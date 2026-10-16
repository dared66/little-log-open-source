import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../elapsed_icon_mockup.dart';
import 'structural_glyph.dart';
import 'render_test.dart' show loadStudyFonts, saveCapture;

class StructuralBoard extends StatelessWidget {
  const StructuralBoard({super.key});
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('structural-capture'),
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
                'Different constructions',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Time replaces an edge / cuts into material / follows a different silhouette',
                style: TextStyle(fontSize: 16, color: Color(0xffb3c0ba)),
              ),
              const SizedBox(height: 24),
              for (final kind in IconConstruction.values)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          'Seam lettering',
                          'Carved apertures',
                          'Wide objects',
                          'Numeral bodies',
                          'Folded surfaces',
                        ][kind.index],
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final brightness in [
                        Brightness.dark,
                        Brightness.light,
                      ])
                        Theme(
                          data: littleLogTheme(brightness: brightness),
                          child: Builder(
                            builder: (c) => Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              color: Theme.of(c).scaffoldBackgroundColor,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (final method in elapsedIconActivities)
                                    Column(
                                      children: [
                                        Container(
                                          width: 108,
                                          height: 108,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: activityTint(
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
                                            elapsed: sampleElapsed[method],
                                            color: activityAccent(
                                              method,
                                              context: c,
                                            ),
                                            background: activityTint(
                                              method,
                                              context: c,
                                            ),
                                            construction: kind,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
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
  );
}

void main() {
  testWidgets('structurally different native Dart concepts', (t) async {
    t.view.physicalSize = const Size(900, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    await t.pumpWidget(const StructuralBoard());
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(t, 'structural-capture', 'structural-prototypes');
    await t.pumpWidget(const SizedBox());
  });
}
