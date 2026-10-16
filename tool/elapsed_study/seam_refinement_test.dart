import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../elapsed_icon_mockup.dart';
import 'structural_glyph.dart';
import 'structural_main.dart';
import 'render_test.dart' show loadStudyFonts, saveCapture;

class SeamReviewBoard extends StatelessWidget {
  const SeamReviewBoard({super.key, this.elapsed = sampleElapsed});
  final Map<String, Duration?> elapsed;
  Widget glyph(BuildContext c, String method, double size) =>
      StructuralElapsedGlyph(
        method: method,
        label: quickLogActivities[method]!,
        elapsed: elapsed[method],
        size: size,
        color: activityAccent(method, context: c),
        background: activityTint(method, context: c),
        construction: IconConstruction.seam,
      );
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('seam-review'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: littleLogTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Seam lettering',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'One contour / one baseline / measured gaps',
                style: TextStyle(fontSize: 16, color: Color(0xffb3c0ba)),
              ),
              const SizedBox(height: 24),
              for (final brightness in [Brightness.dark, Brightness.light])
                Theme(
                  data: littleLogTheme(brightness: brightness),
                  child: Builder(
                    builder: (c) => Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 18,
                      ),
                      color: Theme.of(c).scaffoldBackgroundColor,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final method in elapsedIconActivities)
                            Column(
                              children: [
                                Container(
                                  width: 112,
                                  height: 112,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: activityTint(method, context: c),
                                    borderRadius: BorderRadius.circular(26),
                                  ),
                                  child: glyph(c, method, 96),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  quickLogActivities[method]!,
                                  style: TextStyle(
                                    color: logPalette(c).ink,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 22),
              const Text(
                'Contour detail',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (c) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final method in [
                      'bottle',
                      'nursing',
                      'sleep',
                      'solids',
                    ])
                      glyph(c, method, 166),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  const before = bool.fromEnvironment('SEAM_BEFORE');
  final prefix = before ? 'seam-before' : 'seam-refined';
  testWidgets('selected seam contour review', (t) async {
    t.view.physicalSize = const Size(950, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    await t.pumpWidget(const SeamReviewBoard());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(t, 'seam-review', '$prefix-board');
    await saveCapture(t, 'seam-review', '$prefix-board-inline', pixelRatio: 1);
    if (!before) {
      for (final duration in [
        null,
        Duration.zero,
        const Duration(minutes: 59),
        const Duration(hours: 1),
        const Duration(hours: 23, minutes: 59),
        const Duration(days: 2),
      ]) {
        await t.pumpWidget(
          SeamReviewBoard(
            elapsed: {
              for (final method in elapsedIconActivities) method: duration,
            },
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
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
        await saveCapture(t, 'seam-review', '$prefix-$name');
      }
    }
    await t.pumpWidget(const SizedBox());
  });
  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('selected seam ${brightness.name} app context', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadStudyFonts);
      await t.pumpWidget(
        structuralMock(IconConstruction.seam, brightness: brightness),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await saveCapture(
        t,
        'elapsed-capture-root',
        '$prefix-${brightness.name}-quick-log',
      );
      await t.tap(find.byKey(const ValueKey('mock-all-activities')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await saveCapture(
        t,
        'elapsed-capture-root',
        '$prefix-${brightness.name}-picker',
      );
      await t.pumpWidget(const SizedBox());
    });
  }
}
