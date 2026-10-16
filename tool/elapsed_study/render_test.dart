import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import '../../test/support/test_fonts.dart';
import '../elapsed_icon_mockup.dart';
import 'designs.dart';
import 'native_fonts.dart';

Future<void> loadStudyFonts() async {
  await loadTestFonts();
  await loadNativeStudyFonts();
}

Widget glyph(
  BuildContext context,
  String method,
  ElapsedGlyphDesign design, {
  Duration? elapsed,
  double size = 96,
}) => ElapsedActivityGlyph(
  method: method,
  label: quickLogActivities[method]!,
  fallback: activityIcon(method),
  elapsed: elapsed ?? sampleElapsed[method],
  size: size,
  design: design,
  color: activityAccent(method, context: context),
);

class StudyBoard extends StatelessWidget {
  const StudyBoard(this.design, {super.key});
  final ElapsedGlyphDesign design;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('study-capture'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: littleLogTheme(brightness: Brightness.dark),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(36),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                design.name,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Actual Dart artwork · stroke ${design.stroke} · ${design.weight.value} weight · width ${design.bodyWidth}',
                style: const TextStyle(color: Color(0xffb3c0ba), fontSize: 15),
              ),
              const SizedBox(height: 24),
              _family(Brightness.dark),
              const SizedBox(height: 18),
              _family(Brightness.light),
              const SizedBox(height: 26),
              const Text(
                'Type study / 2× detail',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              Builder(
                builder: (c) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final method in [
                      'bottle',
                      'sleep',
                      'nursing',
                      'diaper',
                    ])
                      glyph(c, method, design, size: 166),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Minute boundary / new log / older history',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (c) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final duration in [
                      const Duration(minutes: 59),
                      const Duration(hours: 1),
                      Duration.zero,
                      const Duration(days: 2),
                    ])
                      Row(
                        children: [
                          glyph(
                            c,
                            'bottle',
                            design,
                            elapsed: duration,
                            size: 68,
                          ),
                          const SizedBox(width: 10),
                          glyph(
                            c,
                            'sleep',
                            design,
                            elapsed: duration,
                            size: 68,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const Spacer(),
              const Text(
                'Synthetic elapsed values • fixed category colors • text cutoff only, no care targets',
                style: TextStyle(fontSize: 13, color: Color(0xffb3c0ba)),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _family(Brightness brightness) => Theme(
    data: littleLogTheme(brightness: brightness),
    child: Builder(
      builder: (c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
        decoration: BoxDecoration(
          color: Theme.of(c).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final method in elapsedIconActivities)
              Column(
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: activityTint(method, context: c),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: glyph(c, method, design),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    quickLogActivities[method]!,
                    style: TextStyle(color: logPalette(c).ink, fontSize: 16),
                  ),
                ],
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> saveCapture(
  WidgetTester t,
  String key,
  String name, {
  double pixelRatio = 2,
}) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(ValueKey(key)),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../output/elapsed-study/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  const round = int.fromEnvironment('STUDY_ROUND', defaultValue: 1);
  testWidgets('render independent design round $round', (t) async {
    t.view.physicalSize = const Size(1080, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    await t.pumpWidget(StudyBoard(studyDesigns[round - 1]));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await saveCapture(
      t,
      'study-capture',
      'round-${round.toString().padLeft(2, '0')}',
    );
    await t.pumpWidget(const SizedBox());
  });
}
