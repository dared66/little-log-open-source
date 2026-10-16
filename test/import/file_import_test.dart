import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/import_file.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/import_page.dart';
import '../support/nara_export_fixture.dart';
import '../support/nara_csv_fixture.dart';
import '../support/nara_full_csv_fixture.dart';

class FailingProviderFile extends XFile {
  FailingProviderFile({this.failLength = false, this.overflow = false})
    : super('/synthetic/provider.csv');
  final bool failLength, overflow;
  @override
  Future<int> length() async {
    if (failLength) throw StateError('Provider authorization expired');
    return 3;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List.fromList([65, 66, 67]);
    if (overflow) {
      yield Uint8List(FamilyCsv.maxBytes);
    } else {
      throw StateError('Cloud download disconnected');
    }
  }
}

void main() {
  group('export file reading', () {
    test(
      'provider permission failure is reported without returning partial content',
      () async {
        await expectLater(
          ImportFile.read(FailingProviderFile(failLength: true)),
          throwsFormatException,
        );
      },
    );
    test(
      'interrupted provider stream is rejected instead of parsing a partial file',
      () async {
        await expectLater(
          ImportFile.read(FailingProviderFile()),
          throwsFormatException,
        );
      },
    );
    test(
      'provider size changes cannot bypass the streaming size limit',
      () async {
        await expectLater(
          ImportFile.read(FailingProviderFile(overflow: true)),
          throwsFormatException,
        );
      },
    );
    test('UTF-8 BOM and Unicode notes survive file loading', () async {
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode('\ufeff${naraExportFixture()}')),
        name: 'Nara export.json',
        path: '/tmp/Nara export.json',
      );
      final result = await ImportFile.read(file);
      expect(result.name, 'Nara export.json');
      expect(jsonDecode(result.contents), jsonDecode(naraExportFixture()));
    });
    test('empty exports are rejected', () async {
      await expectLater(
        ImportFile.read(XFile.fromData(Uint8List.fromList([32, 10]))),
        throwsFormatException,
      );
    });
    test(
      'invalid UTF-8 is rejected rather than replacing characters',
      () async {
        await expectLater(
          ImportFile.read(XFile.fromData(Uint8List.fromList([0xff, 0xff]))),
          throwsFormatException,
        );
      },
    );
    test('oversized files are rejected before parsing', () async {
      await expectLater(
        ImportFile.read(XFile.fromData(Uint8List(FamilyCsv.maxBytes + 1))),
        throwsFormatException,
      );
    });
  });

  late AppController c;
  Future<ImportFile?> Function() picker = () async => null;
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 30; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> open(WidgetTester t, {String babyName = 'Robin'}) async {
    picker = () async => null;
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    c = AppController(Repository(db), auth, GoogleDrive(auth))..loading = false;
    await t.runAsync(() => c.createLocal('Family', babyName));
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await t.pumpWidget(
      MaterialApp(
        home: ImportPage(controller: c, pickFile: () => picker()),
      ),
    );
    await settle(t);
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text));
    await t.tap(find.text(text));
    await settle(t);
  }

  Future<void> select(WidgetTester t, {String? contents}) async {
    picker = () async =>
        ImportFile('nara-robin.json', contents ?? naraExportFixture());
    await tap(
      t,
      find.text('Change file').evaluate().isNotEmpty
          ? 'Change file'
          : 'Choose file',
    );
  }

  Future<List<Feeding>> records(WidgetTester t) async => (await t.runAsync(
    () => c.repository.feeds(c.family!.id, includeDeleted: true),
  ))!;

  testWidgets(
    'file selection previews before saving, imports once, and reports duplicates',
    (t) async {
      await open(t);
      await select(t);
      expect(find.text('Review import'), findsOneWidget);
      expect(find.text('Bottles'), findsOneWidget);
      expect(find.text('Nursing'), findsOneWidget);
      expect(find.text('Diapers'), findsOneWidget);
      expect(await records(t), isEmpty);
      await tap(t, 'Import these entries');
      final saved = await records(t);
      expect(saved.length, 4);
      expect(
        saved.singleWhere((f) => f.method == 'bottle').amountMl,
        closeTo(73.93382390625, 1e-10),
      );
      expect(find.text('Import these entries'), findsNothing);
      await select(t);
      expect(find.text('No new entries to import.'), findsOneWidget);
      expect(find.text('4 already imported'), findsOneWidget);
      expect(find.text('Import these entries'), findsNothing);
      expect((await records(t)).length, 4);
    },
  );
  testWidgets(
    'cancelling the picker leaves history and current preview unchanged',
    (t) async {
      await open(t);
      await tap(t, 'Choose file');
      expect(find.text('Review import'), findsNothing);
      await select(t);
      picker = () async => null;
      await tap(t, 'Change file');
      expect(find.text('nara-robin.json'), findsOneWidget);
      expect(find.text('Review import'), findsOneWidget);
      expect(await records(t), isEmpty);
    },
  );
  testWidgets(
    'a replacement file that fails validation cannot import an old preview',
    (t) async {
      await open(t);
      await select(t);
      await select(t, contents: '{broken');
      expect(find.text('Import these entries'), findsNothing);
      expect(await records(t), isEmpty);
      await select(t);
      expect(find.text('Import these entries'), findsOneWidget);
    },
  );
  testWidgets(
    'a CSV filename cannot disguise unrelated content or leave an import enabled',
    (t) async {
      await open(t);
      await select(t);
      picker = () async => const ImportFile(
        'nara-export.csv',
        'Type,Profile Name\nExpense,Robin',
      );
      await tap(t, 'Change file');
      expect(
        find.textContaining(
          'Choose a Nara Baby export or Little Log CSV backup.',
        ),
        findsOneWidget,
      );
      expect(find.text('Import these entries'), findsNothing);
      expect(await records(t), isEmpty);
      expect(
        await t.runAsync(() => c.repository.canUndoImport(c.family!.id)),
        isFalse,
      );
      expect(
        await t.runAsync(() => c.repository.importReports(c.family!.id)),
        isEmpty,
      );
    },
  );
  testWidgets(
    'full baby CSV previews all ten activities, imports and deduplicates split entries',
    (t) async {
      await open(t, babyName: 'Schema Baby');
      picker = () async =>
          const ImportFile('nara-schema-baby.csv', naraFullCsvFixture);
      await tap(t, 'Choose file');
      expect(await records(t), isEmpty);
      for (final label in [
        'Bottles',
        'Nursing',
        'Diapers',
        'Sleep',
        'Solids',
        'Growth',
        'Health',
        'Routines',
        'Milestones',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('Import supported entries only'), findsNothing);
      await t.ensureVisible(
        find.byKey(const ValueKey('Include 2 unassigned pumping records-true')),
      );
      await t.tap(
        find.byKey(const ValueKey('Include 2 unassigned pumping records-true')),
      );
      await settle(t);
      expect(find.text('Pumping'), findsOneWidget);
      await tap(t, 'Import these entries');
      expect(await records(t), hasLength(33));
      expect(
        (await t.runAsync(
          () => c.repository.importReports(c.family!.id),
        ))!.single['added'],
        32,
      );
      await tap(t, 'Choose file');
      await t.ensureVisible(
        find.byKey(const ValueKey('Include 2 unassigned pumping records-true')),
      );
      await t.tap(
        find.byKey(const ValueKey('Include 2 unassigned pumping records-true')),
      );
      await settle(t);
      expect(find.text('33 already imported'), findsOneWidget);
      expect(find.text('Import these entries'), findsNothing);
    },
  );

  testWidgets('wrong baby is rejected with no writes', (t) async {
    await open(t);
    await select(t, contents: naraExportFixture().replaceFirst('Robin', 'Sam'));
    expect(
      find.text('Baby name doesn’t match the selected baby.'),
      findsOneWidget,
    );
    expect(find.text('Import these entries'), findsNothing);
    expect(await records(t), isEmpty);
  });
  testWidgets('unsupported activity rejects the entire file', (t) async {
    await open(t);
    final raw = jsonDecode(naraExportFixture()) as Map<String, dynamic>;
    (raw['tracks'] as Map)['unknown'] = {
      'type': 'UNKNOWN',
      'beginDt': 1768000000000,
    };
    await select(t, contents: jsonEncode(raw));
    expect(find.textContaining('Unsupported Nara activity'), findsOneWidget);
    expect(await records(t), isEmpty);
  });
  testWidgets(
    'history changed after preview cannot be overwritten; retry uses fresh history',
    (t) async {
      await open(t);
      await select(t);
      await t.runAsync(
        () => c.repository.add(
          Feeding(
            id: 'manual',
            familyId: c.family!.id,
            at: DateTime.utc(2026),
            method: 'bottle',
            amountMl: 50,
          ),
        ),
      );
      await tap(t, 'Import these entries');
      expect(
        find.textContaining('History changed after preview'),
        findsOneWidget,
      );
      expect((await records(t)).single.id, 'manual');
      await tap(t, 'Retry preview');
      await tap(t, 'Import these entries');
      expect((await records(t)).length, 5);
    },
  );
  testWidgets('picker errors can be retried without writing records', (
    t,
  ) async {
    await open(t);
    picker = () async =>
        throw const FormatException('The file could not be read.');
    await tap(t, 'Choose file');
    expect(find.text('The file could not be read.'), findsOneWidget);
    expect(await records(t), isEmpty);
    await select(t);
    expect(find.text('Review import'), findsOneWidget);
  });
  testWidgets('switching baby while file picker is open rejects the file', (
    t,
  ) async {
    await open(t);
    final pending = Completer<ImportFile?>();
    picker = () => pending.future;
    await t.tap(find.text('Choose file'));
    await t.pump();
    await t.runAsync(() => c.createLocal('Other', 'Sam'));
    pending.complete(ImportFile('nara.json', naraExportFixture()));
    await settle(t);
    expect(find.textContaining('selected baby has changed'), findsOneWidget);
    expect(find.text('Import these entries'), findsNothing);
    expect(await records(t), isEmpty);
  });
  testWidgets('unmounting during file selection is safe', (t) async {
    await open(t);
    final pending = Completer<ImportFile?>();
    picker = () => pending.future;
    await t.tap(find.text('Choose file'));
    await t.pump();
    await t.pumpWidget(const SizedBox());
    pending.complete(ImportFile('nara.json', naraExportFixture()));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(await records(t), isEmpty);
  });
  testWidgets('repeated taps open only one picker', (t) async {
    await open(t);
    var calls = 0;
    final pending = Completer<ImportFile?>();
    picker = () {
      calls++;
      return pending.future;
    };
    await t.tap(find.text('Choose file'));
    await t.tap(find.text('Choose file'));
    expect(calls, 1);
    pending.complete(null);
    await settle(t);
  });
  testWidgets('small screen and large text retain file and import controls', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await open(t);
    await select(t);
    await tap(t, 'Import these entries');
    expect((await records(t)).length, 4);
    expect(t.takeException(), isNull);
  });
  testWidgets('CSV picker flow requires explicit opt-in for unassigned pumps', (
    t,
  ) async {
    await open(t);
    picker = () async => const ImportFile('nara-robin.csv', naraCsvFixture);
    await tap(t, 'Choose file');
    expect(find.text('Include 1 unassigned pumping record'), findsOneWidget);
    expect(await records(t), isEmpty);
    final include = find.byKey(
      const ValueKey('Include 1 unassigned pumping record-true'),
    );
    await t.ensureVisible(include);
    await t.tap(include);
    await settle(t);
    await tap(t, 'Import these entries');
    expect((await records(t)).where((r) => r.method == 'pumping').length, 2);
  });
  testWidgets(
    'Nara-only removal is confirmed, preserves manual entries, and can be undone',
    (t) async {
      await open(t);
      await t.runAsync(
        () => c.repository.add(
          Feeding(
            id: 'manual',
            familyId: c.family!.id,
            at: DateTime.utc(2026),
            method: 'bottle',
            amountMl: 50,
          ),
        ),
      );
      await select(t);
      await tap(t, 'Import these entries');
      await tap(t, 'Remove Nara Baby imports');
      expect(find.text('Remove Nara Baby imports?'), findsOneWidget);
      await tap(t, 'Cancel');
      expect((await records(t)).where((r) => !r.deleted).length, 5);
      await tap(t, 'Remove Nara Baby imports');
      await tap(t, 'Remove imports');
      expect((await records(t)).where((r) => !r.deleted).single.id, 'manual');
      await tap(t, 'Undo removal');
      await tap(t, 'Restore imports');
      expect((await records(t)).where((r) => !r.deleted).length, 5);
      expect(
        (await records(
          t,
        )).where((r) => !r.deleted && r.source['system'] == 'Nara Baby').length,
        4,
      );
    },
  );
  testWidgets(
    'excluded CSV rows are shown, require consent, and persist in the report',
    (t) async {
      await open(t);
      final raw = naraCsvFixture.replaceFirst(
        'Diaper,Robin',
        'Unsupported,Robin',
      );
      picker = () async => ImportFile('nara.csv', raw);
      await tap(t, 'Choose file');
      final button = t.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Import these entries'),
      );
      expect(button.onPressed, isNull);
      await tap(t, '2 entries not imported');
      expect(find.text('Row 2 · Unsupported'), findsOneWidget);
      final consent = find.byKey(
        const ValueKey('Import supported entries only-true'),
      );
      await t.ensureVisible(consent);
      await t.tap(consent);
      await settle(t);
      await tap(t, 'Import these entries');
      final reports = await t.runAsync(
        () => c.repository.importReports(c.family!.id),
      );
      expect(reports!.single['issues'], hasLength(2));
      expect((await records(t)).any((r) => r.method == 'diaper'), isFalse);
      await tap(t, 'Import history');
      await tap(t, 'Nara Baby CSV');
      await tap(t, '2 entries not imported');
      expect(find.text('Row 2 · Unsupported'), findsOneWidget);
    },
  );
}
