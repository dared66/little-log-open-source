// Read-only cloud verification of the explicitly named synthetic QA baby.
// Run on the signed-in Android emulator with the normal Google configuration.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/open_database.dart';
import 'package:little_log/storage/repository.dart';
import 'live_test_config.dart';

Future<void> main() async {
  const live = LiveTestConfig();
  live.validate(requireBaby: true, requireFile: false);
  WidgetsFlutterBinding.ensureInitialized();
  final auth = GoogleAuth();
  final drive = GoogleDrive(auth);
  final c = AppController(Repository(await openLocalDatabase()), auth, drive);
  runApp(LittleLogApp(controller: c));
  final result = <String, Object?>{};
  Future<void> checkpoint(String stage) async {
    result['stage'] = stage;
    final directory = await getExternalStorageDirectory();
    await File('${directory!.path}/qa-live-google.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
      flush: true,
    );
  }

  await checkpoint('initialize');
  try {
    await c.initialize().timeout(const Duration(seconds: 30));
    await checkpoint('restore_auth');
    for (var i = 0; i < 60 && (auth.user == null || auth.checkingDrive); i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    live.checkAccount(auth.user?.email);
    if (c.family?.babyName != live.babyName) {
      throw StateError('Expected synthetic QA baby and test account.');
    }
    result['signed_in'] = auth.user != null;
    result['drive_connected'] = auth.driveConnected;
    await checkpoint('sync');
    await c.sync(manual: true).timeout(const Duration(seconds: 60));
    await checkpoint('read_cloud');
    final remote = await GoogleDrive(auth).readFeeds(c.family!);
    result['local_count'] = c.feeds.length;
    result['pending_count'] = c.pendingCount;
    result['remote_count'] = remote.feeds.length;
    result['matching_ids'] = c.feeds.every(
      (local) => remote.feeds.any(
        (r) => r.id == local.id && r.amountMl == local.amountMl,
      ),
    );
    result['amounts_ml'] = remote.feeds.map((r) => r.amountMl).toList();
    // Inject an expired HTTP response while exercising the real native SDK's
    // token clearing. Verify the app returns its reconnect error promptly.
    await checkpoint('expired_response_recovery');
    final watch = Stopwatch()..start();
    try {
      await GoogleDrive(
        auth,
        client: MockClient((_) async => http.Response('{}', 401)),
      ).readFeeds(c.family!).timeout(const Duration(seconds: 20));
      result['expired_response_unlocked'] = false;
    } on CloudException catch (error) {
      result['expired_response_unlocked'] = error.status == 401;
      result['expired_response_ms'] = watch.elapsedMilliseconds;
    }
    result['passed'] =
        c.pendingCount == 0 &&
        remote.feeds.length == 2 &&
        result['matching_ids'] == true &&
        result['expired_response_unlocked'] == true;
  } catch (error) {
    // Avoid recording credentials or full API payloads.
    result['passed'] = false;
    result['error_type'] = error.runtimeType.toString();
  }
  final directory = await getExternalStorageDirectory();
  await File('${directory!.path}/qa-live-google.json').writeAsString(
    const JsonEncoder.withIndent('  ').convert(result),
    flush: true,
  );
}
