// Native termination/reboot QA; never opens the normal app database.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final db = await databaseFactoryIo.openDatabase(
    '${support.path}/qa-usability-recovery.db',
  );
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth));
  await c.initialize();
  if (c.family == null) {
    await c.createLocal('Synthetic QA', 'Restart sample');
    await c.setThemeMode(ThemeMode.dark);
    await c.performAssistantAction(
      'add_diaper',
      kind: 'wet',
      at: DateTime.now(),
    );
    for (final action in ['nursing_left', 'sleep', 'pumping']) {
      await c.performAssistantAction(action, at: DateTime.now());
    }
  }
  runApp(LittleLogApp(controller: c));
  final result = {
    'pid': pid,
    'checked_at': DateTime.now().toIso8601String(),
    'family': c.family!.id,
    'theme': c.themeMode.name,
    'records': c.feeds.map((r) => r.toJson()).toList(),
    'nursing': c.nursing?.toJson(),
    'timers': c.timers.map((r) => r.toJson()).toList(),
    'error': c.message,
  };
  await File('${support.path}/qa-usability-results.jsonl').writeAsString(
    '${jsonEncode(result)}\n',
    mode: FileMode.append,
    flush: true,
  );
}
