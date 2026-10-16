import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/family_cloud.dart';
import 'package:little_log/services/sync_service.dart';

class Cloud implements FamilyCloud {
  final Map<String, Feeding> rows = {};
  @override
  Future<RemoteHistory> readFeeds(Family family) async =>
      RemoteHistory(rows.values.map((f) => f.acknowledged()).toList());
  @override
  Future<void> appendFeeds(Family family, List<Feeding> feeds) async {
    for (final f in feeds) {
      if (rows[f.id]?.deleted != true) rows[f.id] = f;
    }
  }
}

void main() {
  test(
    'deletion survives stale remote copies, CSV roundtrip and another caregiver sync',
    () async {
      final db = await databaseFactoryMemory.openDatabase('delete');
      final otherDb = await databaseFactoryMemory.openDatabase('other');
      final a = Repository(db), b = Repository(otherDb), cloud = Cloud();
      const family = Family(
        id: 'f',
        name: 'Family',
        babyName: 'Robin',
        driveFileId: 'file',
        accountId: 'account',
      );
      final feed = Feeding(
        id: 'one',
        familyId: 'f',
        at: DateTime.utc(2026),
        method: 'bottle',
        amountMl: 90,
      );
      await a.add(feed);
      await b.add(feed);
      cloud.rows[feed.id] = feed;
      await a.add(feed.asDeleted());
      await SyncService(a, cloud).sync(family, accountId: 'account');
      expect(await a.feeds('f'), isEmpty);
      expect(cloud.rows['one']!.deleted, isTrue);
      final csv = FamilyCsv.decode(
        FamilyCsv(family, cloud.rows.values.toList()).encode(),
      );
      expect(csv.feeds.single.deleted, isTrue);
      expect(csv.feeds.single.originalRow, feed.originalRow);
      await SyncService(b, cloud).sync(family, accountId: 'account');
      expect(await b.feeds('f'), isEmpty);
      await b.merge([feed.acknowledged()]);
      expect(await b.feeds('f'), isEmpty);
      expect((await b.feeds('f', includeDeleted: true)).single.deleted, isTrue);
      await db.close();
      await otherDb.close();
    },
  );
  test(
    'weight preference persists independently of volume and original measurements',
    () async {
      final db = await databaseFactoryMemory.openDatabase('weight');
      final repo = Repository(db);
      expect(await repo.weightUnit(), 'kg');
      await repo.saveWeightUnit('lb');
      expect(await Repository(db).weightUnit(), 'lb');
      final feed = Feeding(
        id: 'w',
        familyId: 'f',
        at: DateTime.utc(2026),
        method: 'growth',
        details: {'measurement': 'Weight', 'value': 4.2, 'unit': 'kg'},
      );
      await repo.add(feed);
      expect((await repo.feeds('f')).single.details['value'], 4.2);
      await db.close();
    },
  );
}
