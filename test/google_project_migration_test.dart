import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:little_log/config.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_io.dart';
import 'google_drive_test.dart' show FakeDrive, family, feed;
import 'support/invitation_harness.dart';

// Model project-specific OAuth grants while retaining the same Drive file,
// Google account and real on-disk local database across application upgrades.
class MigrationAuth extends HarnessAuth {
  MigrationAuth() : super('caregiver@example.com');
  bool granted = true;
  int invalidations = 0;

  @override
  Future<String> accessToken() async {
    if (!granted) throw StateError('Connect Google Drive to continue.');
    return super.accessToken();
  }

  @override
  Future<void> invalidateToken(String token) async {
    invalidations++;
    granted = false;
    driveConnected = false;
  }
}

class MigrationDrive {
  final file = FakeDrive()
    ..owned = false
    ..ownerEmail = 'owner@example.com'
    ..shared = true;
  final grants = <String, Set<String>>{
    'testing': {'caregiver@example.com'},
    'production': <String>{},
  };
  int mutations = 0;

  GoogleDrive client(MigrationAuth auth, String project) => GoogleDrive(
    auth,
    client: MockClient((request) async {
      final email = request.headers['authorization']!.substring(7);
      final authorized = grants[project]!.contains(email);
      if (request.method != 'GET') mutations++;
      if (request.url.path == '/drive/v3/files' && request.method == 'GET') {
        return file.json({
          'files': [
            if (authorized)
              {
                'id': family.driveFileId,
                'name': 'Little Log · Baby.csv',
                'ownedByMe': false,
                'shared': true,
                'owners': [
                  {'emailAddress': 'owner@example.com'},
                ],
              },
          ],
        });
      }
      if (!authorized) return file.json({}, 404);
      return file.handle(request);
    }),
  );
}

void main() {
  late Directory directory;
  late Repository repo;
  late MigrationAuth auth;
  late MigrationDrive server;
  late AppController c;

  Future<void> open(String project) async {
    repo = Repository(
      await databaseFactoryIo.openDatabase('${directory.path}/migration.db'),
    );
    auth = MigrationAuth();
    c = AppController(repo, auth, server.client(auth, project));
    c.setForeground(false);
    await c.initialize();
  }

  Future<void> upgrade() async {
    c.dispose();
    await repo.db.close();
    await open('production');
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'little-log-oauth-migration-',
    );
    server = MigrationDrive();
    await open('testing');
    final selected = Family.fromJson({
      ...family.toJson(),
      'accountId': auth.user!.id,
      'ownerEmail': 'owner@example.com',
      'driveShared': true,
    });
    await repo.saveFamily(selected);
    await repo.add(feed('old').acknowledged());
    await repo.add(feed('pending'));
    await repo.add(feed('deleted').asDeleted());
    server.file.contents = FamilyCsv(family, [feed('old')]).encode();
    c.family = selected;
    await c.refresh();
  });
  tearDown(() async {
    c.dispose();
    await repo.db.close();
    await directory.delete(recursive: true);
  });

  test('production build definitions point both native clients at production', () {
    // Ordinary unconfigured test runs remain usable; migration CI supplies defines.
    if (AppConfig.projectNumber.isEmpty) return;
    expect(AppConfig.projectNumber, '259649378161');
    expect(
      AppConfig.iosClientId,
      '259649378161-42hju28uhnfhqhgn1po92jsppg8kms5g.apps.googleusercontent.com',
    );
    expect(
      AppConfig.webClientId,
      '259649378161-io29onh7gbcfchavdjdaqllmnia4tq3u.apps.googleusercontent.com',
    );
    expect(AppConfig.iosClientId, startsWith('${AppConfig.projectNumber}-'));
    expect(AppConfig.webClientId, startsWith('${AppConfig.projectNumber}-'));
    expect(AppConfig.scopes, ['https://www.googleapis.com/auth/drive.file']);
  });

  test(
    'upgrade retains active shared log, pending entries, deletions and timer',
    () async {
      await c.startActivityTimer('sleep');
      final timer = c.timers.single;
      await upgrade();
      expect(c.family!.driveFileId, family.driveFileId);
      expect(c.family!.accountId, 'caregiver@example.com');
      expect(c.family!.ownerEmail, 'owner@example.com');
      expect(c.timers.single.id, timer.id);
      expect(c.timers.single.startedAt, timer.startedAt);
      final rows = await repo.feeds(family.id, includeDeleted: true);
      expect(rows.map((r) => r.id).toSet(), {'old', 'pending', 'deleted'});
      expect(rows.singleWhere((r) => r.id == 'old').synced, isTrue);
      expect(rows.singleWhere((r) => r.id == 'pending').synced, isFalse);
      expect(rows.singleWhere((r) => r.id == 'deleted').deleted, isTrue);
      expect(c.pendingCount, 2);
    },
  );

  test(
    'same Google identity upgrade syncs the saved file without reselection',
    () async {
      c.dispose();
      await repo.db.close();
      await open('testing');
      expect(c.family!.driveFileId, family.driveFileId);
      await c.sync(manual: true);
      expect(c.message, isNull);
      expect(c.pendingCount, 0);
      expect(server.file.fileCreates, 0);
      expect(c.family!.driveFileId, family.driveFileId);
      final rows = await repo.feeds(family.id, includeDeleted: true);
      expect(rows.where((r) => r.id == 'pending'), hasLength(1));
    },
  );

  test('old project file grant does not imply production access', () async {
    expect(await c.drive.listFamilies(), hasLength(1));
    await upgrade();
    expect(await c.drive.listFamilies(), isEmpty);
    await c.sync(manual: true);
    expect(c.driveFileUnavailable, isTrue);
    expect(c.pendingCount, 2);
    expect(c.family!.driveFileId, family.driveFileId);
    expect(server.mutations, 0);
    expect(server.file.fileCreates, 0);
  });

  test(
    'sign-in without new Drive grant cannot publish a replacement log',
    () async {
      await upgrade();
      auth.granted = false;
      await c.publishFamily();
      expect(c.message, contains('Connect Google Drive'));
      expect(c.pendingCount, 2);
      expect(server.mutations, 0);
      expect(server.file.fileCreates, 0);
    },
  );

  test(
    'reselecting existing file preserves outbox then flushes exactly once',
    () async {
      await upgrade();
      await c.sync(manual: true);
      server.grants['production']!.add(auth.user!.email);
      await c.join(family.driveFileId!);
      expect(c.family!.driveFileId, family.driveFileId);
      expect(c.pendingCount, 2);
      await c.sync(manual: true);
      expect(c.message, isNull);
      expect(c.pendingCount, 0);
      final remote = FamilyCsv.decode(server.file.contents).feeds;
      expect(remote.map((r) => r.id).toSet(), {'old', 'pending', 'deleted'});
      expect(remote, hasLength(3));
      expect(remote.singleWhere((r) => r.id == 'deleted').deleted, isTrue);
      final writes = server.file.writes;
      await c.sync(manual: true);
      expect(server.file.writes, writes);
      expect(server.file.fileCreates, 0);
      expect(server.file.moves, 0);
      await upgrade();
      expect(c.pendingCount, 0);
      expect(c.family!.driveFileId, family.driveFileId);
    },
  );

  for (final status in [401, 403, 404, 429, 503]) {
    test(
      'production HTTP $status preserves records and recovers without recreating CSV',
      () async {
        await upgrade();
        server.grants['production']!.add(auth.user!.email);
        server.file.error = status;
        await c.sync(manual: true);
        expect(c.message, isNotNull);
        expect(c.pendingCount, 2);
        expect(server.file.writes, 0);
        expect(server.file.fileCreates, 0);
        if (status == 401) expect(auth.invalidations, 1);
        server.file.error = null;
        auth.granted = true;
        await c.sync(manual: true);
        expect(c.message, isNull);
        expect(c.pendingCount, 0);
        expect(server.file.fileCreates, 0);
        expect(c.family!.driveFileId, family.driveFileId);
      },
    );
  }

  test(
    'wrong production account cannot upload the previous tester outbox',
    () async {
      await upgrade();
      auth.use('other@example.com');
      server.grants['production']!.add('other@example.com');
      await c.sync(manual: true);
      expect(c.message, contains('account linked to this baby'));
      expect(c.pendingCount, 2);
      expect(server.mutations, 0);
    },
  );

  test(
    'conflicting production history rejects rejoin and keeps both copies',
    () async {
      await upgrade();
      server.grants['production']!.add(auth.user!.email);
      server.file.contents = FamilyCsv(family, [
        feed('pending', note: 'different'),
      ]).encode();
      final remoteBefore = server.file.contents;
      await expectLater(c.join(family.driveFileId!), throwsFormatException);
      expect(
        (await repo.feeds(
          family.id,
        )).singleWhere((r) => r.id == 'pending').note,
        '',
      );
      expect(c.pendingCount, 2);
      expect(server.file.contents, remoteBefore);
      expect(server.mutations, 0);
      expect(
        jsonDecode(jsonEncode(c.family!.toJson()))['driveFileId'],
        family.driveFileId,
      );
    },
  );
}
