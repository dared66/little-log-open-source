import 'package:flutter/material.dart';
import 'package:little_log/design.dart';
import 'package:little_log/quick_log.dart';
import '../elapsed_icon_mockup.dart';
import 'native_fonts.dart';
import 'structural_glyph.dart';

ElapsedIconsMockupApp structuralMock(
  IconConstruction construction, {
  Brightness brightness = Brightness.dark,
  Map<String, Duration?> elapsed = sampleElapsed,
  bool live = false,
  DateTime Function() now = DateTime.now,
}) => ElapsedIconsMockupApp(
  brightness: brightness,
  elapsed: elapsed,
  live: live,
  now: now,
  glyphBuilder: (context, method, duration, size) => StructuralElapsedGlyph(
    method: method,
    label: quickLogActivities[method]!,
    elapsed: duration,
    size: size,
    color: activityAccent(method, context: context),
    background: activityTint(method, context: context),
    construction: construction,
  ),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadNativeStudyFonts();
  const direction = int.fromEnvironment(
    'STRUCTURAL_DIRECTION',
    defaultValue: 1,
  );
  const light = bool.fromEnvironment('MOCK_LIGHT');
  runApp(
    structuralMock(
      IconConstruction.values[direction.clamp(1, 5) - 1],
      live: true,
      brightness: light ? Brightness.light : Brightness.dark,
    ),
  );
}
