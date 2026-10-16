import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/services/assistant_actions.dart';
import 'package:little_log/services/assistant_history.dart';
import 'siri_actions_test.dart' show makeController, payload;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 14, 12);

  test('all history questions parse; unsupported questions are rejected', () {
    for (final action in assistantHistoryQuestions.keys) {
      expect(AssistantRequest.parse(payload(action, action))?.action, action);
    }
    expect(AssistantRequest.parse(payload('bad', 'last_unknown')), isNull);
  });

  test(
    'queries read durable selected-baby history without writing; feed combines bottle, nursing and solids',
    () async {
      final c = await makeController();
      Feeding record(
        String id,
        String method,
        int minutes, {
        String? kind,
        DateTime? end,
        String? family,
        bool deleted = false,
      }) => Feeding(
        id: id,
        familyId: family ?? c.family!.id,
        method: method,
        at: now.subtract(Duration(minutes: minutes)),
        endedAt: end,
        diaperKind: kind,
        deleted: deleted,
      );
      final records = [
        record('both', 'diaper', 45, kind: 'both'),
        record('dry', 'diaper', 15, kind: 'dry'),
        record('old-wet', 'diaper', 80, kind: 'wet'),
        record('bottle', 'bottle', 30),
        record('nursing', 'nursing', 10),
        record('solids', 'solids', 20),
        record('pumping', 'pumping', 90),
        record(
          'sleep-long',
          'sleep',
          420,
          end: now.subtract(const Duration(hours: 2)),
        ),
        record(
          'sleep-short',
          'sleep',
          240,
          end: now.subtract(const Duration(hours: 3)),
        ),
        record('duration-only', 'sleep', 60),
        record('future', 'diaper', -1, kind: 'both'),
        record('deleted', 'diaper', 0, kind: 'both', deleted: true),
        record('other-baby', 'diaper', 0, kind: 'both', family: 'other'),
      ];
      for (final r in records) {
        await c.repository.add(r);
      }
      // Intentionally stale in-memory history: queries must read saved data.
      expect(c.feeds, isEmpty);
      final before = jsonEncode(
        (await c.repository.feeds(
          c.family!.id,
          includeDeleted: true,
        )).map((r) => r.toJson()).toList(),
      );
      final expected = {
        'last_diaper': ['dry diaper', '15 minutes ago'],
        'last_wet_diaper': ['wet and dirty diaper', '45 minutes ago'],
        'last_dirty_diaper': ['wet and dirty diaper', '45 minutes ago'],
        'last_feed': ['nursing session started', '10 minutes ago'],
        'last_bottle': ['bottle feed', '30 minutes ago'],
        'last_nursing': ['nursing session started', '10 minutes ago'],
        'last_solids': ['solids were logged', '20 minutes ago'],
        'last_sleep': ['sleep started', '1 hour ago'],
        'last_wake': ['wake-up was', '2 hours ago'],
        'last_pumping': [
          'pumping session started',
          '1 hour and 30 minutes ago',
        ],
        'sleep_status': ['no active sleep timer'],
      };
      for (final entry in expected.entries) {
        final answer = await c.performAssistantAction(entry.key, at: now);
        expect(answer, contains('Robin'));
        for (final part in entry.value) {
          expect(answer, contains(part), reason: entry.key);
        }
        expect(c.working, false);
      }
      expect(
        jsonEncode(
          (await c.repository.feeds(
            c.family!.id,
            includeDeleted: true,
          )).map((r) => r.toJson()).toList(),
        ),
        before,
      );
      expect(await c.repository.nursingSession(c.family!.id), isNull);
      expect(await c.repository.activityTimers(c.family!.id), isEmpty);
    },
  );

  test(
    'active and paused nursing, sleep and pumping are reported honestly and preserved',
    () async {
      final c = await makeController();
      final family = c.family!;
      final nursing = NursingSession(
        id: 'active-nursing',
        familyId: family.id,
        startedAt: now.subtract(const Duration(minutes: 8)),
        segmentAt: now.subtract(const Duration(minutes: 2)),
        side: 'left',
        paused: true,
        leftSeconds: 360,
      );
      final sleep = ActivityTimer(
        id: 'active-sleep',
        familyId: family.id,
        method: 'sleep',
        startedAt: now.subtract(const Duration(minutes: 35)),
      );
      final pumping = ActivityTimer(
        id: 'active-pumping',
        familyId: family.id,
        method: 'pumping',
        startedAt: now.subtract(const Duration(minutes: 12)),
      );
      final records = [
        Feeding(
          id: 'prior-sleep',
          familyId: family.id,
          method: 'sleep',
          at: now.subtract(const Duration(hours: 5)),
          endedAt: now.subtract(const Duration(hours: 3)),
        ),
      ];
      String answer(String action) => answerAssistantHistory(
        action: action,
        baby: family,
        records: records,
        timers: [sleep, pumping],
        nursing: nursing,
        now: now,
      );
      expect(answer('last_feed'), contains('paused nursing session started'));
      expect(answer('last_nursing'), contains('8 minutes ago'));
      expect(answer('last_sleep'), contains('active sleep timer started'));
      expect(answer('sleep_status'), contains('35 minutes ago'));
      expect(answer('last_pumping'), contains('active pumping timer started'));
      expect(answer('last_wake'), contains('3 hours ago'));
      expect(answer('last_wake'), contains('An active sleep timer is running'));
      expect(nursing.paused, true);
      expect(nursing.leftSeconds, 360);
      expect(sleep.startedAt, now.subtract(const Duration(minutes: 35)));
      await c.repository.saveSession(nursing);
      await c.repository.startTimer(sleep);
      await c.repository.startTimer(pumping);
      for (final r in records) {
        await c.repository.add(r);
      }
      final originalSession = jsonEncode(
        (await c.repository.nursingSession(family.id))!.toJson(),
      );
      final originalTimers = jsonEncode(
        (await c.repository.activityTimers(
          family.id,
        )).map((t) => t.toJson()).toList(),
      );
      // The dispatcher must read durable timers even when its cached lists are stale.
      expect(c.nursing, isNull);
      expect(c.timers, isEmpty);
      for (final query in [
        'last_feed',
        'last_nursing',
        'last_sleep',
        'last_wake',
        'last_pumping',
        'sleep_status',
      ]) {
        expect(await c.performAssistantAction(query, at: now), answer(query));
      }
      expect(
        jsonEncode((await c.repository.nursingSession(family.id))!.toJson()),
        originalSession,
      );
      expect(
        jsonEncode(
          (await c.repository.activityTimers(
            family.id,
          )).map((t) => t.toJson()).toList(),
        ),
        originalTimers,
      );
    },
  );

  test(
    'missing, future, deleted and other-baby history never fabricates an answer',
    () async {
      final c = await makeController();
      for (final action in assistantHistoryQuestions.keys) {
        final answer = await c.performAssistantAction(action, at: now);
        expect(
          answer,
          contains(action == 'sleep_status' ? 'no active sleep timer' : 'No '),
        );
      }
      final future = Feeding(
        id: 'future',
        familyId: c.family!.id,
        method: 'sleep',
        at: now.add(const Duration(hours: 1)),
        endedAt: now.add(const Duration(hours: 2)),
      );
      final malformedEnd = Feeding(
        id: 'invalid-end',
        familyId: c.family!.id,
        method: 'sleep',
        at: now.subtract(const Duration(hours: 1)),
        endedAt: now.subtract(const Duration(hours: 2)),
      );
      final answer = answerAssistantHistory(
        action: 'last_wake',
        baby: c.family!,
        records: [future, malformedEnd],
        timers: [],
        nursing: null,
        now: now,
      );
      expect(answer, 'No wake-up times are logged for Robin.');
      await expectLater(
        c.performAssistantAction('last_unknown', at: now),
        throwsFormatException,
      );
      final empty = await makeController(baby: false);
      await expectLater(
        empty.performAssistantAction('last_feed', at: now),
        throwsStateError,
      );
    },
  );

  test(
    'calendar dates, UTC timestamps, multi-day history and midnight stay readable',
    () {
      expect(
        historyTime(now.subtract(const Duration(days: 2, hours: 1)), now),
        contains('2 days and 1 hour ago'),
      );
      expect(
        historyTime(now.subtract(const Duration(days: 2)), now),
        contains('October 12'),
      );
      expect(
        historyTime(
          DateTime(2026, 10, 13, 23, 50),
          DateTime(2026, 10, 14, 0, 10),
        ),
        contains('yesterday at'),
      );
      expect(
        historyTime(now.toUtc().subtract(const Duration(minutes: 5)), now),
        contains('5 minutes ago'),
      );
      expect(historyTime(now, now), contains('less than a minute ago'));
    },
  );

  test(
    'switching babies changes the answer rather than leaking the other history',
    () async {
      final c = await makeController();
      final original = c.family!;
      await c.repository.add(
        Feeding(
          id: 'robin-feed',
          familyId: original.id,
          method: 'bottle',
          at: now.subtract(const Duration(minutes: 20)),
        ),
      );
      await c.createLocal('Other family', 'Lila');
      expect(
        await c.performAssistantAction('last_feed', at: now),
        'No feeds are logged for Lila.',
      );
      await c.select(original);
      expect(
        await c.performAssistantAction('last_feed', at: now),
        contains('Robin’s last bottle feed'),
      );
    },
  );

  for (final name in ['app.littlelog/siri', 'app.littlelog/assistant']) {
    test(
      'cold $name query returns an answer, carries query marker and replay does not rerun it',
      () async {
        final c = await makeController();
        final channel = MethodChannel(name);
        final replies = <Map>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'listen') {
                return [payload('read-once', 'last_feed')];
              }
              if (call.method == 'complete') replies.add(call.arguments as Map);
              return true;
            });
        var executions = 0;
        final actions = AssistantActions(channel: channel);
        addTearDown(() {
          actions.dispose();
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        await actions.listen((request) {
          executions++;
          return executeAssistantRequest(c, request);
        });
        for (var i = 0; i < 100 && replies.isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(replies.single['message'], 'No feeds are logged for Robin.');
        expect(replies.single['query'], true);
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              channel.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('received', payload('read-once', 'last_feed')),
              ),
              (_) {},
            );
        expect(executions, 1);
        expect(replies.length, 2);
      },
    );
  }
}
