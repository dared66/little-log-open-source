import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';

class RetryRepository extends Repository {
  RetryRepository(super.db);
  bool failNextFinish = false;
  Completer<void>? finishGate;
  @override
  Future<void> finishSession(NursingSession session, Feeding feed) async {
    if (failNextFinish) {
      failNextFinish = false;
      throw StateError('Storage unavailable. Try again.');
    }
    await finishGate?.future;
    await super.finishSession(session, feed);
  }
}

void main() {
  late Database db;
  late RetryRepository repo;
  late AppController c;
  late NursingSession original;
  Future<void> setup(
    WidgetTester t, {
    bool paused = false,
    bool large = false,
    String side = 'left',
    bool active = true,
  }) async {
    t.view.physicalSize = Size(large ? 320 : 390, 844);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    repo = RetryRepository(db);
    final auth = GoogleAuth();
    c = AppController(repo, auth, GoogleDrive(auth))..loading = false;
    await t.runAsync(() => c.createLocal('QA', 'Robin'));
    final now = DateTime.now();
    original = NursingSession(
      id: 'nursing-test',
      familyId: c.family!.id,
      startedAt: now.subtract(const Duration(minutes: 2)),
      segmentAt: now.subtract(const Duration(seconds: 2)),
      side: side,
      leftSeconds: 47,
      rightSeconds: 13,
      paused: paused,
      note: 'Existing note',
    );
    await t.runAsync(() async {
      if (active) await repo.saveSession(original);
      await c.refresh();
    });
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    openActivity(t.element(find.byType(HomePage)), c, 'nursing');
    await t.pumpAndSettle();
  }

  Future<void> tap(WidgetTester t, String label) async {
    final target = find.text(label);
    await t.ensureVisible(target);
    await t.pumpAndSettle();
    expect(target.hitTestable(), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(target);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> cleanup(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  }

  for (final paused in [false, true]) {
    for (final large in [false, true]) {
      testWidgets('Finish saves once and closes: paused=$paused large=$large', (
        t,
      ) async {
        await setup(t, paused: paused, large: large);
        if (!paused) {
          expect(find.text('Finish nursing'), findsNothing);
          await tap(t, 'Pause nursing');
        }
        final pausedAt = c.nursing!.segmentAt;
        await tap(t, 'Finish nursing');
        expect(find.byType(TimedActivityFlow), findsNothing);
        expect(find.text('Save nursing'), findsNothing);
        expect(c.nursing, isNull);
        expect(c.feeds, hasLength(1));
        final record = c.feeds.single;
        expect(record.id, original.id);
        expect(record.endedAt!.isAtSameMomentAs(pausedAt), isTrue);
        expect(
          record.leftSeconds,
          original.secondsFor('left', record.endedAt!),
        );
        expect(
          record.rightSeconds,
          original.secondsFor('right', record.endedAt!),
        );
        expect(record.note, 'Existing note');
        await t.runAsync(() async {
          expect(await repo.nursingSession(original.familyId), isNull);
          final saved = await repo.feeds(original.familyId);
          expect(saved, hasLength(1));
          expect(saved.single.toJson(), record.toJson());
        });
        await cleanup(t);
      });
    }
  }
  testWidgets(
    'Pause freezes persisted totals; Resume retains the chosen side',
    (t) async {
      await setup(t);
      await tap(t, 'Pause nursing');
      expect(c.nursing!.paused, true);
      expect(find.text('Paused · Left side'), findsOneWidget);
      expect(find.text('Timer running'), findsNothing);
      expect(find.text('Resume nursing'), findsOneWidget);
      final paused = c.nursing!;
      final later = DateTime.now().add(const Duration(hours: 1));
      expect(paused.secondsFor('left', later), paused.leftSeconds);
      expect(paused.secondsFor('right', later), paused.rightSeconds);
      await t.runAsync(() async {
        final stored = (await repo.nursingSession(original.familyId))!;
        expect(stored.toJson(), paused.toJson());
      });
      await tap(t, 'Resume nursing');
      expect(c.nursing!.paused, false);
      expect(c.nursing!.side, 'left');
      expect(c.nursing!.leftSeconds, paused.leftSeconds);
      expect(c.nursing!.rightSeconds, paused.rightSeconds);
      await tap(t, 'Switch to right');
      expect(c.nursing!.side, 'right');
      expect(find.text('Finish nursing'), findsNothing);
      await tap(t, 'Pause nursing');
      await tap(t, 'Finish nursing');
      expect(c.nursing, isNull);
      expect(c.feeds, hasLength(1));
      await cleanup(t);
    },
  );
  testWidgets(
    'Paused session survives close and app restart; Start right explicitly resumes',
    (t) async {
      await setup(t, paused: true);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(c.nursing!.paused, true);
      expect(c.feeds, isEmpty);
      final family = c.family!;
      await t.pumpWidget(const SizedBox());
      c.dispose();
      final auth = GoogleAuth();
      c = AppController(repo, auth, GoogleDrive(auth))
        ..loading = false
        ..family = family;
      await t.runAsync(c.refresh);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      openActivity(t.element(find.byType(HomePage)), c, 'nursing');
      await t.pumpAndSettle();
      expect(find.text('Paused · Left side'), findsOneWidget);
      expect(find.text('Pause nursing'), findsNothing);
      expect(find.text('Switch to right'), findsNothing);
      await tap(t, 'Start right');
      expect(c.nursing!.paused, false);
      expect(c.nursing!.side, 'right');
      expect(c.nursing!.leftSeconds, original.leftSeconds);
      expect(c.nursing!.rightSeconds, original.rightSeconds);
      expect(find.text('Right side running'), findsOneWidget);
      await tap(t, 'Pause nursing');
      expect(find.text('Paused · Right side'), findsOneWidget);
      await tap(t, 'Finish nursing');
      expect(c.nursing, isNull);
      expect(c.feeds, hasLength(1));
      await cleanup(t);
    },
  );
  testWidgets(
    'Finish locks all controls while saving and cannot duplicate the session',
    (t) async {
      await setup(t, paused: true);
      final gate = Completer<void>();
      repo.finishGate = gate;
      await tap(t, 'Finish nursing');
      expect(find.text('Saving…'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Saving…'))
            .onPressed,
        isNull,
      );
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Resume nursing'),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.text('Saving…'));
      await t.runAsync(() async {
        gate.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(c.nursing, isNull);
      expect(c.feeds, hasLength(1));
      await cleanup(t);
    },
  );
  test('Side transition graph excludes all paused time', () {
    final at = DateTime(2026, 10, 2);
    var session = NursingSession(
      id: 'graph',
      familyId: 'family',
      startedAt: at,
      segmentAt: at,
      side: 'left',
    );
    session = session.switchTo('right', at.add(const Duration(seconds: 10)));
    session = session.pause(at.add(const Duration(seconds: 25)));
    expect(
      session.pause(at.add(const Duration(seconds: 30))).toJson(),
      session.toJson(),
    );
    session = session.resume(at.add(const Duration(seconds: 40)));
    expect(
      session.resume(at.add(const Duration(seconds: 41))).toJson(),
      session.toJson(),
    );
    session = session.switchTo('left', at.add(const Duration(seconds: 55)));
    final result = session.finish(at.add(const Duration(seconds: 65)), '');
    expect(result.leftSeconds, 20);
    expect(result.rightSeconds, 30);
    expect(result.minutes, 1);
  });
  for (final side in ['left', 'right']) {
    testWidgets('Idle starts $side once, pauses and finishes with one tap', (
      t,
    ) async {
      await setup(t, active: false);
      expect(find.text('Finish nursing'), findsNothing);
      expect(find.text('Pause nursing'), findsNothing);
      await tap(t, 'Start $side');
      expect(c.nursing!.side, side);
      expect(c.nursing!.paused, false);
      expect(c.feeds, isEmpty);
      await tap(t, 'Pause nursing');
      expect(c.nursing!.paused, true);
      await tap(t, 'Finish nursing');
      expect(c.nursing, isNull);
      expect(c.feeds, hasLength(1));
      expect(find.byType(TimedActivityFlow), findsNothing);
      await cleanup(t);
    });
  }
  testWidgets('Dismissing during Finish still commits exactly once', (t) async {
    await setup(t, paused: true);
    final gate = Completer<void>();
    repo.finishGate = gate;
    await tap(t, 'Finish nursing');
    Navigator.of(t.element(find.byType(TimedActivityFlow))).pop();
    await t.pumpAndSettle();
    await t.runAsync(() async {
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.nursing, isNull);
    expect(c.feeds, hasLength(1));
    expect(find.byType(TimedActivityFlow), findsNothing);
    expect(t.takeException(), isNull);
    await cleanup(t);
  });
  testWidgets('Failed Finish preserves timer and offers one safe retry', (
    t,
  ) async {
    await setup(t, paused: true);
    repo.failNextFinish = true;
    await tap(t, 'Finish nursing');
    expect(find.byType(TimedActivityFlow), findsOneWidget);
    expect(find.text('Storage unavailable. Try again.'), findsOneWidget);
    expect(c.nursing!.id, original.id);
    expect(c.feeds, isEmpty);
    expect(c.recording, false);
    await tap(t, 'Finish nursing');
    expect(c.nursing, isNull);
    expect(c.feeds, hasLength(1));
    expect(find.byType(TimedActivityFlow), findsNothing);
    await cleanup(t);
  });
}
