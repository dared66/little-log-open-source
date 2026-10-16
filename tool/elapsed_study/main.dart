import 'package:flutter/material.dart';
import '../elapsed_icon_mockup.dart';
import 'designs.dart';
import 'native_fonts.dart';

/// Local Dart mock only. ICON_DIRECTION=1..5; MOCK_LIGHT=true for light mode.
/// A real clock updates minute labels; tapping logs into synthetic state only.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadNativeStudyFonts();
  const direction = int.fromEnvironment('ICON_DIRECTION', defaultValue: 1);
  const light = bool.fromEnvironment('MOCK_LIGHT');
  runApp(
    ElapsedIconsMockupApp(
      design: studyDesigns[direction.clamp(1, 5) + 4],
      live: true,
      brightness: light ? Brightness.light : Brightness.dark,
    ),
  );
}
