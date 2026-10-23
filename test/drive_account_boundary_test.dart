import 'dart:convert';
import 'package:little_log/controller.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/models.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/family_csv.dart';
import 'google_drive_test.dart'
    show TestAuth, TestAccount, FakeDrive, family, feed;

class AccountTokenAuth extends TestAuth {
  void Function()? duringToken;
  @override
  Future<String> accessToken() async {
    final token = user!.id;
    duringToken?.call();
    return token;
  }
}

void main() {
  final operations = <String, Future<Object?> Function(GoogleDrive)>{
    'backup': (drive) => drive.createFamily(family, 'a'),
    'join': (drive) => drive.openFamily(family.driveFileId!, 'a'),
    'read': (drive) => drive.readFeeds(family),
    'upload': (drive) => drive.appendFeeds(family, [feed('pending')]),
    'prepare existing log': (drive) => drive.prepareSync(family),
    'invitation': (drive) => drive.invite(family, 'caregiver@example.com'),
    'collaborators': (drive) => drive.listCollaborators(family),
    'discovery': (drive) => drive.listFamilies(),
  };
  for (final operation in operations.entries) {
    test(
      '${operation.key} cancels at every response boundary without using another account',
      () async {
        var requests = 0;
        final baseline = FakeDrive();
        final baselineAuth = AccountTokenAuth();
        final baselineDrive = GoogleDrive(
          baselineAuth,
          client: MockClient((r) async {
            requests++;
            return baseline.handle(r);
          }),
        );
        await operation.value(baselineDrive);
        baselineDrive.dispose();
        baselineAuth.dispose();
        expect(requests, greaterThan(0));
        for (var boundary = 1; boundary <= requests; boundary++) {
          for (final switchBack in [false, true]) {
            final auth = AccountTokenAuth();
            final server = FakeDrive();
            var count = 0;
            final drive = GoogleDrive(
              auth,
              client: MockClient((request) async {
                expect(request.headers['authorization'], 'Bearer a');
                expect(++count, lessThanOrEqualTo(boundary));
                final response = await server.handle(request);
                if (count == boundary) {
                  auth.user = TestAccount('b');
                  if (switchBack) auth.user = TestAccount('a');
                }
                return response;
              }),
            );
            await expectLater(
              operation.value(drive),
              throwsStateError,
              reason:
                  '${operation.key}: boundary $boundary, switchBack=$switchBack',
            );
            expect(count, boundary);
            drive.dispose();
            auth.dispose();
          }
        }
      },
    );

    test(
      '${operation.key} rejects a change while obtaining its token',
      () async {
        final auth = AccountTokenAuth();
        auth.duringToken = () => auth.user = TestAccount('b');
        var sent = 0;
        final drive = GoogleDrive(
          auth,
          client: MockClient((_) async {
            sent++;
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          Future.sync(() => operation.value(drive)),
          throwsStateError,
        );
        expect(sent, 0);
        drive.dispose();
        auth.dispose();
      },
    );
  }

  test('paginated discovery cannot combine accounts', () async {
    final auth = AccountTokenAuth();
    var requests = 0;
    final drive = GoogleDrive(
      auth,
      client: MockClient((_) async {
        requests++;
        auth.user = TestAccount('b');
        return http.Response(
          jsonEncode({'files': [], 'nextPageToken': 'next'}),
          200,
        );
      }),
    );
    await expectLater(drive.listFamilies(), throwsStateError);
    expect(requests, 1);
    drive.dispose();
    auth.dispose();
  });

  test(
    'a completed old-account write stays unacknowledged and safely deduplicates on retry',
    () async {
      final auth = AccountTokenAuth();
      final server = FakeDrive();
      var switched = false;
      final drive = GoogleDrive(
        auth,
        client: MockClient((request) async {
          final response = await server.handle(request);
          if (!switched && request.method == 'PUT') {
            switched = true;
            auth.user = TestAccount('b');
          }
          return response;
        }),
      );
      await expectLater(
        drive.appendFeeds(family, [feed('pending')]),
        throwsStateError,
      );
      expect(server.writes, 1);
      auth.user = TestAccount('a');
      await drive.appendFeeds(family, [feed('pending')]);
      expect(server.writes, 1);
      expect(FamilyCsv.decode(server.contents).feeds.map((f) => f.id), [
        'pending',
      ]);
      drive.dispose();
      auth.dispose();
    },
  );
  test(
    'controller retains pending history when an old-account write completes after a switch',
    () async {
      final repo = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      final auth = AccountTokenAuth();
      final server = FakeDrive();
      var switched = false;
      final drive = GoogleDrive(
        auth,
        client: MockClient((r) async {
          final result = await server.handle(r);
          if (r.method == 'PUT' && !switched) {
            switched = true;
            auth.user = TestAccount('b');
          }
          return result;
        }),
      );
      final c = AppController(repo, auth, drive)
        ..loading = false
        ..family = family;
      await repo.saveFamily(family);
      await repo.add(feed('pending'));
      await c.sync(manual: true);
      expect((await repo.feeds(family.id)).single.synced, isFalse);
      expect(c.family!.accountId, 'a');
      expect(c.message, contains('account changed'));
      auth.user = TestAccount('a');
      await c.sync(manual: true);
      expect((await repo.feeds(family.id)).single.synced, isTrue);
      expect(server.writes, 1);
      c.dispose();
      await repo.db.close();
    },
  );

  test(
    'interrupted backup leaves the local log and full history recoverable',
    () async {
      final repo = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      final auth = AccountTokenAuth();
      final server = FakeDrive();
      var switched = false;
      final drive = GoogleDrive(
        auth,
        client: MockClient((r) async {
          final result = await server.handle(r);
          if (r.method == 'POST' &&
              r.url.path == '/upload/drive/v3/files' &&
              !switched) {
            switched = true;
            auth.user = TestAccount('b');
          }
          return result;
        }),
      );
      const local = Family(id: 'family', name: 'Demo', babyName: 'Baby');
      final c = AppController(repo, auth, drive)
        ..loading = false
        ..family = local;
      await repo.saveFamily(local);
      await repo.add(feed('history'));
      await c.sync(manual: true);
      expect(c.family!.isLocal, isTrue);
      expect((await repo.feeds(local.id)).single.id, 'history');
      auth.user = TestAccount('a');
      await c.sync(manual: true);
      expect(c.family!.accountId, 'a');
      expect((await repo.feeds(local.id)).single.synced, isTrue);
      expect(server.fileCreates, 1);
      c.dispose();
      await repo.db.close();
    },
  );
}
