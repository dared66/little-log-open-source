import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import 'structural_final_test.dart' show StructuralOverview;
import 'render_test.dart' show loadStudyFonts, saveCapture;

void main() {
  testWidgets('native structural transition frames', (t) async {
    t.view.physicalSize = const Size(950, 1250);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    var frame = 0;
    for (final step in [
      (const Duration(minutes: 59), '59m / before the hour boundary'),
      (const Duration(hours: 1), '1h / the next minute'),
      (const Duration(hours: 1, minutes: 1), '1h 1m / one minute later'),
      (Duration.zero, 'Just logged / now, or a literal 0m in numeral bodies'),
    ]) {
      await t.pumpWidget(
        StructuralOverview(
          elapsed: {
            for (final method in elapsedIconActivities) method: step.$1,
          },
          caption: step.$2,
        ),
      );
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await saveCapture(
          t,
          'construction-capture',
          'structural-motion/frame-${(frame++).toString().padLeft(3, '0')}',
          pixelRatio: 1,
        );
      }
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
  });
}
