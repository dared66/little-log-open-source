import 'dart:io';
import 'dart:async';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/volume.dart';
import 'package:sembast/sembast_memory.dart';
import 'support/test_fonts.dart';

Feeding record(String id, DateTime at, {String method = 'diaper'}) => Feeding(
  id: id,
  familyId: 'synthetic',
  at: at,
  method: method,
  diaperKind: method == 'diaper' ? 'wet' : null,
  leftSeconds: method == 'nursing' ? 1006 : null,
  rightSeconds: method == 'nursing' ? 758 : null,
  endedAt: method == 'nursing' ? at.add(const Duration(minutes: 30)) : null,
  details: method == 'diaper' ? const {'rash': false} : const {},
  author: 'Caregiver',
);

void main() {
  testWidgets('demo waits for a visible record and respects reduced motion', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final scroll = ScrollController();
    var starts = 0;
    Widget screen({bool reducedMotion = false}) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reducedMotion),
        child: Scaffold(
          body: SingleChildScrollView(
            controller: scroll,
            child: Column(
              children: [
                const SizedBox(height: 1000),
                RecordRow(
                  record: record('visible', DateTime.now()),
                  volumeUnit: VolumeUnit.ml,
                  swipeDemoEnabled: true,
                  onSwipeDemoStart: () {
                    starts++;
                    return true;
                  },
                  onSwipeDemoEnd: (_) async {},
                  onEdit: () async {},
                  onDelete: () async {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpWidget(screen());
    await t.pump(const Duration(seconds: 1));
    expect(starts, 0);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await t.pump();
    await t.pump(const Duration(milliseconds: 701));
    expect(starts, 1);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(screen(reducedMotion: true));
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(starts, 1);
    await t.pumpWidget(const SizedBox());
    scroll.dispose();
  });
  test('elapsed handles midnight, long gaps and future timestamps', () {
    final now = DateTime.utc(2026, 10, 9, 0, 20);
    expect(
      elapsedActivityTime(now.subtract(const Duration(minutes: 39)), now),
      '39m ago',
    );
    expect(
      elapsedActivityTime(
        now.subtract(const Duration(hours: 4, minutes: 28)),
        now,
      ),
      '4h 28m ago',
    );
    expect(
      elapsedActivityTime(now.subtract(const Duration(days: 2, hours: 3)), now),
      '2d 3h ago',
    );
    expect(elapsedActivityTime(now, now), 'Just now');
    expect(
      elapsedActivityTime(now.add(const Duration(minutes: 2)), now),
      'In the future',
    );
  });

  test(
    'latest means latest per activity across all days, with stable ties',
    () {
      final now = DateTime.utc(2026, 10, 9);
      final entries = [
        record('a', now),
        record('z', now),
        record('old', now.subtract(const Duration(days: 1))),
        record(
          'nursing',
          now.subtract(const Duration(days: 2)),
          method: 'nursing',
        ),
        record('deleted', now.add(const Duration(hours: 1))).asDeleted(),
      ];
      expect(latestActivityIds(entries), {'z', 'nursing'});
      final sorted = entries.where((r) => !r.deleted).toList()
        ..sort(newestRecordFirst);
      expect(sorted.map((r) => r.id), ['z', 'a', 'old', 'nursing']);
    },
  );

  test('completed demo persists independently of baby selection', () async {
    final db = await databaseFactoryMemory.openDatabase(newId.v4());
    final repo = Repository(db);
    expect(await repo.swipeDemoSeen(), false);
    await repo.saveSwipeDemoSeen();
    expect(await Repository(db).swipeDemoSeen(), true);
    await db.close();
  });

  testWidgets('every activity uses the compact collapsed row', (t) async {
    await t.runAsync(loadTestFonts);
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final now = DateTime.now();
    final entries = [
      record('diaper', now),
      record('nursing', now, method: 'nursing'),
      for (final method in [
        'bottle',
        'sleep',
        'pumping',
        'solids',
        'growth',
        'health',
        'routine',
        'milestone',
      ])
        Feeding(
          id: method,
          familyId: 'synthetic',
          at: now,
          method: method,
          amountMl: 60,
          endedAt: ['sleep', 'pumping'].contains(method)
              ? now.add(const Duration(minutes: 20))
              : null,
          details: switch (method) {
            'solids' => {'food': 'Pear'},
            'growth' => {'measurement': 'Weight', 'value': 4.0, 'unit': 'kg'},
            'health' => {
              'kind': 'Medication',
              'name': 'Example',
              'dose': '1 ml',
            },
            'routine' || 'milestone' => {'name': 'Sample activity'},
            _ => {},
          },
        ),
    ];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordList(
              children: [
                for (final entry in entries)
                  RecordRow(
                    key: ValueKey(entry.id),
                    record: entry,
                    volumeUnit: VolumeUnit.oz,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    for (final entry in entries) {
      expect(
        t.getSize(find.byKey(ValueKey(entry.id))).height,
        closeTo(60, .1),
        reason: entry.method,
      );
    }
    expect(t.takeException(), isNull);
  });

  for (final large in [false, true]) {
    testWidgets(
      'collapsed records grow naturally at ${large ? '320px / 200%' : '390px'}',
      (t) async {
        await t.runAsync(loadTestFonts);
        t.view.physicalSize = Size(large ? 320 : 390, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final now = DateTime.now();
        final entries = [
          record('diaper', now.subtract(const Duration(minutes: 39))),
          record(
            'nursing',
            now.subtract(const Duration(hours: 4, minutes: 28)),
            method: 'nursing',
          ),
          Feeding(
            id: 'bottle',
            familyId: 'synthetic',
            method: 'bottle',
            at: now.subtract(const Duration(hours: 6)),
            amountMl: 60,
            details: const {'breastMilkMl': 60.0, 'formulaMl': 0.0},
          ),
        ];
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('uniform-capture'),
                child: SingleChildScrollView(
                  child: RecordList(
                    children: [
                      for (final entry in entries)
                        RecordRow(
                          key: ValueKey(entry.id),
                          record: entry,
                          volumeUnit: VolumeUnit.oz,
                          showElapsed: true,
                          onEdit: () async {},
                          onDelete: () async {},
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('Nursing · L 16m46s · R 12m38s'), findsOneWidget);
        expect(find.text('L 16m 46s · R 12m 38s'), findsNothing);
        final heights = entries
            .map((entry) => t.getSize(find.byKey(ValueKey(entry.id))).height)
            .toList();
        for (final height in heights) {
          expect(height, greaterThanOrEqualTo(60));
        }
        for (final entry in entries) {
          final row = find.byKey(ValueKey(entry.id));
          final badge = find.descendant(
            of: row,
            matching: find.byType(ActivityBadge),
          );
          final title = find.descendant(
            of: row,
            matching: find.textContaining(
              entry.method == 'diaper'
                  ? 'Diaper · Wet'
                  : entry.method == 'nursing'
                  ? 'Nursing ·'
                  : 'Bottle ·',
            ),
          );
          final textBlock = find
              .ancestor(of: title, matching: find.byType(Column))
              .first;
          expect(t.getCenter(badge).dy, closeTo(t.getCenter(textBlock).dy, .1));
        }
        final oldHeight = heights.first;
        await t.tap(find.text('Diaper · Wet'));
        await t.pumpAndSettle();
        expect(
          t.getSize(find.byKey(const ValueKey('diaper'))).height,
          greaterThan(oldHeight),
        );
        expect(
          t.getSize(find.byKey(const ValueKey('nursing'))).height,
          closeTo(heights[1], .1),
        );
        expect(t.takeException(), isNull);
        await t.tap(find.text('Diaper · Wet'));
        await t.pumpAndSettle();
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('uniform-capture')),
        );
        final image = await t.runAsync(() => boundary.toImage(pixelRatio: 2));
        final bytes = await t.runAsync(
          () => image!.toByteData(format: ImageByteFormat.png),
        );
        await t.runAsync(() async {
          final file = File(
            '${Platform.isAndroid || Platform.isIOS ? Directory.systemTemp.path : 'build'}/activity-polish-qa/uniform-${large ? 'large' : 'normal'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
        });
        image!.dispose();
        await t.pumpWidget(const SizedBox());
      },
    );
    testWidgets(
      'elapsed and expanded details align at ${large ? '320px / 200%' : '390px'}',
      (t) async {
        await t.runAsync(loadTestFonts);
        t.view.physicalSize = Size(large ? 320 : 390, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final now = DateTime.now();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: const ValueKey('capture'),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      RecordRow(
                        record: record(
                          'diaper',
                          now.subtract(const Duration(minutes: 39)),
                        ),
                        volumeUnit: VolumeUnit.ml,
                        showElapsed: true,
                        onDelete: () async {},
                        onEdit: () async {},
                      ),
                      RecordRow(
                        record: record(
                          'nursing',
                          now.subtract(const Duration(hours: 4, minutes: 28)),
                          method: 'nursing',
                        ),
                        volumeUnit: VolumeUnit.ml,
                        showElapsed: true,
                        onDelete: () async {},
                        onEdit: () async {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Diaper · Wet'));
        await t.pumpAndSettle();
        expect(
          t.getTopLeft(find.text('Logged by Caregiver')).dx,
          closeTo(t.getTopLeft(find.text('Diaper · Wet')).dx, 0.1),
        );
        expect(find.textContaining('39m ago'), findsOneWidget);
        expect(find.textContaining('Started'), findsOneWidget);
        expect(find.textContaining('4h 28m ago'), findsOneWidget);
        for (final method in ['diaper', 'nursing']) {
          final row = find.byWidgetPredicate(
            (widget) => widget is RecordRow && widget.record.method == method,
          );
          final badge = find.descendant(
            of: row,
            matching: find.byType(ActivityBadge),
          );
          final title = find.descendant(
            of: row,
            matching: find.text(
              method == 'diaper'
                  ? 'Diaper · Wet'
                  : 'Nursing · L 16m46s · R 12m38s',
            ),
          );
          final chevron = find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Icon &&
                  [Icons.expand_more, Icons.expand_less].contains(widget.icon),
            ),
          );
          final textBlock = find
              .ancestor(of: title, matching: find.byType(Column))
              .first;
          expect(t.getCenter(badge).dy, closeTo(t.getCenter(textBlock).dy, .1));
          expect(
            t.getCenter(chevron).dy,
            closeTo(t.getCenter(textBlock).dy, .1),
          );
          expect(t.getTopLeft(badge).dx - t.getTopLeft(row).dx, closeTo(8, .1));
          expect(
            t.getTopRight(row).dx - t.getTopRight(chevron).dx,
            closeTo(8, .1),
          );
        }
        expect(t.takeException(), isNull);
        if (!large) {
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture')),
          );
          final image = await t.runAsync(() => boundary.toImage(pixelRatio: 2));
          final bytes = await t.runAsync(
            () => image!.toByteData(format: ImageByteFormat.png),
          );
          await t.runAsync(() async {
            final file = File(
              '${Platform.isAndroid || Platform.isIOS ? Directory.systemTemp.path : 'build'}/activity-polish-qa/records.png',
            );
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
          });
          image!.dispose();
        }
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('demo previews both actions once without invoking either', (
    t,
  ) async {
    var edits = 0, deletes = 0, starts = 0, learned = 0;
    final preferenceSave = Completer<void>();
    final completions = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordRow(
              record: record('demo', DateTime.now()),
              volumeUnit: VolumeUnit.ml,
              swipeDemoEnabled: true,
              onSwipeAction: () async {
                learned++;
                await preferenceSave.future;
              },
              onSwipeDemoStart: () {
                starts++;
                return true;
              },
              onSwipeDemoEnd: (completed) async {
                completions.add(completed);
              },
              onEdit: () async {
                edits++;
              },
              onDelete: () async {
                deletes++;
              },
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 701));
    await t.pump(const Duration(milliseconds: 900));
    final transforms = t.widgetList<Transform>(find.byType(Transform));
    expect(transforms.any((w) => w.transform.storage[12] > 50), true);
    await t.pump(const Duration(milliseconds: 1600));
    expect(
      t
          .widgetList<Transform>(find.byType(Transform))
          .any((w) => w.transform.storage[12] < -50),
      true,
    );
    await t.pump(const Duration(milliseconds: 800));
    expect(completions, [true]);
    expect(starts, 1);
    expect(edits, 0);
    expect(deletes, 0);
    expect(learned, 0);
    await t.drag(find.byType(Dismissible), const Offset(600, 0));
    await t.pumpAndSettle();
    expect(edits, 1);
    expect(learned, 1);
    // Opening Edit does not wait for preference storage to finish.
    expect(preferenceSave.isCompleted, false);
    preferenceSave.complete();
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('touch interrupts demo safely without marking it seen', (
    t,
  ) async {
    final completions = <bool>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RecordRow(
              record: record('interrupt', DateTime.now()),
              volumeUnit: VolumeUnit.ml,
              swipeDemoEnabled: true,
              onSwipeDemoStart: () => true,
              onSwipeDemoEnd: (completed) async {
                completions.add(completed);
              },
              onEdit: () async {},
              onDelete: () async {},
            ),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 701));
    await t.pump(const Duration(milliseconds: 900));
    await t.tap(find.text('Diaper · Wet'));
    await t.pumpAndSettle();
    expect(completions, [false]);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
}
