import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import '../support/nara_export_fixture.dart';
import '../support/nara_csv_fixture.dart';

void main() {
  const family = Family(id: 'import-test', name: 'Family', babyName: 'Robin');
  test('disk reopen preserves imported data and undo receipt', () async {
    final dir = await Directory.systemTemp.createTemp('little-log-import-');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/history.db';
    var db = await databaseFactoryIo.openDatabase(path);
    var repo = Repository(db);
    await repo.saveFamily(family);
    await repo.add(
      Feeding(
        id: 'manual',
        familyId: family.id,
        at: DateTime.utc(2026),
        method: 'bottle',
        amountMl: 50,
      ),
    );
    final before = await repo.feeds(family.id, includeDeleted: true);
    final plan = HistoryImport.preview(naraExportFixture(), family, before);
    await repo.applyImport(plan);
    final saved = snapshotFingerprint(await repo.feeds(family.id));
    await db.close();
    db = await databaseFactoryIo.openDatabase(path);
    repo = Repository(db);
    expect(snapshotFingerprint(await repo.feeds(family.id)), saved);
    expect(await repo.canUndoImport(family.id), isTrue);
    await repo.undoImport(family.id);
    expect((await repo.feeds(family.id)).single.id, 'manual');
    expect(await repo.canUndoImport(family.id), isFalse);
    await db.close();
    db = await databaseFactoryIo.openDatabase(path);
    expect((await Repository(db).feeds(family.id)).single.id, 'manual');
    await db.close();
  });
  test(
    'malformed final row yields no partial writes or recovery receipt',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-import-');
      addTearDown(() => dir.delete(recursive: true));
      final db = await databaseFactoryIo.openDatabase('${dir.path}/history.db');
      addTearDown(db.close);
      final repo = Repository(db);
      await repo.saveFamily(family);
      final raw = jsonDecode(naraExportFixture()) as Map<String, dynamic>;
      (raw['tracks'] as Map)['bad-last-row'] = {
        'type': 'FEED',
        'feedType': 'BOTTLE',
        'beginDt': 1768000000000,
        'bottleVolumeNum': -50,
        'bottleVolumeExp': 0,
        'bottleVolumeUnit': 'ML',
      };
      expect(
        () => HistoryImport.preview(jsonEncode(raw), family, []),
        throwsFormatException,
      );
      expect(await repo.feeds(family.id), isEmpty);
      expect(await repo.canUndoImport(family.id), isFalse);
    },
  );
  test(
    'an unchanged duplicate import does not replace the undo receipt',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-import-');
      addTearDown(() => dir.delete(recursive: true));
      final db = await databaseFactoryIo.openDatabase('${dir.path}/history.db');
      addTearDown(db.close);
      final repo = Repository(db);
      await repo.saveFamily(family);
      await repo.applyImport(
        HistoryImport.preview(naraExportFixture(), family, []),
      );
      final duplicate = HistoryImport.preview(
        naraExportFixture(),
        family,
        await repo.feeds(family.id),
      );
      await repo.applyImport(duplicate);
      await repo.undoImport(family.id);
      expect(await repo.feeds(family.id), isEmpty);
    },
  );
  test(
    'reimport never revives an intentionally deleted source entry',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-import-');
      addTearDown(() => dir.delete(recursive: true));
      final db = await databaseFactoryIo.openDatabase('${dir.path}/history.db');
      addTearDown(db.close);
      final repo = Repository(db);
      await repo.saveFamily(family);
      final plan = HistoryImport.preview(naraExportFixture(), family, []);
      await repo.applyImport(plan);
      await repo.undoImport(family.id);
      final duplicate = HistoryImport.preview(
        naraExportFixture(),
        family,
        await repo.feeds(family.id, includeDeleted: true),
      );
      expect(duplicate.additions, isEmpty);
      expect(duplicate.duplicates, 4);
    },
  );
  test(
    'repository rejects partial import without consent and preserves report after reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-partial-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/history.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      final csv = naraCsvFixture.replaceFirst(
        'Diaper,Robin',
        'Unsupported,Robin',
      );
      final blocked = HistoryImport.preview(csv, family, []);
      await expectLater(repo.applyImport(blocked), throwsStateError);
      expect(await repo.feeds(family.id), isEmpty);
      await repo.applyImport(
        HistoryImport.preview(csv, family, [], allowPartial: true),
      );
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      final report = (await repo.importReports(family.id)).single;
      expect(report['issues'], hasLength(2));
      expect(report['added'], 3);
      await db.close();
    },
  );
}
