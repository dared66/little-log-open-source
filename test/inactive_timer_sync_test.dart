import 'dart:async';

import 'package:flutter_test/flutter_test.dart' hide fail;
import 'package:little_log/activity_details.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_cloud.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';

import 'manual_sync_test.dart' show Account, Auth, Drive;

class FamilyDrive extends Drive {
  FamilyDrive(super.auth);
  final uploadedTo = <String>[];
  final unavailable = <String>{};

  @override
  Future<RemoteHistory> readFeeds(Family family) async {
    if (fail || unavailable.contains(family.id)) {
      throw CloudException('Drive is offline.');
    }
    return RemoteHistory(
      rows.values
          .where((row) => row.familyId == family.id)
          .map((row) => row.acknowledged())
          .toList(),
    );
  }

  @override
  Future<void> appendFeeds(Family family, List<Feeding> feeds) async {
    expect(feeds.every((row) => row.familyId == family.id), isTrue);
    uploadedTo.add(family.id);
    await super.appendFeeds(family, feeds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Repository repo;
  late Auth auth;
  late FamilyDrive drive;
  late AppController c;
  const babyA = Family(
    id: 'baby-a',
    name: 'Family A',
    babyName: 'A',
    driveFileId: 'file-a',
    accountId: 'account',
  );
  const babyB = Family(
    id: 'baby-b',
    name: 'Family B',
    babyName: 'B',
    driveFileId: 'file-b',
    accountId: 'account',
  );
  const local = Family(id: 'local', name: 'Local', babyName: 'Local');
  const otherAccount = Family(
    id: 'baby-b',
    name: 'Other',
    babyName: 'Other',
    driveFileId: 'file-other',
    accountId: 'other-account',
  );
  final start = DateTime.utc(2026, 10, 20, 12);
  final stop = start.add(const Duration(minutes: 8));

  Future<void> startSleep(Family baby, String id) => repo.startTimer(
    ActivityTimer(id: id, familyId: baby.id, method: 'sleep', startedAt: start),
  );
  Future<void> finishSleep(Family baby, String id) => c.finishLiveTimer(
    sessionId: id,
    familyId: baby.id,
    method: 'sleep',
    at: stop,
  );

  setUp(() async {
    repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
    auth = Auth()
      ..user = Account()
      ..driveConnected = true;
    drive = FamilyDrive(auth);
    c = AppController(repo, auth, drive)..loading = false;
    for (final baby in [babyA, babyB, local]) {
      await repo.saveFamily(baby);
    }
    await repo.selectFamily(babyB.id);
    c.family = babyB;
  });
  tearDown(() async {
    await c.sync();
    c.dispose();
    await repo.db.close();
  });

  test(
    'inactive sleep uploads once to its own log without changing selection',
    () async {
      await startSleep(babyA, 'sleep');
      await finishSleep(babyA, 'sleep');
      await c.sync();
      await finishSleep(babyA, 'sleep');
      await c.sync();
      expect(drive.uploadedTo, [babyA.id]);
      final saved = (await repo.feeds(babyA.id)).single;
      expect(saved.id, 'sleep');
      expect(saved.endedAt, stop);
      expect(saved.synced, isTrue);
      expect(c.family!.id, babyB.id);
      expect(await repo.activeFamilyId(), babyB.id);
      expect(c.feeds, isEmpty);
    },
  );

  test(
    'inactive nursing uploads both sides and preserves the selected baby',
    () async {
      await repo.saveSession(
        NursingSession(
          id: 'nursing',
          familyId: babyA.id,
          startedAt: start,
          segmentAt: start.add(const Duration(minutes: 3)),
          side: 'right',
          leftSeconds: 180,
        ),
      );
      await c.performLiveTimerAction(
        sessionId: 'nursing',
        familyId: babyA.id,
        method: 'nursing',
        action: 'pause',
        at: stop,
      );
      await c.finishLiveTimer(
        sessionId: 'nursing',
        familyId: babyA.id,
        method: 'nursing',
        at: stop,
      );
      await c.sync();
      final saved = drive.rows['nursing']!;
      expect(saved.leftSeconds, 180);
      expect(saved.rightSeconds, 300);
      expect(drive.uploadedTo, [babyA.id]);
      expect(c.family!.id, babyB.id);
    },
  );

  test('finishing during another baby upload queues the correct log', () async {
    drive.uploadGate = Completer<void>();
    await repo.add(
      Feeding(
        id: 'bottle-b',
        familyId: babyB.id,
        at: start,
        method: 'bottle',
        amountMl: 90,
      ),
    );
    final syncing = c.sync();
    await drive.started.future;
    await startSleep(babyA, 'sleep');
    await finishSleep(babyA, 'sleep');
    drive.uploadGate!.complete();
    await syncing;
    await c.sync();
    expect(drive.uploadedTo, [babyB.id, babyA.id]);
    expect((await repo.feeds(babyA.id)).single.synced, isTrue);
    expect(c.family!.id, babyB.id);
  });

  test('a failed selected log cannot block the timer log upload', () async {
    drive.unavailable.add(babyB.id);
    await c.sync();
    await startSleep(babyA, 'sleep');
    await finishSleep(babyA, 'sleep');
    await c.sync();
    expect(drive.uploadedTo, [babyA.id]);
    expect((await repo.feeds(babyA.id)).single.synced, isTrue);
    expect(c.family!.id, babyB.id);
    expect(c.message, 'Drive is offline.');
  });

  test(
    'another baby failure does not replace the selected log status',
    () async {
      drive.unavailable.add(babyA.id);
      await repo.add(
        Feeding(
          id: 'pending-a',
          familyId: babyA.id,
          at: start,
          method: 'bottle',
          amountMl: 90,
        ),
      );
      await c.sync(manual: true);
      expect(c.family!.id, babyB.id);
      expect(c.lastSync, isNotNull);
      expect(c.message, isNull);
      expect((await repo.feeds(babyA.id)).single.synced, isFalse);
      expect(drive.creations, 0);
    },
  );

  test(
    'offline completion survives restart and retries with a local baby selected',
    () async {
      c.family = local;
      await repo.selectFamily(local.id);
      drive.fail = true;
      await startSleep(babyA, 'offline-sleep');
      await finishSleep(babyA, 'offline-sleep');
      await c.sync();
      expect((await repo.feeds(babyA.id)).single.synced, isFalse);
      expect(await repo.activityTimers(babyA.id), isEmpty);
      c.dispose();
      auth = Auth()
        ..user = Account()
        ..driveConnected = true;
      drive = FamilyDrive(auth);
      c = AppController(repo, auth, drive)..loading = false;
      c.family = (await repo.families()).singleWhere((f) => f.id == local.id);
      await c.sync();
      expect((await repo.feeds(babyA.id)).single.synced, isTrue);
      expect(drive.uploadedTo, [babyA.id]);
      expect(c.family!.id, local.id);
      expect(drive.creations, 0);
    },
  );

  test(
    'background completion waits for foreground and leaves local and other-account logs alone',
    () async {
      await repo.saveFamily(otherAccount);
      c.family = otherAccount;
      c.setForeground(false);
      for (final baby in [babyA, local, otherAccount]) {
        await startSleep(baby, 'sleep-${baby.id}');
        await finishSleep(baby, 'sleep-${baby.id}');
        await c.sync();
      }
      expect(drive.rows, isEmpty);
      c.setForeground(true);
      // setForeground drains native actions before starting sync.
      await Future<void>.delayed(Duration.zero);
      await c.sync();
      expect(drive.uploadedTo, [babyA.id]);
      expect(drive.creations, 0);
      expect((await repo.feeds(local.id)).single.synced, isFalse);
      expect((await repo.feeds(otherAccount.id)).single.synced, isFalse);
      expect(c.family!.id, babyB.id);
    },
  );
}
