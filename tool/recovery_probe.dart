// Native process/reboot probe using a separate database and synthetic records.
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
    '${support.path}/qa-process-recovery.db',
  );
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth));
  await c.initialize();
  if (c.family == null) {
    await c.createLocal('Synthetic QA', 'Restart sample');
    await c.addFeed(
      at: DateTime.now(),
      method: 'bottle',
      amountMl: 90,
      note: 'Process recovery sample',
    );
    await c.nursingAction('left');
    await c.startActivityTimer('sleep');
    await c.startActivityTimer('pumping');
  }
  runApp(LittleLogApp(controller: c));
  final result = {
    'pid': pid,
    'checked_at': DateTime.now().toIso8601String(),
    'family': c.family!.id,
    'records': c.feeds.map((r) => r.toJson()).toList(),
    'nursing': c.nursing?.toJson(),
    'timers': c.timers.map((r) => r.toJson()).toList(),
    'error': c.message,
  };
  // Synthetic probe state only; no normal app records or credentials.
  // ignore: avoid_print
  print('QA_PROCESS_RESULT ${jsonEncode(result)}');
  await File('${support.path}/qa-process-results.jsonl').writeAsString(
    '${jsonEncode(result)}\n',
    mode: FileMode.append,
    flush: true,
  );
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      await File('${external.path}/qa-process-results.jsonl').writeAsString(
        await File('${support.path}/qa-process-results.jsonl').readAsString(),
        flush: true,
      );
    }
  }
}
