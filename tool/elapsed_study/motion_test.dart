import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'final_test.dart' show FinalOverview;
import 'render_test.dart' show loadStudyFonts, saveCapture;

// Native Flutter frames, exported at20fps to show the actual type transition.
// This sequence advances synthetic records; no production records are loaded.
void main() {
  testWidgets('capture five native typography transitions', (t) async {
    t.view.physicalSize = const Size(1080, 1180);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadStudyFonts);
    var frame = 0;
    for (final step in [
      (const Duration(minutes: 59), '59m / before hour boundary'),
      (const Duration(hours: 1), '1h / minute update'),
      (const Duration(hours: 1, minutes: 1), '1h 1m / next minute'),
      (Duration.zero, 'now / new activity logged'),
    ]) {
      await t.pumpWidget(FinalOverview(duration: step.$1, phase: step.$2));
      for (var i = 0; i < 30; i++) {
        await t.pump(const Duration(milliseconds: 50));
        await saveCapture(
          t,
          'final-capture',
          'motion/frame-${(frame++).toString().padLeft(3, '0')}',
          pixelRatio: 1,
        );
      }
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
  });
}
