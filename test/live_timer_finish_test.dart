import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'elapsed_icon_preference_test.dart' show localController;
import 'support/test_fonts.dart';
import 'support/scroll_to.dart';

void main() {
  testWidgets(
    'finish targets the timer baby and repeated or stale taps save once',
    (t) async {
      final c = await localController(t);
      final baby = c.family!;
      final start = DateTime.now().subtract(const Duration(minutes: 10));
      final stop = start.add(const Duration(minutes: 8));
      final timer = ActivityTimer(
        id: 'sleep-original',
        familyId: baby.id,
        method: 'sleep',
        startedAt: start,
      );
      await t.runAsync(() async {
        await c.repository.startTimer(timer);
        await c.createLocal('Other family', 'Other baby');
        await c.finishLiveTimer(
          sessionId: timer.id,
          familyId: baby.id,
          method: 'sleep',
          at: stop,
        );
        await c.finishLiveTimer(
          sessionId: timer.id,
          familyId: baby.id,
          method: 'sleep',
          at: DateTime.now(),
        );
        final saved = await c.repository.feeds(baby.id);
        expect(saved, hasLength(1));
        expect(saved.single.endedAt!.isAtSameMomentAs(stop), isTrue);
        expect(c.feeds, isEmpty);
        expect(c.family!.id, isNot(baby.id));
        await c.repository.startTimer(
          ActivityTimer(
            id: 'replacement',
            familyId: baby.id,
            method: 'sleep',
            startedAt: stop,
          ),
        );
        await c.finishLiveTimer(
          sessionId: timer.id,
          familyId: baby.id,
          method: 'sleep',
          at: DateTime.now(),
        );
        expect(
          (await c.repository.activityTimers(baby.id)).single.id,
          'replacement',
        );
      });
    },
  );

  testWidgets(
    'nursing preserves both sides and stopped pumping survives reload until amount is saved',
    (t) async {
      final c = await localController(t);
      final baby = c.family!;
      final start = DateTime.now().subtract(const Duration(minutes: 10));
      final stop = start.add(const Duration(minutes: 9));
      final session = NursingSession(
        id: 'nursing',
        familyId: baby.id,
        startedAt: start,
        segmentAt: start.add(const Duration(minutes: 5)),
        side: 'right',
        leftSeconds: 300,
        note: 'Keep note',
      );
      final pump = ActivityTimer(
        id: 'pump',
        familyId: baby.id,
        method: 'pumping',
        startedAt: start,
      );
      await t.runAsync(() async {
        await c.repository.saveSession(session);
        await c.repository.startTimer(pump);
        await c.performLiveTimerAction(
          sessionId: session.id,
          familyId: baby.id,
          method: 'nursing',
          action: 'pause',
          at: stop,
        );
        await c.finishLiveTimer(
          sessionId: session.id,
          familyId: baby.id,
          method: 'nursing',
          at: stop,
        );
        final nursing = (await c.repository.feeds(baby.id)).single;
        expect(nursing.leftSeconds, 300);
        expect(nursing.rightSeconds, 240);
        expect(nursing.note, 'Keep note');
        expect(await c.repository.nursingSession(baby.id), isNull);
        await c.performLiveTimerAction(
          sessionId: pump.id,
          familyId: baby.id,
          method: 'pumping',
          action: 'pause',
          at: stop,
        );
        await c.finishLiveTimer(
          sessionId: pump.id,
          familyId: baby.id,
          method: 'pumping',
          at: stop,
        );
        await c.finishLiveTimer(
          sessionId: pump.id,
          familyId: baby.id,
          method: 'pumping',
          at: DateTime.now(),
        );
        final stopped = (await c.repository.activityTimers(baby.id)).single;
        expect(stopped.stoppedAt!.isAtSameMomentAs(stop), isTrue);
        expect(
          ActivityTimer.fromJson(stopped.toJson()).elapsedAt(DateTime.now()),
          const Duration(minutes: 9),
        );
        expect(await c.repository.feeds(baby.id), hasLength(1));
        await c.addActivity(
          method: 'pumping',
          at: stopped.startedAt,
          endedAt: stopped.stoppedAt,
          amountMl: 85,
          timer: stopped,
          expectedFamilyId: baby.id,
        );
        expect(await c.repository.activityTimers(baby.id), isEmpty);
        final saved = (await c.repository.feeds(
          baby.id,
        )).singleWhere((f) => f.method == 'pumping');
        expect(saved.amountMl, 85);
        expect(saved.endedAt!.isAtSameMomentAs(stop), isTrue);
      });
    },
  );

  testWidgets('native stop handoff retries safely after acknowledgment fails', (
    t,
  ) async {
    final c = await localController(t);
    final start = DateTime.now().subtract(const Duration(minutes: 5));
    final stop = DateTime.now().subtract(const Duration(minutes: 1));
    final timer = ActivityTimer(
      id: 'native-sleep',
      familyId: c.family!.id,
      method: 'sleep',
      startedAt: start,
    );
    await t.runAsync(() => c.repository.startTimer(timer));
    final pending = <Map<String, Object?>>[
      {
        'id': timer.id,
        'familyId': timer.familyId,
        'method': 'sleep',
        'stoppedAt': stop.millisecondsSinceEpoch,
      },
    ];
    var failAcknowledgment = true;
    const channel = MethodChannel('little_log/live_activity');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'pendingStops') return List.of(pending);
      if (call.method == 'acknowledgeStop') {
        if (failAcknowledgment) {
          throw PlatformException(code: 'storage-unavailable');
        }
        pending.removeWhere((request) => request['id'] == call.arguments);
      }
      return null;
    });
    addTearDown(() {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await t.runAsync(c.processLiveTimerStops);
    expect(pending, hasLength(1));
    failAcknowledgment = false;
    await t.runAsync(c.processLiveTimerStops);
    expect(pending, isEmpty);
    final feeds = await t.runAsync(() => c.repository.feeds(timer.familyId));
    expect(feeds, hasLength(1));
    expect(
      feeds!.single.endedAt!.millisecondsSinceEpoch,
      stop.millisecondsSinceEpoch,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  for (final large in [false, true]) {
    testWidgets(
      'live cards finish directly and pumping opens a durable stopped review: large=$large',
      (t) async {
        const nativeChannel = MethodChannel('little_log/live_activity');
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          nativeChannel,
          (call) async => call.method == 'pendingStops' ? <Object?>[] : null,
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            nativeChannel,
            null,
          ),
        );
        t.view.physicalSize = Size(large ? 320 : 390, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.runAsync(loadTestFonts);
        final c = await localController(t);
        final now = DateTime.now();
        await t.runAsync(() async {
          await c.repository.startTimer(
            ActivityTimer(
              id: 'sleep',
              familyId: c.family!.id,
              method: 'sleep',
              startedAt: now.subtract(const Duration(hours: 1)),
            ),
          );
          await c.repository.startTimer(
            ActivityTimer(
              id: 'pump',
              familyId: c.family!.id,
              method: 'pumping',
              startedAt: now.subtract(const Duration(minutes: 15)),
            ),
          );
          await c.refresh();
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        final finishSleep = find.byKey(const ValueKey('finish-live-sleep'));
        await scrollTo(t, finishSleep);
        await t.runAsync(() async {
          await t.tap(finishSleep);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        expect(c.feeds.single.method, 'sleep');
        expect(find.byType(TimedActivityFlow), findsNothing);
        expect(find.byKey(const ValueKey('finish-live-pumping')), findsNothing);
        final pausePump = find.byKey(const ValueKey('pause-live-pumping'));
        await scrollTo(t, pausePump);
        await t.runAsync(() async {
          await t.tap(pausePump);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        expect(c.timers.single.paused, isTrue);
        expect(
          find.byKey(const ValueKey('resume-live-pumping')),
          findsOneWidget,
        );
        final finishPump = find.byKey(const ValueKey('finish-live-pumping'));
        await scrollTo(t, finishPump);
        await t.runAsync(() async {
          await t.tap(finishPump);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        await t.runAsync(() async {
          for (var i = 0; i < 100 && c.recording; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await t.pumpAndSettle();
        final stopped = c.timers.single.stoppedAt;
        expect(stopped, isNotNull);
        expect(find.text('Save pumping'), findsOneWidget);
        expect(find.text('Back to timer'), findsNothing);
        await t.pump(const Duration(seconds: 5));
        expect(c.timers.single.stoppedAt, stopped);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
