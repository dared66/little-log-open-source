import 'dart:io';
import 'package:flutter/services.dart';

/// Local design-preview fonts. Platform files are loaded in place and are
/// never copied into assets or committed. Other platforms use their fallback.
Future<void> loadNativeStudyFonts() async {
  if (!Platform.isMacOS) return;
  const systemFonts = {
    'StudySans': '/System/Library/Fonts/SFNS.ttf',
    'StudyCompact': '/System/Library/Fonts/SFCompact.ttf',
    'StudyRounded': '/System/Library/Fonts/SFNSRounded.ttf',
  };
  for (final entry in systemFonts.entries) {
    final file = File(entry.value);
    if (!await file.exists()) continue;
    final loader = FontLoader(entry.key)
      ..addFont(file.readAsBytes().then(ByteData.sublistView));
    await loader.load();
  }
}
