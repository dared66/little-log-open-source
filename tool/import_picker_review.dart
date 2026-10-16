// Manual native-picker harness: isolated in-memory log, synthetic files only.
import 'package:flutter/material.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';

import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/main.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await databaseFactoryMemory.openDatabase('native-import-review');
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth))
    ..loading = false;
  await c.createLocal('Test family', 'Robin');
  runApp(LittleLogApp(controller: c));
}
