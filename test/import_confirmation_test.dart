import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/import_page.dart';
import 'package:little_log/services/import_file.dart';

void main() {
  ImportFile? selected;
  Future<AppController> open(WidgetTester t) async {
    selected = null;
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => c.createLocal('Family', 'Robin'));
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await t.pumpWidget(
      MaterialApp(
        home: ImportPage(controller: c, pickFile: () async => selected),
      ),
    );
    await t.pumpAndSettle();
    return c;
  }

  Feeding entry(Family family) => Feeding(
    id: 'original',
    familyId: family.id,
    at: DateTime.utc(2026, 10, 3),
    method: 'bottle',
    amountMl: 50,
  );

  Future<void> tap(WidgetTester t, String label) async {
    final finder = find.text(label);
    await t.ensureVisible(finder);
    await t.tap(finder);
    // The import page stays busy while its confirmation is open.
    await t.pump(const Duration(milliseconds: 300));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> preview(WidgetTester t, Family family, Feeding record) async {
    selected = ImportFile('backup.csv', FamilyCsv(family, [record]).encode());
    await tap(t, 'Choose file');
  }

  for (final existing in [true, false]) {
    testWidgets(
      'destructive import requires explicit confirmation (${existing ? 'existing' : 'new'} deletion)',
      (t) async {
        final c = await open(t);
        final family = c.family!;
        final record = entry(family);
        if (existing) await t.runAsync(() => c.repository.add(record));
        await preview(t, family, record.asDeleted());
        await tap(t, 'Import these entries');
        expect(find.text('Import changes to history?'), findsOneWidget);
        final before = await t.runAsync(
          () => c.repository.feeds(family.id, includeDeleted: true),
        );
        expect(before!.where((f) => f.deleted), isEmpty);
        await tap(t, 'Cancel');
        expect(
          (await t.runAsync(
            () => c.repository.feeds(family.id, includeDeleted: true),
          ))!.where((f) => f.deleted),
          isEmpty,
        );
        await tap(t, 'Import these entries');
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(
          (await t.runAsync(
            () => c.repository.feeds(family.id, includeDeleted: true),
          ))!.where((f) => f.deleted),
          isEmpty,
        );
        await tap(t, 'Import these entries');
        await tap(t, 'Import changes');
        final saved = await t.runAsync(
          () => c.repository.feeds(family.id, includeDeleted: true),
        );
        expect(saved!.single.deleted, isTrue);
        expect(
          find.textContaining('Import saved on this device.'),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets('undo removes imported history only after confirmation', (
    t,
  ) async {
    final c = await open(t);
    final family = c.family!;
    await preview(t, family, entry(family));
    await tap(t, 'Import these entries');
    expect(find.byType(AlertDialog), findsNothing);
    expect((await t.runAsync(() => c.repository.feeds(family.id)))!.length, 1);
    await tap(t, 'Undo last import');
    expect(find.text('Undo last import?'), findsOneWidget);
    expect((await t.runAsync(() => c.repository.feeds(family.id)))!.length, 1);
    await tap(t, 'Keep import');
    expect((await t.runAsync(() => c.repository.feeds(family.id)))!.length, 1);
    await tap(t, 'Undo last import');
    await tap(t, 'Undo import');
    expect(await t.runAsync(() => c.repository.feeds(family.id)), isEmpty);
    expect(find.textContaining('Import undone.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('changing baby during confirmation prevents deletion', (t) async {
    final c = await open(t);
    final family = c.family!;
    final record = entry(family);
    await t.runAsync(() => c.repository.add(record));
    await preview(t, family, record.asDeleted());
    await tap(t, 'Import these entries');
    await t.runAsync(() => c.createLocal('Family', 'Sam'));
    await tap(t, 'Import changes');
    expect(
      (await t.runAsync(() => c.repository.feeds(family.id)))!.single.id,
      record.id,
    );
    expect(find.textContaining('Import saved on this device.'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
