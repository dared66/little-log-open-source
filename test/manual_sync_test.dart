import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/family_cloud.dart';

class Account implements GoogleSignInAccount {
  @override
  String get id => 'account';
  @override
  String get email => 'sample@example.com';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Auth extends GoogleAuth {
  bool granted = true;
  @override
  Future<void> initialize() async {}
  @override
  Future<String> accessToken() async {
    if (!granted) throw StateError('Connect Google Drive to continue.');
    return 'test-token';
  }

  void connected() {
    driveConnected = true;
    notifyListeners();
  }
}

class Drive extends GoogleDrive {
  Drive(super.auth);
  final rows = <String, Feeding>{};
  int creations = 0, preparations = 0, reads = 0, writes = 0;
  bool fail = false;
  bool missing = false;
  Completer<void>? uploadGate;
  final started = Completer<void>();
  @override
  Future<Family> createFamily(Family local, String accountId) async {
    creations++;
    return Family(
      id: local.id,
      name: local.name,
      babyName: local.babyName,
      accountId: accountId,
      driveFileId: 'csv123456789',
    );
  }

  @override
  Future<void> prepareSync(Family family, {bool force = false}) async {
    preparations++;
  }

  @override
  Future<RemoteHistory> readFeeds(Family family) async {
    reads++;
    if (fail) throw CloudException('Drive is offline.');
    if (missing) throw CloudException('Drive log unavailable.', 404);
    return RemoteHistory(rows.values.map((f) => f.acknowledged()).toList());
  }

  @override
  Future<void> appendFeeds(Family family, List<Feeding> feeds) async {
    writes++;
    if (!started.isCompleted) started.complete();
    await uploadGate?.future;
    for (final f in feeds) {
      rows[f.id] = f;
    }
  }
}

class PollTimer implements Timer {
  PollTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    tick++;
    callback(this);
  }
}

Feeding entry(String id, {bool synced = false}) => Feeding(
  id: id,
  familyId: 'family',
  at: DateTime.utc(2026, 9, 19),
  method: 'bottle',
  amountMl: 90,
  synced: synced,
);
void main() {
  late Repository repo;
  late Auth auth;
  late Drive drive;
  late AppController c;
  setUp(() async {
    repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
    auth = Auth()
      ..user = Account()
      ..ready = true;
    drive = Drive(auth);
    c = AppController(repo, auth, drive)..loading = false;
    await c.createLocal('Family', 'Robin');
    // Use a stable synthetic family ID for these tests.
    c.family = const Family(id: 'family', name: 'Family', babyName: 'Robin');
    await repo.saveFamily(c.family!);
  });
  tearDown(() async {
    c.dispose();
    await repo.db.close();
  });
  test(
    'foreground polls pull changes; background waits until resume',
    () async {
      await c.publishFamily();
      late PollTimer timer;
      late Duration interval;
      await runZoned(
        c.initialize,
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            interval = duration;
            return timer = PollTimer(callback);
          },
        ),
      );
      expect(interval, const Duration(seconds: 30));
      drive.rows['from-caregiver'] = entry('from-caregiver');
      timer.fire();
      await c
          .sync(); // Join the pass started by the registered polling callback.
      expect(c.feeds.map((f) => f.id), contains('from-caregiver'));
      c.setForeground(false);
      drive.rows['while-backgrounded'] = entry('while-backgrounded');
      final backgroundReads = drive.reads;
      timer.fire();
      expect(drive.reads, backgroundReads);
      expect(c.feeds.map((f) => f.id), isNot(contains('while-backgrounded')));
      final resumed = Completer<void>();
      c.addListener(() {
        if (!resumed.isCompleted &&
            c.feeds.any((f) => f.id == 'while-backgrounded')) {
          resumed.complete();
        }
      });
      c.setForeground(true);
      await resumed.future.timeout(const Duration(seconds: 5));
      expect(c.feeds.map((f) => f.id), contains('while-backgrounded'));
    },
  );
  test(
    'explicit backup publishes the private family log and flushes existing records',
    () async {
      await repo.add(entry('existing', synced: true));
      auth.connected();
      await c.publishFamily();
      expect(drive.creations, 1);
      expect(c.family!.isLocal, false);
      expect(drive.rows.keys, ['existing']);
      expect((await repo.feeds('family')).single.synced, true);
      expect(c.message, isNull);
      expect(c.lastSync, isNotNull);
    },
  );
  test(
    'manual refresh waits for the active upload and drains newly logged entries',
    () async {
      await c.publishFamily();
      await repo.add(entry('first'));
      drive.uploadGate = Completer<void>();
      final background = c.sync();
      await drive.started.future;
      await repo.add(entry('during-upload'));
      var completed = false;
      final manual = c.sync(manual: true).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      drive.uploadGate!.complete();
      await background;
      await manual;
      expect(drive.rows.keys.toSet(), {'first', 'during-upload'});
      expect((await repo.feeds('family')).every((f) => f.synced), true);
      expect(drive.reads, greaterThanOrEqualTo(2));
      expect(drive.creations, 1);
    },
  );
  test(
    'manual refresh bypasses retry delay and errors preserve pending records',
    () async {
      await repo.add(entry('pending'));
      drive.fail = true;
      await c.publishFamily();
      expect(c.message, 'Drive is offline.');
      expect((await repo.feeds('family')).single.synced, false);
      drive.fail = false;
      await c.sync(manual: true);
      expect(drive.rows.containsKey('pending'), true);
      expect(c.message, isNull);
    },
  );
  test(
    'missing Drive file keeps local entries and clears warning after recovery',
    () async {
      await c.publishFamily();
      expect(c.lastSync, isNotNull);
      await repo.add(entry('pending'));
      drive.missing = true;
      final writesBeforeFailure = drive.writes;

      await c.sync(manual: true);
      expect(c.driveFileUnavailable, true);
      expect(c.message, 'Drive log unavailable.');
      expect((await repo.feeds('family')).single.synced, false);
      expect(drive.writes, writesBeforeFailure);
      expect(c.lastSync, isNotNull);

      drive.missing = false;
      await c.sync(manual: true);
      expect(c.driveFileUnavailable, false);
      expect(c.message, isNull);
      expect((await repo.feeds('family')).single.synced, true);
    },
  );
  test(
    'missing Drive authorization reports a clear failure without creating files',
    () async {
      auth.granted = false;
      await repo.add(entry('pending'));
      await c.publishFamily();
      expect(c.message, contains('Connect Google Drive'));
      expect(drive.creations, 0);
      expect((await repo.feeds('family')).single.synced, false);
    },
  );
}
