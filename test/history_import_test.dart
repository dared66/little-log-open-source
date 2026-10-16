import 'support/nara_export_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/record_validation.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';

const f = Family(id: 'sample-family', name: 'Sample', babyName: 'Robin');
void main() {
  test(
    'lossless source and new fields roundtrip through CSV JSON and deletion',
    () {
      final p = HistoryImport.preview(
        naraExportFixture(),
        f,
        [],
        caregivers: {'a': 'Alex', 'b': 'Sam'},
      );
      expect(p.activityCount, 3);
      final n = p.additions.singleWhere((r) => r.method == 'nursing');
      expect(n.endedAt, isNull);
      expect(n.leftSeconds, 600);
      expect(n.source['leftDurationMs'], 600123);
      expect(n.author, 'Sam');
      final d = p.additions.singleWhere((r) => r.isDiaper);
      expect(d.details['poopColors'], ['black', 'green']);
      expect(d.details['poopConsistencies'], ['mushy', 'watery']);
      expect(d.details.containsKey('rash'), false);
      final b = p.additions.singleWhere((r) => r.method == 'bottle');
      expect(b.amountMl, closeTo(73.93382390625, 1e-10));
      expect(b.details['formulaMl'], 0);
      for (final r in p.additions) {
        final decoded = FamilyCsv.decode(
          FamilyCsv(f, [r]).encode(),
        ).feeds.single;
        expect(decoded.toRow(), r.toRow());
        expect(Feeding.fromJson(decoded.toJson()).toRow(), r.toRow());
        final deleted = FamilyCsv.decode(
          FamilyCsv(f, [r.asDeleted()]).encode(),
        ).feeds.single;
        expect(deleted.deleted, true);
        expect(deleted.originalRow, r.originalRow);
      }
    },
  );
  test('duplicates skip, conflicts and unknown units fail closed', () {
    final p = HistoryImport.preview(naraExportFixture(), f, []);
    final repeat = HistoryImport.preview(naraExportFixture(), f, p.additions);
    expect(repeat.additions, isEmpty);
    expect(repeat.duplicates, 4);
    expect(
      () => HistoryImport.preview(
        naraExportFixture().replaceFirst('MUSH RUN', 'MUSH'),
        f,
        p.additions,
      ),
      throwsFormatException,
    );
    expect(
      () => HistoryImport.preview(
        naraExportFixture().replaceFirst('FLOZ', 'UNKNOWN'),
        f,
        [],
      ),
      throwsFormatException,
    );
    expect(
      () => validateRecord(
        Feeding(
          id: 'bad',
          familyId: f.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 100,
          details: {'breastMilkMl': 80, 'formulaMl': 30},
        ),
        f.id,
      ),
      throwsFormatException,
    );
  });
  test('pause survives restart and resume is idempotent', () {
    final t = DateTime.utc(2026);
    var s = NursingSession(
      id: 'timer',
      familyId: f.id,
      startedAt: t,
      segmentAt: t,
      side: 'left',
    );
    s = NursingSession.fromJson(
      s.pause(t.add(const Duration(seconds: 60))).toJson(),
    );
    expect(s.secondsFor('left', t.add(const Duration(hours: 1))), 60);
    s = s.resume(t.add(const Duration(seconds: 120)));
    expect(
      s.resume(t.add(const Duration(seconds: 130))).segmentAt,
      s.segmentAt,
    );
    s = s.switchTo('right', t.add(const Duration(seconds: 180)));
    final done = s.finish(t.add(const Duration(seconds: 240)), 'Alex');
    expect(done.leftSeconds, 120);
    expect(done.rightSeconds, 60);
    expect(done.minutes, 3);
  });
  test(
    'atomic import, stale preview protection and rollback retain manual records',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      addTearDown(db.close);
      final repo = Repository(db);
      await repo.saveFamily(f);
      final stale = HistoryImport.preview(naraExportFixture(), f, []);
      await repo.add(
        Feeding(
          id: 'manual',
          familyId: f.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 50,
        ),
      );
      await expectLater(repo.applyImport(stale), throwsStateError);
      final p = HistoryImport.preview(
        naraExportFixture(),
        f,
        await repo.feeds(f.id, includeDeleted: true),
      );
      await repo.applyImport(p);
      expect((await repo.feeds(f.id)).length, 5);
      await repo.undoImport(f.id);
      expect((await repo.feeds(f.id)).single.id, 'manual');
      expect(
        (await repo.feeds(
          f.id,
          includeDeleted: true,
        )).where((r) => r.deleted).length,
        4,
      );
    },
  );
  test('undo refuses to erase a caregiver correction', () async {
    final db = await databaseFactoryMemory.openDatabase(newId.v4());
    addTearDown(db.close);
    final repo = Repository(db);
    await repo.saveFamily(f);
    final p = HistoryImport.preview(naraExportFixture(), f, []);
    await repo.applyImport(p);
    final old = p.additions.first;
    await repo.replace(
      old,
      Feeding.fromJson({...old.toJson(), 'id': 'edited', 'note': 'Correction'}),
    );
    await expectLater(repo.undoImport(f.id), throwsStateError);
    expect((await repo.feeds(f.id)).any((r) => r.note == 'Correction'), true);
  });
}
