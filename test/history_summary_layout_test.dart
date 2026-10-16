import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'support/test_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  testWidgets(
    'History aligns nursing with peer cells and wraps at large text',
    (t) async {
      await t.runAsync(loadTestFonts);
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() => c.createLocal('Family', 'Robin'));
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day);
      await t.runAsync(() async {
        for (final record in [
          Feeding(
            id: 'nursing',
            familyId: c.family!.id,
            at: day.add(const Duration(hours: 9)),
            method: 'nursing',
            endedAt: day.add(const Duration(hours: 11)),
            leftSeconds: 3480,
            rightSeconds: 2640,
            minutes: 102,
          ),
          Feeding(
            id: 'bottle',
            familyId: c.family!.id,
            at: day.add(const Duration(hours: 10)),
            method: 'bottle',
            amountMl: 90,
          ),
          Feeding(
            id: 'sleep',
            familyId: c.family!.id,
            at: day.add(const Duration(hours: 7)),
            method: 'sleep',
            endedAt: day.add(const Duration(hours: 8)),
          ),
        ]) {
          await c.repository.add(record);
        }
        await c.refresh();
      });

      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('history-capture'),
            child: ActivityHistory(controller: c),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('1h 42m'), findsOneWidget);
      expect(find.text('L 58m'), findsOneWidget);
      expect(find.text('R 44m'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('R 44m')).dy,
        greaterThan(t.getTopLeft(find.text('L 58m')).dy),
      );
      expect(find.text('Feeds'), findsNothing);
      expect(
        t.getTopLeft(find.text('1h 42m')).dy,
        closeTo(t.getTopLeft(find.text('90 ml')).dy, 1),
      );
      expect(
        t.getBottomLeft(find.text('Nursing').first).dy,
        closeTo(t.getBottomLeft(find.text('Bottle')).dy, 1),
      );
      expect(t.takeException(), isNull);
      await capture(t, 'history-normal');

      await t.runAsync(() async {
        await c.repository.add(
          Feeding(
            id: 'manual',
            familyId: c.family!.id,
            at: day.add(const Duration(hours: 12)),
            method: 'nursing',
            minutes: 5,
          ),
        );
        await c.refresh();
      });
      t.view.physicalSize = const Size(320, 844);
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      await t.pumpAndSettle();
      expect(find.text('1h47m'), findsOneWidget);
      expect(find.text('1h0m'), findsOneWidget);
      expect(find.textContaining('No side'), findsNothing);
      expect(
        t.getTopLeft(find.text('1h47m')).dy,
        closeTo(t.getTopLeft(find.text('90 ml')).dy, 1),
      );
      if (const bool.fromEnvironment('CAPTURE_HISTORY_SUMMARY')) {
        expect(t.getSize(find.text('1h47m')).height, lessThan(65));
      }
      expect(
        t.getBottomLeft(find.text('Nursing').first).dy,
        closeTo(t.getBottomLeft(find.text('Bottle')).dy, 1),
      );
      expect(t.takeException(), isNull);
      await capture(t, 'history-320-large-text-top');
      await t.ensureVisible(find.text('Nursing').first);
      await t.pumpAndSettle();
      await capture(t, 'history-320-large-text');
    },
  );
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_HISTORY_SUMMARY')) return;
  final boundary = t.firstRenderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('history-capture')),
  );
  final image = await t.runAsync(() => boundary.toImage());
  final bytes = await t.runAsync(
    () => image!.toByteData(format: ImageByteFormat.png),
  );
  await t.runAsync(() async {
    final output = Directory('../output/release31');
    await output.create(recursive: true);
    await File(
      '${output.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
}
