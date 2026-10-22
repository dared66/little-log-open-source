import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/empty_log_day.dart';
import 'package:little_log/widgets/log_header.dart';
import 'support/scroll_to.dart';
import 'support/test_fonts.dart';

void main() {
  testWidgets('adjacent calendar dates, limits and large text retain artwork', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadTestFonts);
    DateTime? chosen;
    final today = DateUtils.dateOnly(DateTime.now());
    for (final day in [
      today,
      DateTime(2000),
      DateTime(2024, 3, 1),
      DateTime(2025, 1, 1),
      DateTime(2026, 3, 9),
    ]) {
      await t.pumpWidget(
        MaterialApp(
          theme: littleLogTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
            child: Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: RepaintBoundary(
                    key: const ValueKey('capture'),
                    child: EmptyLogDay(
                      day: day,
                      canNavigate: true,
                      onChanged: (value) => chosen = value,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
      expect(find.text('No entries'), findsOneWidget);
      final contentCenter =
          (t.getTopLeft(find.byIcon(Icons.auto_awesome_outlined)).dy +
              t.getBottomLeft(find.text('No entries')).dy) /
          2;
      final previous = find.byKey(const ValueKey('empty-day-previous'));
      final next = find.byKey(const ValueKey('empty-day-next'));
      if (day == today) {
        expect(next, findsNothing);
      } else {
        expect(t.getCenter(next).dy, closeTo(contentCenter, .1));
        await t.tap(next);
        expect(chosen, DateTime(day.year, day.month, day.day + 1));
      }
      if (day == DateTime(2000)) {
        expect(previous, findsNothing);
      } else {
        expect(t.getCenter(previous).dy, closeTo(contentCenter, .1));
        expect(t.getSize(previous).height, greaterThanOrEqualTo(44));
        await t.tap(previous);
        expect(chosen, DateTime(day.year, day.month, day.day - 1));
      }
      expect(t.takeException(), isNull);
    }
  });

  testWidgets('home navigates empty days but not empty activity filters', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadTestFonts);
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final repo = Repository(db);
    final auth = GoogleAuth();
    final c = AppController(repo, auth, GoogleDrive(auth))..loading = false;
    await t.runAsync(() async {
      await c.createLocal('Preview family', 'Robin');
      await c.setSummaryMetrics(['Nursing', 'Diapers']);
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture'),
        child: LittleLogApp(controller: c),
      ),
    );
    await t.pumpAndSettle();
    await scrollTo(t, find.byType(EmptyLogDay));
    final today = DateUtils.dateOnly(DateTime.now());
    expect(find.byKey(const ValueKey('empty-day-next')), findsNothing);
    await t.tap(find.byKey(const ValueKey('empty-day-previous')));
    await t.pumpAndSettle();
    expect(
      t.widget<LogHeader>(find.byType(LogHeader)).day,
      DateTime(today.year, today.month, today.day - 1),
    );
    await scrollTo(t, find.byType(EmptyLogDay));
    if (const bool.fromEnvironment('CAPTURE_EMPTY_DAY')) {
      final boundary = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture')),
      );
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          '../output/empty-day-final/build59-source-2ee1dfd-working.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await t.tap(find.byKey(const ValueKey('empty-day-next')));
    await t.pumpAndSettle();
    expect(t.widget<LogHeader>(find.byType(LogHeader)).day, today);
    await t.runAsync(() async {
      await repo.add(
        Feeding(
          id: 'sample-diaper',
          familyId: c.family!.id,
          at: today.add(const Duration(hours: 1)),
          method: 'diaper',
          diaperKind: 'wet',
        ),
      );
      await c.refresh();
    });
    await t.pumpAndSettle();
    expect(find.byType(EmptyLogDay), findsNothing);
    await scrollTo(t, find.text('View all'));
    await t.tap(find.text('View all'));
    await t.pumpAndSettle();
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await scrollTo(t, dropdown);
    await t.tap(dropdown);
    await t.pumpAndSettle();
    await t.tap(find.text('Nursing').last);
    await t.pumpAndSettle();
    await scrollTo(t, find.byType(EmptyLogDay));
    expect(find.text('No entries on this day'), findsOneWidget);
    expect(find.byKey(const ValueKey('empty-day-previous')), findsNothing);
    expect(find.byKey(const ValueKey('empty-day-next')), findsNothing);
    expect(find.byIcon(Icons.auto_awesome_outlined), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });
}
