import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('10000 records load, navigate and save on native storage', (
    t,
  ) async {
    final directory = await (await getApplicationSupportDirectory()).createTemp(
      'qa-performance-',
    );
    var db = await databaseFactoryIo.openDatabase('${directory.path}/large.db');
    var repo = Repository(db);
    const family = Family(
      id: 'qa-performance',
      name: 'QA',
      babyName: 'Performance sample',
    );
    await repo.saveFamily(family);
    final now = DateTime.now();
    final records = List.generate(
      10000,
      (i) => Feeding(
        id: 'sample-$i',
        familyId: family.id,
        at: now.subtract(Duration(minutes: i * 30)),
        method: 'bottle',
        amountMl: 90,
        note: 'Synthetic QA record',
      ),
    );
    final seed = Stopwatch()..start();
    await repo.merge(records);
    seed.stop();
    await db.close();
    final open = Stopwatch()..start();
    db = await databaseFactoryIo.openDatabase('${directory.path}/large.db');
    repo = Repository(db);
    final auth = GoogleAuth();
    final c = AppController(repo, auth, GoogleDrive(auth));
    await c.initialize();
    open.stop();
    expect(c.feeds.length, 10000);
    final firstFrame = Stopwatch()..start();
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    firstFrame.stop();
    if (Platform.isAndroid) {
      // scripts/run_native_tests.py forwards the host DDS port to the emulator.
      // Retain DDS: Flutter's native golden comparator needs its custom stream.
      final info = await developer.Service.getInfo();
      // ignore: avoid_print
      print('ANDROID_PROFILER_PORT: ${info.serverUri!.port}');
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (true) {
        try {
          await binding.enableTimeline();
          break;
        } on StateError catch (error) {
          if (!error.message.contains('Failed to connect to VM Service') ||
              DateTime.now().isAfter(deadline)) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
    await binding.watchPerformance(() async {
      for (var i = 0; i < 5; i++) {
        for (final tab in ['Log', 'Settings', 'Log']) {
          await t.tap(find.text(tab).last);
          await t.pumpAndSettle();
        }
      }
    }, reportKey: 'navigation');
    final save = Stopwatch()..start();
    await c.addFeed(
      at: DateTime.now(),
      method: 'bottle',
      amountMl: 60,
      note: 'Post-load save',
    );
    save.stop();
    expect(c.feeds.length, 10001);
    expect((await repo.feeds(family.id)).length, 10001);
    expect(t.takeException(), isNull);
    binding.reportData!['large_history'] = {
      'records': 10000,
      'seed_ms': seed.elapsedMilliseconds,
      'open_and_initialize_ms': open.elapsedMilliseconds,
      'first_settled_frame_ms': firstFrame.elapsedMilliseconds,
      'save_and_refresh_ms': save.elapsedMilliseconds,
    };
    // Keep synthetic timing evidence in CLI runs as well as driver reports.
    // ignore: avoid_print
    print(
      'LARGE_HISTORY_METRICS ${jsonEncode(binding.reportData!['large_history'])}',
    );
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });
}
