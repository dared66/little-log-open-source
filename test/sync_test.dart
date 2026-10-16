import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/family_cloud.dart';
import 'package:little_log/services/sync_service.dart';

class FakeCloud implements FamilyCloud {
  final List<Feeding> rows = [];
  bool loseResponse = false;
  bool offline = false;
  int writes = 0;
  Completer<void>? block;
  @override
  Future<RemoteHistory> readFeeds(Family family) async {
    if (offline) throw StateError('Offline');
    await block?.future;
    return RemoteHistory(rows.map((f) => f.acknowledged()).toList());
  }

  @override
  Future<void> appendFeeds(Family family, List<Feeding> feeds) async {
    writes++;
    rows.addAll(feeds);
    if (loseResponse) {
      loseResponse = false;
      throw TimeoutException('Lost response');
    }
  }
}

const family = Family(
  id: 'family-a',
  name: 'Family',
  babyName: 'Robin',
  driveFileId: 'sheet-a',
  accountId: 'account-a',
);
Feeding feed(String id, {String familyId = 'family-a'}) => Feeding(
  id: id,
  familyId: familyId,
  at: DateTime.utc(2026, 9, 18, 8),
  method: 'bottle',
  amountMl: 90,
);

void main() {
  late Repository repo;
  late FakeCloud cloud;
  late SyncService sync;
  setUp(() async {
    repo = Repository(
      await databaseFactoryMemory.openDatabase('sync-${newId.v4()}'),
    );
    cloud = FakeCloud();
    sync = SyncService(repo, cloud);
  });
  tearDown(() => repo.db.close());

  test(
    'uploads local entries, pulls caregiver entries and deduplicates',
    () async {
      await repo.add(feed('local'));
      cloud.rows.addAll([feed('remote'), feed('remote')]);
      await sync.sync(family, accountId: 'account-a');
      final entries = await repo.feeds(family.id);
      expect(entries.map((f) => f.id).toSet(), {'local', 'remote'});
      expect(entries.every((f) => f.synced), isTrue);
      expect(cloud.writes, 1);
      await sync.sync(family, accountId: 'account-a');
      expect(cloud.writes, 1);
    },
  );
  test('recovers uncertain append without duplicating the feeding', () async {
    await repo.add(feed('a'));
    cloud.loseResponse = true;
    await expectLater(
      sync.sync(family, accountId: 'account-a'),
      throwsA(isA<TimeoutException>()),
    );
    expect((await repo.feeds(family.id)).single.synced, isFalse);
    await sync.sync(family, accountId: 'account-a');
    expect(cloud.rows.length, 1);
    expect((await repo.feeds(family.id)).single.synced, isTrue);
  });
  test('network errors preserve outbox, reconnect uploads it', () async {
    await repo.add(feed('a'));
    cloud.offline = true;
    await expectLater(
      sync.sync(family, accountId: 'account-a'),
      throwsStateError,
    );
    expect((await repo.feeds(family.id)).single.synced, isFalse);
    cloud.offline = false;
    await sync.sync(family, accountId: 'account-a');
    expect(cloud.rows.single.id, 'a');
  });
  test('another Google account cannot sync this family', () async {
    await repo.add(feed('a'));
    await expectLater(
      sync.sync(family, accountId: 'account-b'),
      throwsStateError,
    );
    expect(cloud.rows, isEmpty);
  });
  test('sync never uploads another local family', () async {
    await repo.add(feed('a'));
    await repo.add(feed('b', familyId: 'other-family'));
    await sync.sync(family, accountId: 'account-a');
    expect(cloud.rows.map((f) => f.id), ['a']);
    expect((await repo.feeds('other-family')).single.synced, isFalse);
  });
  test('overlapping sync requests do not double upload', () async {
    await repo.add(feed('a'));
    cloud.block = Completer<void>();
    final first = sync.sync(family, accountId: 'account-a');
    await sync.sync(family, accountId: 'account-a');
    cloud.block!.complete();
    await first;
    expect(cloud.writes, 1);
  });
  test(
    'publishing CSV requeues legacy acknowledged records only for this family',
    () async {
      await repo.add(feed('old').acknowledged());
      await repo.add(feed('other', familyId: 'other-family').acknowledged());
      await repo.prepareCsvFamily(family);
      expect((await repo.feeds(family.id)).single.synced, false);
      expect((await repo.feeds('other-family')).single.synced, true);
      await sync.sync(family, accountId: 'account-a');
      expect(cloud.rows.single.id, 'old');
    },
  );
  test(
    'pull preserves conflicting local data rather than silently acknowledging',
    () async {
      await repo.add(feed('same'));
      cloud.rows.add(
        Feeding(
          id: 'same',
          familyId: family.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 150,
        ),
      );
      await expectLater(
        sync.sync(family, accountId: 'account-a'),
        throwsFormatException,
      );
      expect((await repo.feeds(family.id)).single.amountMl, 90);
      expect((await repo.feeds(family.id)).single.synced, false);
      expect(cloud.writes, 0);
    },
  );
  test('malformed and future schema rows are rejected', () {
    expect(() => Feeding.fromRow(['bad'], family.id), throwsFormatException);
    final row = feed('a').toRow();
    row[8] = 3;
    expect(() => Feeding.fromRow(row, family.id), throwsFormatException);
    row[8] = 1;
    row[4] = 'NaN';
    expect(() => Feeding.fromRow(row, family.id), throwsFormatException);
  });
}
