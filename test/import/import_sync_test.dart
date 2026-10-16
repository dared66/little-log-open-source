import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_cloud.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import '../support/nara_csv_fixture.dart';

const sharedBaby = Family(
  id: 'sync-import',
  name: 'QA',
  babyName: 'Robin',
  driveFileId: 'synthetic',
  accountId: 'test',
);

class CsvCloud implements FamilyCloud {
  final rows = <String, Feeding>{};
  bool offline = false, loseResponse = false;
  @override
  Future<RemoteHistory> readFeeds(Family family) async {
    if (offline) throw StateError('Offline');
    final csv = FamilyCsv.decode(
      FamilyCsv(family, rows.values.toList()).encode(),
    );
    return RemoteHistory(csv.feeds.map((r) => r.acknowledged()).toList());
  }

  @override
  Future<void> appendFeeds(Family family, List<Feeding> records) async {
    if (offline) throw StateError('Offline');
    for (final r in records) {
      if (rows[r.id]?.deleted == true && !r.deleted) continue;
      rows[r.id] = r;
    }
    if (loseResponse) {
      loseResponse = false;
      throw TimeoutException('Lost response after commit');
    }
  }
}

Future<void> synchronize(Repository repo, CsvCloud cloud) =>
    SyncService(repo, cloud).sync(sharedBaby, accountId: 'test');
Future<ImportPlan> removal(Repository repo) async {
  final before = await repo.feeds(sharedBaby.id, includeDeleted: true);
  return ImportPlan(
    familyId: sharedBaby.id,
    before: before,
    additions: [],
    removals: before
        .where((r) => !r.deleted && r.source['system'] == 'Nara Baby')
        .toList(),
    duplicates: 0,
    label: 'Remove Nara Baby imports',
  );
}

void main() {
  late Repository a, b;
  late CsvCloud cloud;
  setUp(() async {
    a = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
    b = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
    cloud = CsvCloud();
    await a.applyImport(HistoryImport.preview(naraCsvFixture, sharedBaby, []));
    await a.add(
      Feeding(
        id: 'manual',
        familyId: sharedBaby.id,
        at: DateTime.utc(2026),
        method: 'bottle',
        amountMl: 50,
      ),
    );
  });
  tearDown(() async {
    await a.db.close();
    await b.db.close();
  });
  test(
    'two devices retain source and manual data through import removal undo and reimport',
    () async {
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect(
        (await b.feeds(
          sharedBaby.id,
        )).where((r) => r.source['system'] == 'Nara Baby'),
        hasLength(5),
      );
      await a.applyImport(await removal(a));
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect((await b.feeds(sharedBaby.id)).single.id, 'manual');
      await a.undoImport(sharedBaby.id);
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect(
        snapshotFingerprint(await a.feeds(sharedBaby.id)),
        snapshotFingerprint(await b.feeds(sharedBaby.id)),
      );
      expect(await b.feeds(sharedBaby.id), hasLength(6));
      final reimport = HistoryImport.preview(
        naraCsvFixture,
        sharedBaby,
        await b.feeds(sharedBaby.id, includeDeleted: true),
      );
      expect(reimport.additions, isEmpty);
      await b.applyImport(reimport);
      await synchronize(b, cloud);
      await synchronize(a, cloud);
      expect(await a.feeds(sharedBaby.id), hasLength(6));
    },
  );
  test(
    'remote caregiver correction blocks undo and stale removal without losing the correction',
    () async {
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      final stale = await removal(a);
      final original = (await b.feeds(
        sharedBaby.id,
      )).firstWhere((r) => r.method == 'nursing');
      final corrected = Feeding.fromJson({
        ...original.toJson(),
        'id': 'caregiver-edit',
        'note': 'Caregiver correction',
        'synced': false,
      });
      await b.replace(original, corrected);
      await synchronize(b, cloud);
      await synchronize(a, cloud);
      await expectLater(a.undoImport(sharedBaby.id), throwsStateError);
      await expectLater(a.applyImport(stale), throwsStateError);
      expect(
        (await a.feeds(
          sharedBaby.id,
        )).singleWhere((r) => r.id == corrected.id).source,
        original.source,
      );
      await a.applyImport(await removal(a));
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect((await b.feeds(sharedBaby.id)).single.id, 'manual');
      await a.undoImport(sharedBaby.id);
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect(
        (await b.feeds(
          sharedBaby.id,
        )).where((r) => r.note == 'Caregiver correction'),
        hasLength(1),
      );
    },
  );
  test(
    'offline import with lost upload response retries without duplicates',
    () async {
      cloud.offline = true;
      await expectLater(synchronize(a, cloud), throwsStateError);
      expect((await a.feeds(sharedBaby.id)).every((r) => !r.synced), isTrue);
      cloud.offline = false;
      cloud.loseResponse = true;
      await expectLater(
        synchronize(a, cloud),
        throwsA(isA<TimeoutException>()),
      );
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect(cloud.rows, hasLength(6));
      expect(await b.feeds(sharedBaby.id), hasLength(6));
      expect((await a.feeds(sharedBaby.id)).every((r) => r.synced), isTrue);
    },
  );
  test(
    'offline removal cannot be resurrected by stale active cloud rows',
    () async {
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      cloud.offline = true;
      await a.applyImport(await removal(a));
      await expectLater(synchronize(a, cloud), throwsStateError);
      cloud.offline = false;
      await synchronize(a, cloud);
      await synchronize(b, cloud);
      expect((await a.feeds(sharedBaby.id)).single.id, 'manual');
      expect((await b.feeds(sharedBaby.id)).single.id, 'manual');
    },
  );
}
