import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import 'google_drive_test.dart'
    show FakeDrive, TestAuth, TestAccount, family, feed;
import 'support/shared_log_builds_52_55/services/family_csv.dart' as released;

class ObservedRepository extends Repository {
  ObservedRepository(super.db);
  int mergedRows = 0;
  @override
  Future<void> merge(List<Feeding> feeds) async {
    mergedRows += feeds.length;
    await super.merge(feeds);
  }
}

void main() {
  Future<ObservedRepository> repository() async {
    final repo = ObservedRepository(
      await databaseFactoryMemory.openDatabase(newId.v4()),
    );
    addTearDown(repo.db.close);
    return repo;
  }

  GoogleDrive client(FakeDrive server, {String accountId = 'a'}) {
    final auth = TestAuth()..user = TestAccount(accountId);
    final drive = GoogleDrive(auth, client: MockClient(server.handle));
    addTearDown(drive.dispose);
    addTearDown(auth.dispose);
    return drive;
  }

  test(
    '10000 pending entries upload once; unchanged polls do not rewrite rows',
    () async {
      final repo = await repository();
      final server = FakeDrive();
      final sync = SyncService(repo, client(server));
      final records = List.generate(10000, (i) => feed('large-$i'));
      await repo.merge(records);
      repo.mergedRows = 0;
      await sync.sync(family, accountId: 'a');
      expect(server.writes, 1);
      expect(
        repo.mergedRows,
        10000,
      ); // Only the verified outbox acknowledgment.
      expect((await repo.feeds(family.id)).every((r) => r.synced), isTrue);
      final remote = FamilyCsv.decode(server.contents).feeds;
      expect(remote.map((r) => r.id).toSet(), records.map((r) => r.id).toSet());
      // A shipped reader must still accept the large upload and its IDs.
      expect(released.FamilyCsv.decode(server.contents).feeds.length, 10000);
      final downloads = server.downloads;
      repo.mergedRows = 0;
      await sync.sync(family, accountId: 'a');
      expect(server.writes, 1);
      expect(server.downloads, downloads);
      expect(repo.mergedRows, 0);
    },
  );

  for (final secondDeletes in [false, true]) {
    test(
      'overlapping edit/${secondDeletes ? 'delete' : 'edit'} retains both intentions after 412',
      () async {
        final a = await repository();
        final b = await repository();
        final server = FakeDrive()
          ..contents = FamilyCsv(family, [feed('original')]).encode();
        final syncA = SyncService(a, client(server));
        final syncB = SyncService(b, client(server, accountId: 'b'));
        final familyB = Family.fromJson({...family.toJson(), 'accountId': 'b'});
        await syncA.sync(family, accountId: 'a');
        await syncB.sync(familyB, accountId: 'b');
        final original = (await a.feeds(family.id)).single;
        await a.replace(original, feed('edit-a', note: 'Caregiver A'));
        if (secondDeletes) {
          await b.add(original.asDeleted());
        } else {
          await b.replace(original, feed('edit-b', note: 'Caregiver B'));
        }
        server.beforeWrite = () async {
          await syncB.sync(familyB, accountId: 'b');
        };
        await syncA.sync(family, accountId: 'a');
        await syncA.sync(family, accountId: 'a');
        await syncB.sync(familyB, accountId: 'b');
        expect(server.conflicts, 1);
        final expected = {'edit-a', if (!secondDeletes) 'edit-b'};
        expect((await a.feeds(family.id)).map((r) => r.id).toSet(), expected);
        expect((await b.feeds(family.id)).map((r) => r.id).toSet(), expected);
        for (final repo in [a, b]) {
          final all = await repo.feeds(family.id, includeDeleted: true);
          expect(all.singleWhere((r) => r.id == 'original').deleted, isTrue);
          expect(all.every((r) => r.synced), isTrue);
        }
        final writes = server.writes;
        await syncA.sync(family, accountId: 'a');
        expect(server.writes, writes);
        final legacy = released.FamilyCsv.decode(server.contents);
        expect(
          legacy.feeds.where((r) => !r.deleted).map((r) => r.id).toSet(),
          expected,
        );
      },
    );
  }

  test(
    'failed large upload leaves every outbox entry pending and retry deduplicates',
    () async {
      final repo = await repository();
      final server = FakeDrive()..loseResponse = true;
      final sync = SyncService(repo, client(server));
      await repo.merge(List.generate(1001, (i) => feed('retry-$i')));
      await expectLater(
        sync.sync(family, accountId: 'a'),
        throwsA(isA<TimeoutException>()),
      );
      expect((await repo.feeds(family.id)).every((r) => !r.synced), isTrue);
      await sync.sync(family, accountId: 'a');
      expect(server.writes, 1);
      expect((await repo.feeds(family.id)).every((r) => r.synced), isTrue);
      expect(FamilyCsv.decode(server.contents).feeds.length, 1001);
    },
  );
}
