import 'support/test_fonts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  testWidgets('Log shows selected summary categories including zero totals', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final db = await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    );
    final repo = Repository(db!);
    final auth = GoogleAuth();
    final controller = AppController(repo, auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => controller.createLocal('Family', 'Robin'));
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });
    await t.pumpWidget(LittleLogApp(controller: controller));
    await t.pumpAndSettle();

    await t.scrollUntilVisible(
      find.byKey(const ValueKey('today-summary')),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('At a glance'), findsOneWidget);

    await t.runAsync(() async {
      await repo.add(
        Feeding(
          id: newId.v4(),
          familyId: controller.family!.id,
          at: DateTime.now(),
          method: 'diaper',
          diaperKind: 'wet',
        ),
      );
      await controller.refresh();
    });
    await t.pump();
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('today-summary')),
      180,
      scrollable: find.byType(Scrollable).first,
    );

    final summary = find.byKey(const ValueKey('today-summary'));
    expect(
      find.descendant(of: summary, matching: find.text('Diapers')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Feeds')),
      findsNothing,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Bottle')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Sleep')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);

    await t.runAsync(() async {
      await repo.add(
        Feeding(
          id: newId.v4(),
          familyId: controller.family!.id,
          at: DateTime.now(),
          method: 'bottle',
          amountMl: 90,
        ),
      );
      await controller.refresh();
    });
    await t.pump();
    expect(
      find.descendant(of: summary, matching: find.text('Nursing')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Bottle')),
      findsOneWidget,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('Today nursing timer freezes and says paused after pause', (
    t,
  ) async {
    final db = await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    );
    final repo = Repository(db!);
    final auth = GoogleAuth();
    final controller = AppController(repo, auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => controller.createLocal('Family', 'Robin'));
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });

    final now = DateTime.now();
    await t.runAsync(() async {
      await repo.saveSession(
        NursingSession(
          id: newId.v4(),
          familyId: controller.family!.id,
          startedAt: now.subtract(const Duration(minutes: 10)),
          segmentAt: now.subtract(const Duration(seconds: 95)),
          side: 'left',
        ),
      );
      await controller.refresh();
    });
    await t.pumpWidget(LittleLogApp(controller: controller));
    await t.pump();
    expect(find.textContaining('timer running'), findsOneWidget);

    await t.runAsync(() => controller.nursingAction('pause'));
    await t.pump();
    final paused = t.widget<Text>(find.textContaining(' · paused')).data!;
    expect(paused, startsWith('1:'));
    expect(paused, isNot(startsWith('10:')));

    await t.pump(const Duration(seconds: 5));
    expect(t.widget<Text>(find.textContaining(' · paused')).data, paused);
  });
  for (final (large, long) in [
    (false, false),
    (false, true),
    (true, false),
    (true, true),
  ]) {
    testWidgets(
      'Today and History share compact nursing totals (${large ? 'large' : 'standard'} text, ${long ? 'hours' : 'minutes'})',
      (t) async {
        t.view.physicalSize = large
            ? const Size(320, 640)
            : const Size(390, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.runAsync(loadTestFonts);
        final total = long ? (large ? '1h43m' : '1h 43m') : '4m';
        final leftSide = long ? 'L 58m' : 'L 2m';
        final rightSide = long ? 'R 44m' : 'R 1m';
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final repo = Repository(db);
        final auth = GoogleAuth();
        final c = AppController(repo, auth, GoogleDrive(auth))..loading = false;
        await t.runAsync(() async {
          await c.createLocal('Family', 'Robin');
          // Summary layout checks are independent of the discovery animation.
          await c.learnSwipeActions();
          await repo.add(
            Feeding(
              id: 'sides',
              familyId: c.family!.id,
              at: DateTime.now(),
              method: 'nursing',
              minutes: 4,
              leftSeconds: long ? 3480 : 125,
              rightSeconds: long ? 2640 : 75,
            ),
          );
          await repo.add(
            Feeding(
              id: 'manual',
              familyId: c.family!.id,
              at: DateTime.now(),
              method: 'nursing',
              minutes: 1,
            ),
          );
          await repo.add(
            Feeding(
              id: 'bottle',
              familyId: c.family!.id,
              at: DateTime.now(),
              method: 'bottle',
              amountMl: 90,
            ),
          );
          await repo.add(
            Feeding(
              id: 'diaper',
              familyId: c.family!.id,
              at: DateTime.now(),
              method: 'diaper',
              diaperKind: 'wet',
            ),
          );
          await repo.add(
            Feeding(
              id: 'sleep',
              familyId: c.family!.id,
              at: DateTime.now().subtract(const Duration(hours: 1)),
              method: 'sleep',
              endedAt: DateTime.now(),
            ),
          );
          await c.refresh();
        });
        addTearDown(() async {
          c.dispose();
          await db.close();
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        final summary = find.byKey(const ValueKey('today-summary'));
        await t.scrollUntilVisible(
          summary,
          180,
          scrollable: find.byType(Scrollable).first,
        );
        for (final label in [total, leftSide, rightSide, 'Nursing']) {
          expect(
            find.descendant(of: summary, matching: find.text(label)),
            findsOneWidget,
          );
        }
        if (!large) {
          final totalFinder = find.descendant(
            of: summary,
            matching: find.text(total),
          );
          final leftFinder = find.descendant(
            of: summary,
            matching: find.text(leftSide),
          );
          expect(
            t.getTopLeft(leftFinder).dx,
            greaterThan(t.getTopLeft(totalFinder).dx),
          );
        }
        final nursing = find.byKey(const ValueKey('today-metric-Nursing'));
        final nursingLabel = find.descendant(
          of: nursing,
          matching: find.text('Nursing'),
        );
        final side = find.descendant(
          of: nursing,
          matching: find.text(rightSide),
        );
        final labelRect = t.getRect(nursingLabel);
        final sideRect = t.getRect(side);
        expect(
          labelRect.overlaps(sideRect),
          false,
          reason: 'Side details must not overlap Nursing',
        );
        expect(t.widget<Text>(side).style!.fontSize, 14);
        expect(find.textContaining('No side'), findsNothing);
        expect(
          find.descendant(of: summary, matching: find.text('Feeds')),
          findsNothing,
        );
        for (final pair in [('Nursing', 'Bottle'), ('Diapers', 'Sleep')]) {
          final left = find.byKey(ValueKey('today-metric-${pair.$1}'));
          final right = find.byKey(ValueKey('today-metric-${pair.$2}'));
          expect(t.getTopLeft(left).dy, closeTo(t.getTopLeft(right).dy, 1));
          expect(t.getSize(left).height, closeTo(t.getSize(right).height, 1));
          final leftLabel = find.descendant(
            of: left,
            matching: find.text(pair.$1),
          );
          final rightLabel = find.descendant(
            of: right,
            matching: find.text(pair.$2),
          );
          expect(
            t.getBottomLeft(leftLabel).dy,
            closeTo(t.getBottomLeft(rightLabel).dy, 1),
          );
        }
        expect(
          t.getSize(find.byKey(const ValueKey('today-metric-Nursing'))).height,
          closeTo(
            t
                .getSize(find.byKey(const ValueKey('today-metric-Diapers')))
                .height,
            1,
          ),
        );
        expect(
          t
              .getTopLeft(
                find.descendant(of: summary, matching: find.text(total)),
              )
              .dy,
          closeTo(
            t
                .getTopLeft(
                  find.descendant(of: summary, matching: find.text('90 ml')),
                )
                .dy,
            1,
          ),
        );

        if (const bool.fromEnvironment('CAPTURE_NURSING')) {
          await Scrollable.ensureVisible(t.element(summary), alignment: 0.1);
          await t.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/nursing46-review/today-${large ? 'large' : 'standard'}-${long ? 'hours' : 'minutes'}.png',
            ),
          );
        }
        await t.tap(find.text('Log'));
        await t.pumpAndSettle();
        expect(find.text(total), findsOneWidget);
        for (final side in [leftSide, rightSide]) {
          expect(find.text(side), findsOneWidget);
        }
        if (const bool.fromEnvironment('CAPTURE_NURSING')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../build/nursing46-review/history-${large ? 'large' : 'standard'}-${long ? 'hours' : 'minutes'}.png',
            ),
          );
        }
        expect(t.takeException(), isNull);
      },
    );
  }
}
