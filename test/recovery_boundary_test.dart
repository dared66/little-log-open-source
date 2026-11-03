import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

import 'support/shared_log_builds_52_55/services/family_csv.dart' as released;

const local = Family(id: 'family', name: 'Family', babyName: 'Sam');
final at = DateTime.utc(2025, 1, 1);
final feeds = stringMapStoreFactory.store('feedings');
final archive = stringMapStoreFactory.store('legacyOriginals');

Feeding sleep(String id, {bool complete = false, bool deleted = false}) =>
    Feeding(
      id: id,
      familyId: local.id,
      method: 'sleep',
      at: at,
      endedAt: complete ? at.add(const Duration(hours: 1)) : null,
      deleted: deleted,
    );

Future<Repository> openMemory() async {
  final db = await databaseFactoryMemory.openDatabase(newId.v4());
  addTearDown(db.close);
  return Repository(db);
}

class DelayedFinish extends Repository {
  DelayedFinish(super.db);
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> finishSession(NursingSession session, Feeding entry) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    await super.finishSession(session, entry);
  }
}

void main() {
  for (final boundary in [
    'acknowledged',
    'account',
    'sheet',
    'drive',
    'missing family',
  ]) {
    test(
      'repair cannot archive a record across the $boundary boundary',
      () async {
        final repo = await openMemory();
        if (boundary != 'missing family') {
          await repo.saveFamily(
            Family(
              id: local.id,
              name: local.name,
              babyName: local.babyName,
              accountId: boundary == 'account' ? 'account' : null,
              legacySheetId: boundary == 'sheet' ? 'sheet' : null,
              driveFileId: boundary == 'drive' ? 'file' : null,
            ),
          );
        }
        final old = sleep('old');
        final raw = {
          ...old.toJson(),
          'synced': boundary == 'acknowledged',
          'unknown': 123,
        };
        await feeds.record('family/old').put(repo.db, raw);
        await expectLater(
          repo.replace(old, sleep('fixed', complete: true)),
          throwsFormatException,
        );
        await expectLater(repo.remove(old), throwsFormatException);
        expect(await feeds.record('family/old').get(repo.db), raw);
        expect(await feeds.record('family/fixed').exists(repo.db), isFalse);
        expect(await archive.count(repo.db), 0);
      },
    );
  }

  test(
    'conflicting repair attempts preserve the winning edit and original',
    () async {
      final repo = await openMemory();
      await repo.saveFamily(local);
      final old = sleep('old');
      final raw = {
        ...old.toJson(),
        'unknown': ['preserve'],
      };
      await feeds.record('family/old').put(repo.db, raw);
      final taken = sleep('occupied', complete: true);
      await repo.add(taken);
      await expectLater(repo.replace(old, taken), throwsStateError);
      expect(await archive.count(repo.db), 0);
      Future<bool> repair(String id) async {
        try {
          await repo.replace(old, sleep(id, complete: true));
          return true;
        } on StateError {
          return false;
        }
      }

      final wins = await Future.wait([repair('edit-a'), repair('edit-b')]);
      expect(wins.where((v) => v), hasLength(1));
      final rows = await repo.feeds(local.id, includeDeleted: true);
      expect(rows.map((r) => r.id).toSet(), {
        'occupied',
        wins.first ? 'edit-a' : 'edit-b',
      });
      expect(await archive.record('family/old').get(repo.db), raw);
      await expectLater(repo.remove(old), throwsStateError);
    },
  );

  test(
    'backup rollback and restart preserve archived originals and family isolation',
    () async {
      final dir = await Directory.systemTemp.createTemp('recovery-boundary-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/db';
      var db = await databaseFactoryIo.openDatabase(path);
      addTearDown(() => db.close());
      var repo = Repository(db);
      const other = Family(id: 'other', name: 'Other', babyName: 'Lee');
      const linked = Family(
        id: 'family',
        name: 'Family',
        babyName: 'Sam',
        driveFileId: 'file',
        accountId: 'account',
      );
      await repo.saveFamily(other);
      await repo.saveFamily(local);
      final deleted = {
        ...sleep('a', deleted: true).toJson(),
        'extra': {'old': true},
      };
      final obstacle = sleep('z');
      await feeds.record('family/a').put(db, deleted);
      await feeds.record('family/z').put(db, obstacle.toJson());
      final unrelated = Feeding.fromJson({
        ...sleep('a').toJson(),
        'familyId': other.id,
      });
      await feeds.record('other/a').put(db, unrelated.toJson());
      await repo.remove(unrelated);
      await expectLater(repo.prepareCsvFamily(linked), throwsFormatException);
      expect(await archive.record('family/a').exists(db), isFalse);
      expect(await feeds.record('family/a').get(db), deleted);
      expect(
        (await repo.families()).singleWhere((f) => f.id == local.id).isLocal,
        isTrue,
      );
      await repo.replace(obstacle, sleep('fixed', complete: true));
      await repo.prepareCsvFamily(linked);
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      final rows = await repo.feeds(local.id, includeDeleted: true);
      expect(
        released.FamilyCsv.decode(
          FamilyCsv(linked, rows).encode(),
        ).feeds.single.id,
        'fixed',
      );
      expect(await archive.record('family/a').get(db), deleted);
      expect(await archive.record('family/z').get(db), obstacle.toJson());
      await repo.deleteBaby(local.id);
      expect(await archive.count(db), 1);
      expect(await archive.record('other/a').get(db), unrelated.toJson());
    },
  );

  test(
    'review that becomes stale during save preserves the newer timer',
    () async {
      final repo = DelayedFinish((await openMemory()).db);
      final auth = GoogleAuth();
      final controller = AppController(repo, auth, GoogleDrive(auth));
      addTearDown(controller.dispose);
      await repo.saveFamily(local);
      controller.family = local;
      final paused = NursingSession(
        id: 'session',
        familyId: local.id,
        startedAt: at,
        segmentAt: at,
        side: 'left',
      ).pause(at.add(const Duration(minutes: 1)));
      await repo.saveSession(paused);
      final finish = controller.saveReviewedNursing(
        session: paused,
        endedAt: paused.segmentAt,
        note: 'first',
      );
      await repo.entered.future;
      final latest = paused
          .switchTo('right', paused.segmentAt)
          .pause(at.add(const Duration(minutes: 2)));
      await repo.saveSession(latest);
      final rejected = expectLater(finish, throwsStateError);
      repo.release.complete();
      await rejected;
      expect((await repo.nursingSession(local.id))!.toJson(), latest.toJson());
      expect(await repo.feeds(local.id), isEmpty);
      await controller.saveReviewedNursing(
        session: latest,
        endedAt: latest.segmentAt,
        note: 'latest',
      );
      await controller.sync();
      final saved = (await repo.feeds(local.id)).single;
      expect(
        [saved.leftSeconds, saved.rightSeconds, saved.note],
        [60, 60, 'latest'],
      );
      expect(await repo.nursingSession(local.id), isNull);
    },
  );
}
