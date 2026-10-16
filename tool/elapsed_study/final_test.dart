import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../elapsed_icon_mockup.dart';
import 'designs.dart';
import 'render_test.dart' show loadStudyFonts, saveCapture;

const finalNames = [
  'Lunar script',
  'Soft bold',
  'Tall narrow',
  'Continuous inscription',
  'Sculpted',
];

class FinalOverview extends StatelessWidget {
  const FinalOverview({super.key, this.qa = false, this.duration, this.phase});
  final bool qa;
  final Duration? duration;
  final String? phase;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('final-capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: littleLogTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                qa ? 'Longest value at two sizes' : 'Five live icon directions',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                qa
                    ? '23h59m at 96px and 68px · actual Flutter rendering'
                    : phase ??
                          'Ten reviewed rounds · actual Dart mockups · time lives within each object',
                style: const TextStyle(fontSize: 15, color: Color(0xffb3c0ba)),
              ),
              const SizedBox(height: 22),
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Builder(
                    builder: (c) => Row(
                      children: [
                        SizedBox(
                          width: 184,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '0${i + 1}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xffa4d5c2),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                finalNames[i],
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                [
                                  'Curved · medium',
                                  'Rounded · bold',
                                  'Condensed · slender',
                                  'Single line · precise',
                                  'Filled · confident',
                                ][i],
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xffb3c0ba),
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
                                    Container(
                                      width: 108,
                                      height: 108,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: activityTint(method, context: c),
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                      child: ElapsedActivityGlyph(
                                        method: method,
                                        label: quickLogActivities[method]!,
                                        fallback: activityIcon(method),
                                        elapsed: qa
                                            ? const Duration(
                                                hours: 23,
                                                minutes: 59,
                                              )
                                            : duration ?? sampleElapsed[method],
                                        color: activityAccent(
                                          method,
                                          context: c,
                                        ),
                                        size: 96,
                                        design: studyDesigns[i + 5],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    if (!qa)
                                      Text(
                                        quickLogActivities[method]!,
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    if (qa)
                                      ElapsedActivityGlyph(
                                        method: method,
                                        label: quickLogActivities[method]!,
                                        fallback: activityIcon(method),
                                        elapsed: const Duration(
                                          hours: 23,
                                          minutes: 59,
                                        ),
                                        color: activityAccent(
                                          method,
                                          context: c,
                                        ),
                                        size: 68,
                                        design: studyDesigns[i + 5],
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              const Text(
                'Minute updates · 220ms type transition · fixed silhouettes and category colors',
                style: TextStyle(fontSize: 14, color: Color(0xffb3c0ba)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final qa in [false, true]) {
    testWidgets('all five ${qa ? 'boundary QA' : 'final overview'}', (t) async {
      t.view.physicalSize = Size(1080, qa ? 1500 : 1180);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadStudyFonts);
      await t.pumpWidget(FinalOverview(qa: qa));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await saveCapture(
        t,
        'final-capture',
        qa ? 'final-boundaries' : 'five-finals',
      );
      if (!qa) {
        await saveCapture(t, 'final-capture', 'five-finals-inline', pixelRatio: 1);
      }
      await t.pumpWidget(const SizedBox());
    });
  }
  for (var i = 0; i < 5; i++) {
    for (final brightness in [Brightness.dark, Brightness.light]) {
      testWidgets('final ${i + 1} ${brightness.name} real app context', (
        t,
      ) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        await t.runAsync(loadStudyFonts);
        await t.pumpWidget(
          ElapsedIconsMockupApp(
            brightness: brightness,
            design: studyDesigns[i + 5],
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await saveCapture(
          t,
          'elapsed-capture-root',
          'final-${i + 1}-${brightness.name}',
        );
        await t.tap(find.byKey(const ValueKey('mock-all-activities')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        await saveCapture(
          t,
          'elapsed-capture-root',
          'final-${i + 1}-${brightness.name}-picker',
        );
        await t.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('live source clock, hour boundary, tap reset and older cutoff', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    var now = DateTime(2026, 10, 14, 12);
    await t.runAsync(loadStudyFonts);
    await t.pumpWidget(
      ElapsedIconsMockupApp(
        design: studyDesigns[5],
        live: true,
        now: () => now,
        elapsed: {
          for (final m in elapsedIconActivities)
            m: const Duration(minutes: 59, seconds: 59),
        },
      ),
    );
    await t.pumpAndSettle();
    Duration? elapsed() => t
        .widgetList<ElapsedActivityGlyph>(find.byType(ElapsedActivityGlyph))
        .first
        .elapsed;
    expect(elapsedIconLabel(elapsed()).primary, '59m');
    now = now.add(const Duration(seconds: 1));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(elapsedIconLabel(elapsed()).primary, '1h');
    await saveCapture(t, 'elapsed-capture-root', 'live-hour-change');
    await t.tap(find.byKey(const ValueKey('mock-log-bottle')));
    await t.pumpAndSettle();
    expect(elapsedIconLabel(elapsed()).primary, 'now');
    await saveCapture(t, 'elapsed-capture-root', 'live-reset');
    now = now.add(const Duration(days: 3));
    await t.pump(const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(elapsedIconLabel(elapsed()).primary, '>1d');
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('original footprint comparison, not an enlarged study', (
    t,
  ) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    await t.pumpWidget(
      ElapsedIconsMockupApp(design: studyDesigns[6], pickerIconSize: 32),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('mock-all-activities')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(t, 'elapsed-capture-root', 'original-footprint-picker');
    await t.pumpWidget(const SizedBox());
  });
  for (var i = 0; i < 5; i++) {
    testWidgets('final ${i + 1} small phone large text and reduced motion', (
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
      await t.pumpWidget(ElapsedIconsMockupApp(design: studyDesigns[i + 5]));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('mock-log-solids')).hitTestable(),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.byKey(const ValueKey('mock-log-solids')));
      await t.pumpAndSettle();
      expect(
        t
            .widgetList<ElapsedActivityGlyph>(find.byType(ElapsedActivityGlyph))
            .singleWhere((g) => g.method == 'solids')
            .elapsed,
        Duration.zero,
      );
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
      await t.pumpWidget(const SizedBox());
    });
  }
}
