import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

/// Load real fonts from the SDK running the tests, regardless of install path.
/// Call through WidgetTester.runAsync when used inside a widget test.
Future<void> loadTestFonts() async {
  // Native integration tests use fonts bundled by the mobile engine.
  if (Platform.isAndroid || Platform.isIOS) return;
  final configFile = File('.dart_tool/package_config.json').absolute;
  final config =
      jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
  final flutterPackage = (config['packages'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((package) => package['name'] == 'flutter');
  final rootUri = flutterPackage['rootUri'] as String;
  final flutterRoot = configFile.uri.resolve(
    rootUri.endsWith('/') ? rootUri : '$rootUri/',
  );
  final fonts = flutterRoot.resolve(
    '../../bin/cache/artifacts/material_fonts/',
  );
  for (final entry in {
    'Roboto': 'Roboto-Regular.ttf',
    'MaterialIcons': 'MaterialIcons-Regular.otf',
  }.entries) {
    final loader = FontLoader(entry.key)
      ..addFont(
        File.fromUri(
          fonts.resolve(entry.value),
        ).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
  }
}
