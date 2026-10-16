import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../test/support/test_fonts.dart';
import 'elapsed_icon_mockup.dart';

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_ELAPSED_ICONS')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('elapsed-capture-root')),
  );
  await t.runAsync(() async {
    final pixels = await boundary.toImage(pixelRatio: 2);
    final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../output/elapsed-icons-dart/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    pixels.dispose();
  });
}

void main() {
  test(
    'elapsed labels cap strictly beyond 24 hours and retain minute precision',
    () {
      expect(elapsedIconLabel(null).primary, '—');
      expect(elapsedIconLabel(const Duration(seconds: 59)).primary, 'now');
      expect(elapsedIconLabel(const Duration(minutes: -1)).primary, 'now');
      expect(elapsedIconLabel(const Duration(minutes: 59)).primary, '59m');
      expect(elapsedIconLabel(const Duration(hours: 1)).secondary, '');
      final before = elapsedIconLabel(const Duration(hours: 23, minutes: 59));
      expect(before.primary, '23h');
      expect(before.secondary, '59m');
      expect(elapsedIconLabel(const Duration(hours: 24)).primary, '1d');
      expect(
        elapsedIconLabel(const Duration(hours: 24, seconds: 1)).primary,
        '>1d',
      );
      expect(elapsedIconLabel(const Duration(days: 50)).primary, '>1d');
    },
  );

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('six actual Flutter icons: ${brightness.name}', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadTestFonts);
      await t.pumpWidget(ElapsedIconsMockupApp(brightness: brightness));
      await t.pumpAndSettle();
      expect(find.byType(ElapsedActivityGlyph), findsNWidgets(6));
      for (final method in elapsedIconActivities) {
        expect(find.byKey(ValueKey('mock-log-$method')), findsOneWidget);
      }
      expect(t.takeException(), isNull);
      await capture(t, '${brightness.name}-quick-log');
      await t.tap(find.byKey(const ValueKey('mock-all-activities')));
      await t.pumpAndSettle();
      expect(find.text('Log an activity'), findsOneWidget);
      expect(t.takeException(), isNull);
      await capture(t, '${brightness.name}-activity-picker');
      await t.ensureVisible(find.byKey(const ValueKey('picker-pumping')));
      await t.tap(find.byKey(const ValueKey('picker-pumping')));
      await t.pumpAndSettle();
      final glyphs = t.widgetList<ElapsedActivityGlyph>(
        find.byType(ElapsedActivityGlyph),
      );
      expect(
        glyphs.singleWhere((g) => g.method == 'pumping').elapsed,
        Duration.zero,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'small phone and accessibility text keep all six actions reachable',
    (t) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      await t.pumpWidget(const ElapsedIconsMockupApp());
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await capture(t, 'dark-small-large-text');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mock-log-solids')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('mock-log-solids')));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<ElapsedActivityGlyph>(find.byType(ElapsedActivityGlyph))
            .singleWhere((g) => g.method == 'solids')
            .elapsed,
        Duration.zero,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'missing history and older-than-day states render without clipping',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadTestFonts);
      await t.pumpWidget(
        const ElapsedIconsMockupApp(
          elapsed: {
            'bottle': Duration(hours: 23, minutes: 59),
            'nursing': Duration(days: 2),
            'diaper': null,
            'sleep': Duration.zero,
            'pumping': Duration(days: 3),
            'solids': Duration(minutes: 59),
          },
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await capture(t, 'dark-time-states');
      await t.pumpWidget(const SizedBox());
    },
  );
}
