import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

void main() {
  testWidgets('create a local family and save a feeding without Google', (
    tester,
  ) async {
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('widget'),
    ))!;
    final repo = Repository(db);
    final auth = GoogleAuth();
    final c = AppController(repo, auth, GoogleDrive(auth));
    await tester.runAsync(c.initialize);
    await tester.pumpWidget(LittleLogApp(controller: c));
    await tester.tap(find.text('New baby log'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('This device'));
    await tester.tap(find.text('This device'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Robin');
    await tester.ensureVisible(find.text('Create baby log'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Create baby log'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    expect(find.text('Robin'), findsOneWidget);
    final logScroll = find
        .descendant(
          of: find.byKey(const PageStorageKey('today')),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Saved on this device'),
      200,
      scrollable: logScroll,
    );
    expect(find.text('Saved on this device'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Bottle'),
      -200,
      scrollable: logScroll,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bottle').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '90');
    await tester.ensureVisible(find.text('Save bottle'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Save bottle'));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('Bottle · 90 ml'),
      200,
      scrollable: logScroll,
    );
    expect(find.textContaining('Bottle · 90 ml'), findsWidgets);
    final saved = await tester.runAsync(() => repo.feeds(c.family!.id));
    expect(saved!.single.amountMl, 90);
    expect(saved.single.synced, isFalse);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(db.close);
  });
  testWidgets('phone layout logs a diaper and starts, switches, ends nursing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('activity-ui'),
    ))!;
    final repo = Repository(db);
    final auth = GoogleAuth();
    final c = AppController(repo, auth, GoogleDrive(auth));
    await tester.runAsync(() async {
      await c.initialize();
      await c.createLocal('Family', 'Robin');
    });
    await tester.pumpWidget(LittleLogApp(controller: c));
    await tester.pumpAndSettle();
    Future<void> tapSave(String label) async {
      await tester.ensureVisible(find.text(label).last);
      await tester.runAsync(() async {
        await tester.tap(find.text(label).last);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }

    await tester.tap(find.text('Nursing').first);
    await tester.pumpAndSettle();
    await tapSave('Start left');
    expect(c.nursing?.side, 'left');
    await tapSave('Switch to right');
    expect(c.nursing?.side, 'right');
    expect(find.text('Finish nursing'), findsNothing);
    await tapSave('Pause nursing');
    await tapSave('Finish nursing');
    expect(c.nursing, isNull);
    expect(find.text('Save nursing'), findsNothing);
    expect(c.feeds.single.method, 'nursing');
    expect(c.feeds.single.endedAt, isNotNull);
    await tester.scrollUntilVisible(find.text('Diaper').first, 150);
    await tapSave('Diaper');
    await tester.tap(find.widgetWithText(FilterChip, 'Dirty'));
    await tester.pumpAndSettle();
    await tapSave('Save diaper');
    expect(c.feeds.where((f) => f.isDiaper).single.diaperKind, 'both');
    expect(c.feeds.length, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(db.close);
  });
}
