import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/assistant_actions.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';

Future<AppController> makeController({bool baby = true}) async {
  final db = await databaseFactoryMemory.openDatabase(newId.v4());
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth))
    ..loading = false;
  if (baby) await c.createLocal('Test family', 'Robin');
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

Map<String, Object> payload(
  String id,
  String action, {
  String? kind,
  DateTime? at,
}) {
  final now = at ?? DateTime.now();
  return {
    'id': id,
    'action': action,
    'at': now.millisecondsSinceEpoch,
    'deadline': DateTime.now()
        .add(const Duration(seconds: 15))
        .millisecondsSinceEpoch,
    'kind': ?kind,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['wet', 'dirty', 'both', 'dry']) {
    test(
      'Siri saves $kind diaper durably at the requested time for the selected baby',
      () async {
        final c = await makeController();
        final at = DateTime.now().subtract(const Duration(minutes: 1));
        final request = AssistantRequest.parse(
          payload('one', 'add_diaper', kind: kind, at: at),
        )!;
        final message = await executeAssistantRequest(c, request);
        expect(message, contains('Robin'));
        expect(c.feeds.single.diaperKind, kind);
        expect(
          c.feeds.single.at.millisecondsSinceEpoch,
          at.millisecondsSinceEpoch,
        );
        await c.refresh();
        expect(c.feeds.single.diaperKind, kind);
        expect(
          (await c.repository.feeds(c.family!.id)).single.diaperKind,
          kind,
        );
      },
    );
  }

  for (final side in ['left', 'right']) {
    test(
      'Siri starts $side nursing, preserves an active session, and resumes a paused session',
      () async {
        final c = await makeController();
        await c.performAssistantAction('nursing_$side', at: DateTime.now());
        final id = c.nursing!.id, started = c.nursing!.startedAt;
        expect(c.nursing!.side, side);
        final other = side == 'left' ? 'right' : 'left';
        expect(
          await c.performAssistantAction('nursing_$other', at: DateTime.now()),
          contains('already running on the $side'),
        );
        expect(c.nursing!.id, id);
        expect(c.nursing!.startedAt, started);
        await c.nursingAction('pause');
        await c.performAssistantAction('nursing_$other', at: DateTime.now());
        expect(c.nursing!.paused, false);
        expect(c.nursing!.side, other);
        expect(c.nursing!.id, id);
      },
    );
  }

  test(
    'Siri starts sleep once and reports an existing timer honestly',
    () async {
      final c = await makeController();
      await c.performAssistantAction('sleep', at: DateTime.now());
      final timer = c.timers.single;
      expect(
        await c.performAssistantAction('sleep', at: DateTime.now()),
        contains('already running'),
      );
      await c.refresh();
      expect(c.timers.single.id, timer.id);
      expect(c.timers.single.startedAt, timer.startedAt);
    },
  );

  test(
    'Siri rejects missing baby, unfinished setup, busy state, and invalid requests',
    () async {
      final c = await makeController(baby: false);
      await expectLater(
        c.performAssistantAction('sleep', at: DateTime.now()),
        throwsStateError,
      );
      await c.createLocal('Test family', 'Robin');
      c.onboardingSyncedSetup = true;
      await expectLater(
        c.performAssistantAction('sleep', at: DateTime.now()),
        throwsStateError,
      );
      c.onboardingSyncedSetup = false;
      c.switchingBaby = true;
      await expectLater(
        c.performAssistantAction('add_diaper', kind: 'wet', at: DateTime.now()),
        throwsStateError,
      );
      c.switchingBaby = false;
      await expectLater(
        c.performAssistantAction(
          'add_diaper',
          kind: 'unknown',
          at: DateTime.now(),
        ),
        throwsFormatException,
      );
      await expectLater(
        c.performAssistantAction('unknown', at: DateTime.now()),
        throwsFormatException,
      );
      expect(c.feeds, isEmpty);
      expect(c.working, false);
      expect(
        AssistantRequest.parse(payload('x', 'add_diaper', kind: 'unknown')),
        isNull,
      );
      expect(AssistantRequest.parse(payload('x', 'remove_all')), isNull);
    },
  );

  test(
    'cold request waits for load and expires without making a late entry',
    () async {
      final c = await makeController();
      c.loading = true;
      final request = AssistantRequest.parse(
        payload('x', 'add_diaper', kind: 'wet'),
      )!;
      final result = executeAssistantRequest(c, request);
      await Future<void>.delayed(Duration.zero);
      expect(c.feeds, isEmpty);
      c.loading = false;
      await c.refresh();
      expect(await result, contains('Added a wet diaper'));
      final expired = AssistantRequest(
        id: 'expired',
        action: 'add_diaper',
        kind: 'wet',
        at: DateTime.now(),
        deadline: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      await expectLater(executeAssistantRequest(c, expired), throwsStateError);
      expect(c.feeds.length, 1);
    },
  );

  for (final method in ['sleep', 'pumping']) {
    test(
      'Siri starts and finishes $method once with a durable saved duration',
      () async {
        final c = await makeController();
        await c.performAssistantAction(method, at: DateTime.now());
        final timer = c.timers.single;
        expect(
          await c.performAssistantAction(method, at: DateTime.now()),
          contains('already running'),
        );
        expect(c.timers.single.id, timer.id);
        if (method == 'pumping') {
          await c.performLiveTimerAction(
            sessionId: timer.id,
            familyId: timer.familyId,
            method: method,
            action: 'pause',
            at: DateTime.now(),
          );
        }
        await c.performAssistantAction(
          'finish_$method',
          at: DateTime.now(),
          amount: method == 'pumping' ? 2 : null,
          unit: method == 'pumping' ? 'oz' : null,
        );
        expect(c.timers, isEmpty);
        await c.refresh();
        expect(c.feeds.single.id, timer.id);
        expect(c.feeds.single.endedAt, isNotNull);
        if (method == 'pumping') {
          expect(c.feeds.single.amountMl, closeTo(59.147059125, .00001));
        }
        await expectLater(
          c.performAssistantAction(
            'finish_$method',
            at: DateTime.now(),
            amount: 90,
            unit: 'ml',
          ),
          throwsStateError,
        );
        expect(c.feeds.length, 1);
      },
    );
  }

  test(
    'Siri finishes nursing without losing side totals or saved notes',
    () async {
      final c = await makeController();
      await c.performAssistantAction('nursing_left', at: DateTime.now());
      final id = c.nursing!.id;
      final now = DateTime.now();
      await c.repository.saveSession(
        NursingSession(
          id: id,
          familyId: c.family!.id,
          startedAt: now.subtract(const Duration(minutes: 10)),
          segmentAt: now,
          side: 'left',
          leftSeconds: 180,
          rightSeconds: 120,
          paused: true,
          note: 'Saved session note',
        ),
      );
      await c.refresh();
      await c.performAssistantAction('finish_nursing', at: DateTime.now());
      expect(c.nursing, isNull);
      await c.refresh();
      expect(c.feeds.single.id, id);
      expect(c.feeds.single.leftSeconds, 180);
      expect(c.feeds.single.rightSeconds, 120);
      expect(c.feeds.single.note, 'Saved session note');
      await expectLater(
        c.performAssistantAction('finish_nursing', at: DateTime.now()),
        throwsStateError,
      );
      expect(c.feeds.length, 1);
    },
  );

  test(
    'Invalid pumped amounts preserve the timer until a valid amount is saved',
    () async {
      final c = await makeController();
      await c.performAssistantAction('pumping', at: DateTime.now());
      final id = c.timers.single.id;
      await c.performLiveTimerAction(
        sessionId: id,
        familyId: c.family!.id,
        method: 'pumping',
        action: 'pause',
        at: DateTime.now(),
      );
      for (final amount in [0.0, -1.0, double.nan, 2001.0]) {
        await expectLater(
          c.performAssistantAction(
            'finish_pumping',
            at: DateTime.now(),
            amount: amount,
            unit: 'ml',
          ),
          throwsFormatException,
        );
        expect(c.timers.single.id, id);
        expect(c.feeds, isEmpty);
      }
      await c.performAssistantAction(
        'finish_pumping',
        at: DateTime.now(),
        amount: 90,
        unit: 'ml',
      );
      expect(c.feeds.single.amountMl, 90);
    },
  );

  test('a failed local save produces no success response', () async {
    final c = await makeController();
    await c.repository.db.close();
    await expectLater(
      c.performAssistantAction('add_diaper', kind: 'wet', at: DateTime.now()),
      throwsA(anything),
    );
    expect(c.feeds, isEmpty);
    expect(c.working, false);
  });

  test('a failed nursing start produces no success response', () async {
    final c = await makeController();
    await c.repository.db.close();
    await expectLater(
      c.performAssistantAction('nursing_left', at: DateTime.now()),
      throwsA(anything),
    );
    expect(c.nursing, isNull);
    expect(c.recording, false);
    expect(c.working, false);
  });

  test(
    'assistant activities stay with the selected baby across switches',
    () async {
      final c = await makeController();
      final robin = c.family!;
      for (final action in ['sleep', 'pumping', 'nursing_left']) {
        await c.performAssistantAction(action, at: DateTime.now());
      }
      final nursingId = c.nursing!.id;
      final timerIds = c.timers.map((timer) => timer.id).toSet();
      await c.createLocal('Second family', 'Wren');
      final wren = c.family!;
      for (final action in [
        'finish_sleep',
        'finish_pumping',
        'finish_nursing',
      ]) {
        await expectLater(
          c.performAssistantAction(
            action,
            at: DateTime.now(),
            amount: 90,
            unit: 'ml',
          ),
          throwsStateError,
        );
      }
      await c.performAssistantAction(
        'add_diaper',
        kind: 'dirty',
        at: DateTime.now(),
      );
      expect(c.feeds.single.familyId, wren.id);
      await c.select(robin);
      expect(c.feeds, isEmpty);
      expect(c.nursing!.id, nursingId);
      expect(c.timers.map((timer) => timer.id).toSet(), timerIds);
      await c.nursingAction('pause');
      final pump = c.timers.singleWhere((timer) => timer.method == 'pumping');
      await c.performLiveTimerAction(
        sessionId: pump.id,
        familyId: pump.familyId,
        method: 'pumping',
        action: 'pause',
        at: DateTime.now(),
      );
      for (final action in [
        'finish_sleep',
        'finish_pumping',
        'finish_nursing',
      ]) {
        await c.performAssistantAction(
          action,
          at: DateTime.now(),
          amount: 90,
          unit: 'ml',
        );
      }
      expect(c.feeds.length, 3);
      expect(c.feeds.every((record) => record.familyId == robin.id), isTrue);
      await c.select(wren);
      expect(c.feeds.single.diaperKind, 'dirty');
      expect(c.nursing, isNull);
      expect(c.timers, isEmpty);
    },
  );

  test(
    'native nursing callback returns an error when the write fails',
    () async {
      final c = await makeController();
      await c.repository.db.close();
      const channel = MethodChannel('test/assistant-write-failure');
      final reply = Completer<Map>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'listen') {
              return [payload('failed-start', 'nursing_right')];
            }
            if (call.method == 'complete') {
              reply.complete(call.arguments as Map);
            }
            return null;
          });
      final actions = AssistantActions(channel: channel);
      addTearDown(() {
        actions.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await actions.listen((request) => executeAssistantRequest(c, request));
      final response = await reply.future;
      expect(response['error'], isNotEmpty);
      expect(response.containsKey('message'), isFalse);
      expect(c.nursing, isNull);
      expect(c.working, isFalse);
    },
  );

  test(
    'native cold delivery and duplicate callbacks save a diaper once and acknowledge only after saving',
    () async {
      final c = await makeController();
      const channel = MethodChannel('test/siri');
      final replies = <Map>[];
      final request = payload('same', 'add_diaper', kind: 'wet');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'listen') return [request];
            if (call.method == 'complete') {
              expect(c.feeds.length, 1);
              replies.add(call.arguments as Map);
            }
            return null;
          });
      final siri = AssistantActions(channel: channel);
      addTearDown(() {
        siri.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await siri.listen((request) => executeAssistantRequest(c, request));
      final delivered = Completer<void>();
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('received', request),
            ),
            (_) => delivered.complete(),
          );
      await delivered.future;
      expect(c.feeds.length, 1);
      expect(replies.length, 2);
      expect(
        replies.every(
          (reply) => reply['message'] == 'Added a wet diaper for Robin.',
        ),
        true,
      );
    },
  );

  test('cancelled cold request does not log after startup completes', () async {
    final c = await makeController();
    c.loading = true;
    const channel = MethodChannel('test/siri-cancel');
    final reply = Completer<Map>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'listen') {
            return [payload('cancel-me', 'add_diaper', kind: 'wet')];
          }
          if (call.method == 'complete') reply.complete(call.arguments as Map);
          return null;
        });
    final siri = AssistantActions(channel: channel);
    addTearDown(() {
      siri.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await siri.listen((request) => executeAssistantRequest(c, request));
    await Future<void>.delayed(Duration.zero);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('cancelled', 'cancel-me'),
          ),
          (_) {},
        );
    c.loading = false;
    await c.refresh();
    expect((await reply.future)['error'], isNotNull);
    expect(c.feeds, isEmpty);
  });
  test(
    'cancellation arriving before the cold payload prevents a save',
    () async {
      final c = await makeController();
      const channel = MethodChannel('test/siri-early-cancel');
      final pending = Completer<List<Object>>(), reply = Completer<Map>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'listen') return pending.future;
            if (call.method == 'complete') {
              reply.complete(call.arguments as Map);
            }
            return null;
          });
      final siri = AssistantActions(channel: channel);
      addTearDown(() {
        siri.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      final listening = siri.listen(
        (request) => executeAssistantRequest(c, request),
      );
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('cancelled', 'early'),
            ),
            (_) {},
          );
      pending.complete([payload('early', 'add_diaper', kind: 'wet')]);
      await listening;
      expect((await reply.future)['error'], isNotNull);
      expect(c.feeds, isEmpty);
    },
  );
}
