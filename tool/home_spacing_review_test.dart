import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import '../test/support/test_fonts.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets('home spacing ${large ? 'large' : 'standard'}', (t) async {
      t.view.physicalSize = Size(large ? 320 : 390, 844);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final repo = Repository(db);
      final auth = GoogleAuth();
      final c = AppController(repo, auth, GoogleDrive(auth))..loading = false;
      await t.runAsync(() => c.createLocal('Family', 'Robin'));
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(t.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../build/home-spacing/$name-${large ? 'large' : 'standard'}.png',
          ),
        );
      }

      await capture('empty');
      await t.runAsync(() async {
        await repo.add(
          Feeding(
            id: 'bottle',
            familyId: c.family!.id,
            at: DateTime.now(),
            method: 'bottle',
            amountMl: 90,
          ),
        );
        await repo.add(
          Feeding(
            id: 'diaper',
            familyId: c.family!.id,
            at: DateTime.now(),
            method: 'diaper',
            diaperKind: 'wet',
          ),
        );
        await c.refresh();
      });
      await t.pumpAndSettle();
      await capture('populated');
      await t.scrollUntilVisible(
        find.byKey(const ValueKey('log-activity-heading')),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await capture('recent');
      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await t.ensureVisible(target);
        await t.tap(target);
        await t.pumpAndSettle();
      }

      await tap('Settings');
      await capture('settings');
      for (final page in ['Units', 'Baby profile', 'Import and recovery']) {
        await tap(page);
        await capture(page.toLowerCase().replaceAll(' ', '-'));
        await t.pageBack();
        await t.pumpAndSettle();
      }
      await tap('Log');
      await t.drag(find.byType(Scrollable).first, const Offset(0, 2000));
      await t.pumpAndSettle();
      final customize = find.descendant(
        of: find.byKey(const ValueKey('quick-log-heading')),
        matching: find.text('Customize'),
      );
      await t.scrollUntilVisible(
        customize,
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(customize);
      await t.pumpAndSettle();
      await capture('quick-log');
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }
}
