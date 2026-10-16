import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

// Store captures use a disposable database and invented sample records only.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture store screenshots with sample data', (t) async {
    final directory = await Directory.systemTemp.createTemp('store-captures-');
    final db = await databaseFactoryIo.openDatabase(
      '${directory.path}/sample.db',
    );
    final auth = GoogleAuth()..ready = true;
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await c.createLocal('Sample family', 'Robin');
    final now = DateTime.now();
    await c.addFeed(
      at: now.subtract(const Duration(minutes: 20)),
      method: 'bottle',
      amountMl: 120,
      note: 'Morning bottle',
    );
    await c.addDiaper(
      kind: 'wet',
      at: now.subtract(const Duration(minutes: 50)),
    );
    await c.addActivity(
      method: 'sleep',
      at: now.subtract(const Duration(hours: 2)),
      endedAt: now.subtract(const Duration(hours: 1)),
      note: 'A restful nap',
    );
    await c.addFeed(
      at: now.subtract(const Duration(hours: 3)),
      method: 'nursing',
      minutes: 18,
      leftSeconds: 600,
      rightSeconds: 480,
      note: '',
    );
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await t.pump();
    }
    Future<void> snap(String name) async {
      expect(t.takeException(), isNull);
      await binding.takeScreenshot(name);
    }

    await snap('01-today');
    await t.tap(find.byKey(const ValueKey('log-day-picker')));
    await t.pumpAndSettle();
    await snap('02-calendar');
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await t.tap(find.text('See all activities').last);
    await t.pumpAndSettle();
    await snap('03-activities');
    await t.tap(find.widgetWithText(ListTile, 'Bottle'));
    await t.pumpAndSettle();
    await snap('04-bottle');
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
  });
}
