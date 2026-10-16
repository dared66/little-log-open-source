import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/live_activity.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'elapsed_icon_preference_test.dart' show localController;
import 'support/test_fonts.dart';
import 'support/scroll_to.dart';

void main() {
  testWidgets(
    'discarding a resumed nursing session preserves its saved portion',
    (t) async {
      final c = await localController(t);
      await t.runAsync(() async {
        final start = DateTime.now().subtract(const Duration(hours: 1));
        final saved = NursingSession(
          id: 'saved',
          familyId: c.family!.id,
          startedAt: start,
          segmentAt: start,
          side: 'left',
          note: 'Original note',
        ).finish(start.add(const Duration(minutes: 5)), 'owner');
        await c.repository.add(saved);
        await c.reopenNursing(saved, 'right');
        final resumed = c.nursing!;
        await c.discardNursingSession(resumed);
        final restored = c.feeds.single;
        expect(restored.id, resumed.id);
        expect(restored.leftSeconds, 300);
        expect(restored.rightSeconds, 0);
        expect(restored.endedAt!.isAtSameMomentAs(saved.endedAt!), isTrue);
        expect(restored.note, 'Original note');
        expect(restored.synced, isFalse);
        expect(c.nursing, isNull);
        await c.repository.merge([saved]);
        expect(
          (await c.repository.feeds(c.family!.id)).length,
          1,
          reason: 'A delayed sync must not restore the tombstoned original too',
        );
      });
    },
  );

  testWidgets(
    'pumping pause/resume excludes breaks and only paused sessions finish',
    (t) async {
      final c = await localController(t);
      final familyId = c.family!.id;
      final start = DateTime.now().subtract(const Duration(hours: 1));
      var timer = ActivityTimer(
        id: 'pump',
        familyId: familyId,
        method: 'pumping',
        startedAt: start,
      );
      Future<bool> action(String name, int minute, {int? revision}) =>
          c.performLiveTimerAction(
            sessionId: timer.id,
            familyId: familyId,
            method: 'pumping',
            action: name,
            at: start.add(Duration(minutes: minute)),
            expectedRevision: revision,
          );
      await t.runAsync(() async {
        await c.repository.startTimer(timer);
        await c.refresh();
        await expectLater(action('finish', 10), throwsStateError);
        await action('pause', 10, revision: 0);
        timer = (await c.repository.activityTimers(familyId)).single;
        expect(timer.paused, isTrue);
        expect(
          timer.elapsedAt(start.add(const Duration(minutes: 20))),
          const Duration(minutes: 10),
        );
        final snapshot = LiveActivity.snapshots('Robin', null, [timer]).single;
        expect(snapshot['phase'], 'paused');
        expect(snapshot['elapsedSeconds'], 600);
        await action('resume', 20, revision: 1);
        expect(
          await action('finish', 25, revision: 1),
          isFalse,
          reason: 'Old paused Finish cannot end a resumed session',
        );
        timer = (await c.repository.activityTimers(familyId)).single;
        expect(
          timer.elapsedAt(start.add(const Duration(minutes: 25))),
          const Duration(minutes: 15),
        );
        await action('pause', 30, revision: 2);
        timer = ActivityTimer.fromJson(
          (await c.repository.activityTimers(familyId)).single.toJson(),
        );
        expect(
          timer.elapsedAt(start.add(const Duration(minutes: 50))),
          const Duration(minutes: 20),
        );
        await action('finish', 40, revision: 3);
        timer = (await c.repository.activityTimers(familyId)).single;
        expect(timer.phase, 'review');
        expect(
          timer.stoppedAt!.isAtSameMomentAs(
            start.add(const Duration(minutes: 30)),
          ),
          isTrue,
        );
        await action('resume', 45, revision: 4);
        expect(
          (await c.repository.activityTimers(familyId)).single.phase,
          'review',
        );
        await c.addActivity(
          method: 'pumping',
          at: timer.startedAt,
          endedAt: timer.stoppedAt,
          amountMl: 90,
          timer: timer,
          expectedFamilyId: familyId,
        );
        final saved = c.feeds.single;
        expect(saved.details['activeSeconds'], 1200);
        final portable = FamilyCsv.decode(
          FamilyCsv(c.family!, [saved]).encode(),
        ).feeds.single;
        expect(portable.details['activeSeconds'], 1200);
        expect(await c.repository.activityTimers(familyId), isEmpty);
      });
    },
  );

  testWidgets(
    'nursing stays live when paused; stale Finish cannot finish an active session',
    (t) async {
      final c = await localController(t);
      final start = DateTime.now().subtract(const Duration(minutes: 30));
      final session = NursingSession(
        id: 'nurse',
        familyId: c.family!.id,
        startedAt: start,
        segmentAt: start,
        side: 'left',
      );
      await t.runAsync(() async {
        await c.repository.saveSession(session);
        await c.refresh();
        await expectLater(
          c.finishLiveTimer(
            sessionId: session.id,
            familyId: session.familyId,
            method: 'nursing',
            at: start.add(const Duration(minutes: 10)),
          ),
          throwsStateError,
        );
        await c.performLiveTimerAction(
          sessionId: session.id,
          familyId: session.familyId,
          method: 'nursing',
          action: 'pause',
          at: start.add(const Duration(minutes: 10)),
          expectedRevision: 0,
        );
        final frozen = LiveActivity.snapshots('Robin', c.nursing, []).single;
        expect(frozen['phase'], 'paused');
        expect(frozen['elapsedSeconds'], 600);
        await c.performLiveTimerAction(
          sessionId: session.id,
          familyId: session.familyId,
          method: 'nursing',
          action: 'resume',
          at: start.add(const Duration(minutes: 20)),
          expectedRevision: 1,
        );
        expect(
          await c.performLiveTimerAction(
            sessionId: session.id,
            familyId: session.familyId,
            method: 'nursing',
            action: 'finish',
            at: start.add(const Duration(minutes: 21)),
            expectedRevision: 1,
          ),
          isFalse,
        );
        await c.performLiveTimerAction(
          sessionId: session.id,
          familyId: session.familyId,
          method: 'nursing',
          action: 'pause',
          at: start.add(const Duration(minutes: 25)),
          expectedRevision: 2,
        );
        await c.finishLiveTimer(
          sessionId: session.id,
          familyId: session.familyId,
          method: 'nursing',
          at: DateTime.now(),
        );
        expect(c.nursing, isNull);
        expect(c.feeds.single.leftSeconds, 900);
        expect(
          c.feeds.single.endedAt!.isAtSameMomentAs(
            start.add(const Duration(minutes: 25)),
          ),
          isTrue,
        );
      });
    },
  );

  for (final method in ['nursing', 'sleep', 'pumping']) {
    testWidgets(
      '$method discard always confirms, cancel preserves its session',
      (t) async {
        await t.runAsync(loadTestFonts);
        final c = await localController(t);
        await t.runAsync(() async {
          if (method == 'nursing') {
            await c.nursingAction('left');
          } else {
            await c.startActivityTimer(method);
          }
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        openActivity(t.element(find.byType(HomePage)), c, method);
        await t.pumpAndSettle();
        await scrollTo(t, find.text('Discard session'));
        await t.tap(find.text('Discard session'));
        await t.pumpAndSettle();
        expect(find.text('Discard $method session?'), findsOneWidget);
        await t.tap(find.text('Keep session'));
        await t.pumpAndSettle();
        expect(
          method == 'nursing' ? c.nursing != null : c.timers.isNotEmpty,
          isTrue,
        );
        await t.tap(find.text('Discard session'));
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(find.widgetWithText(TextButton, 'Discard session').last);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        expect(c.nursing, isNull);
        expect(c.timers, isEmpty);
        expect(c.feeds, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
