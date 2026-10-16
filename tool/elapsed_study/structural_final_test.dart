import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../elapsed_icon_mockup.dart';
import 'structural_glyph.dart';
import 'structural_main.dart';
import 'render_test.dart' show loadStudyFonts, saveCapture;

const structuralNames = [
  'Seam lettering',
  'Carved apertures',
  'Wide objects',
  'Numeral bodies',
  'Folded surfaces',
];

class StructuralOverview extends StatelessWidget {
  const StructuralOverview({
    super.key,
    this.brightness = Brightness.dark,
    this.elapsed = sampleElapsed,
    this.caption =
        'Time constructs a contour, an aperture, a vessel, a body or a folded surface',
    this.glyphSize = 96,
    this.monochrome = false,
  });
  final Brightness brightness;
  final Map<String, Duration?> elapsed;
  final String caption;
  final double glyphSize;
  final bool monochrome;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('construction-capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: littleLogTheme(brightness: brightness),
      home: Scaffold(
        body: Builder(
          builder: (c) => Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Five different constructions',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: logPalette(c).ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  caption,
                  style: TextStyle(
                    fontSize: 14,
                    color: logPalette(c).secondary,
                  ),
                ),
                const SizedBox(height: 20),
                for (final kind in IconConstruction.values)
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 151,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                structuralNames[kind.index],
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: logPalette(c).ink,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  'Type replaces the edge',
                                  'Digits carve material',
                                  'A new orientation',
                                  'Digits carry the object',
                                  'Time follows a plane',
                                ][kind.index],
                                style: TextStyle(
                                  fontSize: 13,
                                  color: logPalette(c).secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              for (final method in elapsedIconActivities)
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    RepaintBoundary(
                                      key: ValueKey(
                                        'paint-${kind.name}-$method',
                                      ),
                                      child: Container(
                                        width: glyphSize + 12,
                                        height: glyphSize + 12,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: monochrome
                                              ? Theme.of(c).colorScheme.surface
                                              : activityTint(
                                                  method,
                                                  context: c,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            25,
                                          ),
                                        ),
                                        child: StructuralElapsedGlyph(
                                          method: method,
                                          label: quickLogActivities[method]!,
                                          elapsed: elapsed[method],
                                          size: glyphSize,
                                          color: monochrome
                                              ? logPalette(c).ink
                                              : activityAccent(
                                                  method,
                                                  context: c,
                                                ),
                                          background: monochrome
                                              ? Theme.of(c).colorScheme.surface
                                              : activityTint(
                                                  method,
                                                  context: c,
                                                ),
                                          construction: kind,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      quickLogActivities[method]!,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: logPalette(c).ink,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('five constructions ${brightness.name}', (t) async {
      t.view.physicalSize = const Size(950, 1250);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadStudyFonts);
      await t.pumpWidget(StructuralOverview(brightness: brightness));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await saveCapture(
        t,
        'construction-capture',
        'structural-five-${brightness.name}',
      );
      await saveCapture(
        t,
        'construction-capture',
        'structural-five-${brightness.name}-inline',
        pixelRatio: 1,
      );
      await t.pumpWidget(const SizedBox());
    });
  }
  testWidgets('no activity vanishes across the full elapsed-state range', (
    t,
  ) async {
    t.view.physicalSize = const Size(950, 1250);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    for (final duration in [
      null,
      Duration.zero,
      const Duration(minutes: 59),
      const Duration(hours: 1),
      const Duration(hours: 23, minutes: 59),
      const Duration(days: 2),
    ]) {
      await t.pumpWidget(
        StructuralOverview(
          elapsed: {
            for (final method in elapsedIconActivities) method: duration,
          },
          caption: elapsedIconLabel(duration).spoken,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        for (final kind in IconConstruction.values) {
          for (final method in elapsedIconActivities) {
            final boundary = t.renderObject<RenderRepaintBoundary>(
              find.byKey(ValueKey('paint-${kind.name}-$method')),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final context = t.element(
              find.byKey(ValueKey('paint-${kind.name}-$method')),
            );
            final tint = activityTint(method, context: context);
            final red = (tint.r * 255).round(),
                green = (tint.g * 255).round(),
                blue = (tint.b * 255).round();
            var visible = 0;
            for (var offset = 0; offset < data.lengthInBytes; offset += 4) {
              if (data.getUint8(offset + 3) < 250) continue;
              final difference =
                  (data.getUint8(offset) - red).abs() +
                  (data.getUint8(offset + 1) - green).abs() +
                  (data.getUint8(offset + 2) - blue).abs();
              if (difference > 20) visible++;
            }
            expect(
              visible,
              greaterThan(250),
              reason: '${kind.name}/$method must visibly render for $duration',
            );
            image.dispose();
          }
        }
      });
      final name = duration == null
          ? 'missing'
          : duration == Duration.zero
          ? 'now'
          : duration.inDays > 0
          ? 'older'
          : duration.inHours == 23
          ? 'longest'
          : duration.inHours == 1
          ? 'hour'
          : 'minutes';
      await saveCapture(t, 'construction-capture', 'structural-state-$name');
    }
    await t.pumpWidget(
      const StructuralOverview(
        glyphSize: 64,
        elapsed: {
          'bottle': Duration(hours: 23, minutes: 59),
          'nursing': Duration(hours: 23, minutes: 59),
          'diaper': Duration(hours: 23, minutes: 59),
          'sleep': Duration(hours: 23, minutes: 59),
          'pumping': Duration(hours: 23, minutes: 59),
          'solids': Duration(hours: 23, minutes: 59),
        },
        caption: 'Longest elapsed value / 64px artwork',
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(t, 'construction-capture', 'structural-longest-64');
    await t.pumpWidget(
      const StructuralOverview(
        monochrome: true,
        caption: 'Monochrome construction comparison',
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(t, 'construction-capture', 'structural-monochrome');
    await t.pumpWidget(const SizedBox());
  });
  for (final kind in IconConstruction.values) {
    testWidgets('${kind.name} small phone large text reduced motion', (
      t,
    ) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      t.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await t.runAsync(loadStudyFonts);
      await t.pumpWidget(structuralMock(kind));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mock-all-activities')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('mock-all-activities')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.byKey(const ValueKey('picker-solids')));
      await t.tap(find.byKey(const ValueKey('picker-solids')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        t
            .widgetList<StructuralElapsedGlyph>(
              find.byType(StructuralElapsedGlyph),
            )
            .singleWhere((g) => g.method == 'solids')
            .elapsed,
        Duration.zero,
      );
      await t.pumpWidget(const SizedBox());
    });
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets('${kind.name} ${brightness.name} actual app context', (
        t,
      ) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.runAsync(loadStudyFonts);
        var now = DateTime(2026, 10, 14, 12);
        await t.pumpWidget(
          structuralMock(
            kind,
            brightness: brightness,
            live: true,
            now: () => now,
          ),
        );
        await t.pumpAndSettle();
        expect(find.byType(StructuralElapsedGlyph), findsNWidgets(6));
        expect(t.takeException(), isNull);
        await saveCapture(
          t,
          'elapsed-capture-root',
          'structural-${kind.name}-${brightness.name}',
        );
        now = now.add(const Duration(minutes: 1));
        await t.pump(const Duration(seconds: 1));
        await t.pumpAndSettle();
        expect(
          t
              .widgetList<StructuralElapsedGlyph>(
                find.byType(StructuralElapsedGlyph),
              )
              .first
              .elapsed,
          const Duration(hours: 2, minutes: 16),
        );
        await t.tap(find.byKey(const ValueKey('mock-all-activities')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await saveCapture(
          t,
          'elapsed-capture-root',
          'structural-${kind.name}-${brightness.name}-picker',
        );
        await t.ensureVisible(find.byKey(const ValueKey('picker-solids')));
        await t.tap(find.byKey(const ValueKey('picker-solids')));
        await t.pumpAndSettle();
        expect(
          t
              .widgetList<StructuralElapsedGlyph>(
                find.byType(StructuralElapsedGlyph),
              )
              .singleWhere((g) => g.method == 'solids')
              .elapsed,
          Duration.zero,
        );
        await t.pumpWidget(const SizedBox());
      });
    }
  }
}
