import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  testWidgets('baby profile and import are reached directly from Settings', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);

    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    final controller = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => controller.createLocal('Family', 'Robin'));
    await t.pumpWidget(LittleLogApp(controller: controller));
    await t.pumpAndSettle();

    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    expect(find.text('Baby profile'), findsOneWidget);
    expect(find.text('Import and recovery'), findsOneWidget);

    Future<void> open(String label) async {
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    await open('Units');
    expect(find.text('Baby profile'), findsNothing);
    expect(find.text('Import and recovery'), findsNothing);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await open('Baby profile');
    expect(find.text('Robin’s profile'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await open('Import and recovery');
    expect(find.text('Import for Robin'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    controller.dispose();
    await t.runAsync(db.close);
  });
}
