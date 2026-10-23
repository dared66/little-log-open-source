import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

class TestAuth extends GoogleAuth {
  bool invalidated = false;
  @override
  Future<String> accessToken() async => 'synthetic-test-token';
  @override
  Future<void> invalidateToken(String token) async {
    invalidated = true;
  }
}

class HangingInvalidationAuth extends TestAuth {
  @override
  Future<void> invalidateToken(String token) => Completer<void>().future;
}

const family = Family(
  id: 'family',
  name: 'Demo',
  babyName: 'Baby',
  driveFileId: 'csv123456789',
  accountId: 'a',
);
Feeding feed(String id, {String note = ''}) => Feeding(
  id: id,
  familyId: family.id,
  at: DateTime.utc(2026),
  method: 'bottle',
  amountMl: 90,
  note: note,
);

/// Stateful fake of Drive's versioned file contract, shared by both clients.
/// This verifies client behavior, not Google's actual enforcement of If-Match.
class FakeDrive {
  String contents = FamilyCsv(family, []).encode();
  int version = 1, writes = 0, downloads = 0, conflicts = 0;
  bool loseResponse = false, rejectAll = false, missingEtag = false;
  bool ignorePreconditions = false;
  bool folderExists = false, recoverable = false, loseCreateResponse = false;
  bool owned = true, trashed = false, canModifyContent = true;
  String? ownerEmail;
  bool? shared;
  int folderCreates = 0, fileCreates = 0, moves = 0;
  List<String> parents = ['root'];
  int? error;
  Future<void> Function()? beforeWrite;
  String get etag => '"v$version"';
  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    expect(request.url.host, 'www.googleapis.com');
    expect(request.url.path, isNot(contains('sheets')));
    if (error != null) return json({}, error!);
    if (request.url.path == '/drive/v3/files' && request.method == 'GET') {
      final q = request.url.queryParameters['q']!;
      if (q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
        return json({
          'files': [
            if (folderExists)
              {
                'id': 'littleLogFolder',
                'name': 'Little Log',
                'appProperties': {'littleLogRole': 'root'},
              },
          ],
        });
      }
      return json({
        'files': [
          if (recoverable)
            {'id': family.driveFileId, 'name': 'Little Log · Demo.csv'},
        ],
      });
    }
    if (request.url.path == '/drive/v3/files' && request.method == 'POST') {
      final meta = jsonDecode(request.body);
      expect(meta['name'], 'Little Log');
      expect(meta['mimeType'], 'application/vnd.google-apps.folder');
      folderCreates++;
      folderExists = true;
      return json({'id': 'littleLogFolder'});
    }
    if (request.method == 'PATCH') {
      expect(request.url.path, '/drive/v3/files/${family.driveFileId}');
      expect(request.url.queryParameters['removeParents'], parents.join(','));
      parents = [request.url.queryParameters['addParents']!];
      moves++;
      return json({'id': family.driveFileId, 'parents': parents});
    }
    if (request.method == 'POST' &&
        request.url.path == '/upload/drive/v3/files') {
      expect(request.headers['content-type'], startsWith('multipart/related'));
      expect(request.body, contains('text/csv'));
      final meta = jsonDecode(
        request.body.split('\r\n').firstWhere((line) => line.startsWith('{')),
      );
      expect(meta['parents'], ['littleLogFolder']);
      expect(meta['appProperties']['littleLogFamilyId'], family.id);
      parents = ['littleLogFolder'];
      fileCreates++;
      recoverable = true;
      if (loseCreateResponse) {
        loseCreateResponse = false;
        throw TimeoutException('Lost creation response');
      }
      return json({'id': family.driveFileId});
    }
    if (request.method == 'GET') {
      if (request.url.queryParameters['alt'] == 'media') {
        downloads++;
        return http.Response(
          contents,
          200,
          headers: {'content-type': 'text/csv; charset=utf-8'},
        );
      }
      return json({
        'id': family.driveFileId,
        'parents': parents,
        'ownedByMe': owned,
        if (ownerEmail != null)
          'owners': [
            {'emailAddress': ownerEmail},
          ],
        if (shared != null) 'shared': shared,
        'capabilities': {'canModifyContent': canModifyContent},
        'trashed': trashed,
        'labels': {'trashed': trashed},
        if (!missingEtag) 'etag': etag,
        'mimeType': 'text/csv',
        'fileSize': utf8.encode(contents).length.toString(),
      });
    }
    if (request.method == 'PUT') {
      final callback = beforeWrite;
      beforeWrite = null;
      await callback?.call();
      if (!ignorePreconditions &&
          (rejectAll || request.headers['if-match'] != etag)) {
        conflicts++;
        return json({}, 412);
      }
      contents = request.body;
      version++;
      writes++;
      if (loseResponse) {
        loseResponse = false;
        throw TimeoutException('Response lost');
      }
      return json({'id': family.driveFileId});
    }
    return json({});
  }
}

void main() {
  test(
    'file authorization reason is preserved separately from other 403 errors',
    () async {
      final cloud = GoogleDrive(
        TestAuth(),
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error': {
                'errors': [
                  {'reason': 'appNotAuthorizedToFile'},
                ],
              },
            }),
            403,
          ),
        ),
      );
      await expectLater(
        cloud.openFamily('csv123456789', 'account'),
        throwsA(
          isA<CloudException>()
              .having((e) => e.reason, 'reason', 'appNotAuthorizedToFile')
              .having((e) => e.status, 'status', 403),
        ),
      );
      cloud.dispose();
    },
  );

  testWidgets('expired access returns even if Google token clearing hangs', (
    t,
  ) async {
    final drive = GoogleDrive(
      HangingInvalidationAuth(),
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    Object? failure;
    var completed = false;
    final read = drive
        .readFeeds(family)
        .then<void>(
          (_) {
            completed = true;
          },
          onError: (Object error) {
            failure = error;
            completed = true;
          },
        );
    await t.pump();
    expect(completed, isFalse);
    await t.pump(const Duration(seconds: 11));
    await read;
    expect(completed, isTrue);
    expect(
      failure,
      isA<CloudException>().having((e) => e.status, 'status', 401),
    );
    expect(failure.toString(), contains('Connect Google Drive again'));
  });
  late TestAuth auth;
  late FakeDrive server;
  late GoogleDrive cloud;
  setUp(() {
    auth = TestAuth();
    server = FakeDrive();
    cloud = GoogleDrive(auth, client: MockClient(server.handle));
  });
  tearDown(() {
    cloud.dispose();
    auth.dispose();
  });

  test(
    'creates CSV and proves a real stale precondition is rejected',
    () async {
      final result = await cloud.createFamily(family, 'a');
      expect(result.driveFileId, family.driveFileId);
      expect(server.conflicts, 1);
      expect(server.writes, 1);
    },
  );
  test('new logs use a reusable Little Log folder', () async {
    await cloud.createFamily(family, 'a');
    await cloud.createFamily(family, 'a');
    expect(server.folderCreates, 1);
    expect(server.fileCreates, 1);
    expect(server.parents, ['littleLogFolder']);
  });
  test('lost creation response reuses the same family file', () async {
    server.loseCreateResponse = true;
    await expectLater(
      cloud.createFamily(family, 'a'),
      throwsA(isA<TimeoutException>()),
    );
    final recovered = await cloud.createFamily(family, 'a');
    expect(recovered.driveFileId, family.driveFileId);
    expect(server.fileCreates, 1);
    expect(server.folderCreates, 1);
  });
  test(
    'manual preparation moves owned files in place and rechecks folder placement',
    () async {
      await cloud.prepareSync(family, force: true);
      expect(server.parents, ['littleLogFolder']);
      expect(server.moves, 1);
      expect(server.fileCreates, 0);
      server.parents = ['root'];
      await cloud.prepareSync(family, force: true);
      expect(server.moves, 2);
      expect(server.folderCreates, 1);
    },
  );
  test('shared caregiver files are never relocated', () async {
    server.owned = false;
    await cloud.prepareSync(family, force: true);
    expect(server.moves, 0);
    expect(server.folderCreates, 0);
  });
  test('creation stops if Drive ignores conditional writes', () async {
    server.ignorePreconditions = true;
    await expectLater(
      cloud.createFamily(family, 'a'),
      throwsA(isA<CloudException>()),
    );
  });
  test(
    'two clients concurrently append without losing either record',
    () async {
      final other = GoogleDrive(auth, client: MockClient(server.handle));
      await cloud.readFeeds(family);
      await other.readFeeds(family);
      server.beforeWrite = () => other.appendFeeds(family, [feed('other')]);
      await cloud.appendFeeds(family, [feed('mine')]);
      expect(FamilyCsv.decode(server.contents).feeds.map((f) => f.id).toSet(), {
        'other',
        'mine',
      });
      expect(server.conflicts, 1);
      other.dispose();
    },
  );
  test('lost response followed by retry does not duplicate', () async {
    server.loseResponse = true;
    await expectLater(
      cloud.appendFeeds(family, [feed('mine')]),
      throwsA(isA<TimeoutException>()),
    );
    await cloud.appendFeeds(family, [feed('mine')]);
    expect(server.writes, 1);
    expect((await cloud.readFeeds(family)).feeds.single.id, 'mine');
  });
  test('unchanged polls use metadata without another download', () async {
    await cloud.readFeeds(family);
    await cloud.readFeeds(family);
    expect(server.downloads, 1);
    server.contents = FamilyCsv(family, [feed('new')]).encode();
    server.version++;
    expect((await cloud.readFeeds(family)).feeds.single.id, 'new');
    expect(server.downloads, 2);
  });
  test('cache never crosses accounts', () async {
    await cloud.readFeeds(family);
    await cloud.readFeeds(
      const Family(
        id: 'family',
        name: 'Demo',
        babyName: 'Baby',
        driveFileId: 'csv123456789',
        accountId: 'b',
      ),
    );
    expect(server.downloads, 2);
  });
  test('missing ETag prevents any write', () async {
    server.missingEtag = true;
    await expectLater(
      cloud.appendFeeds(family, [feed('mine')]),
      throwsA(isA<CloudException>()),
    );
    expect(server.writes, 0);
  });
  test('bounded conflict retries retain pending data', () async {
    server.rejectAll = true;
    await expectLater(
      cloud.appendFeeds(family, [feed('mine')]),
      throwsA(isA<CloudException>()),
    );
    expect(server.conflicts, 4);
    expect(server.writes, 0);
  });
  test('malformed CSV cannot be overwritten', () async {
    server.contents += 'malformed\r\n';
    await expectLater(
      cloud.appendFeeds(family, [feed('mine')]),
      throwsFormatException,
    );
    expect(server.writes, 0);
  });
  test('conflicting same-ID payloads are not silently discarded', () async {
    server.contents = FamilyCsv(family, [
      feed('same', note: 'remote'),
    ]).encode();
    await expectLater(
      cloud.appendFeeds(family, [feed('same', note: 'local')]),
      throwsFormatException,
    );
    expect(server.writes, 0);
  });
  test('wrong-family CSV is not overwritten', () async {
    server.contents = FamilyCsv(
      const Family(id: 'other', name: 'Other', babyName: 'Baby'),
      [],
    ).encode();
    await expectLater(
      cloud.appendFeeds(family, [feed('mine')]),
      throwsFormatException,
    );
    expect(server.writes, 0);
  });
  test('unauthorized response invalidates access', () async {
    server.error = 401;
    await expectLater(
      cloud.readFeeds(family),
      throwsA(isA<CloudException>().having((e) => e.status, 'status', 401)),
    );
    expect(auth.invalidated, true);
  });
  test(
    'missing baby log reports a recoverable 404 without creating a file',
    () async {
      server.error = 404;
      await expectLater(
        cloud.prepareSync(family, force: true),
        throwsA(
          isA<CloudException>()
              .having((e) => e.status, 'status', 404)
              .having(
                (e) => e.message,
                'message',
                contains('remain on this device'),
              ),
        ),
      );
      expect(server.fileCreates, 0);
      expect(server.writes, 0);
    },
  );
  test('trashed baby log is identified as unavailable', () async {
    server.trashed = true;
    await expectLater(
      cloud.readFeeds(family),
      throwsA(
        isA<CloudException>()
            .having((e) => e.status, 'status', 404)
            .having((e) => e.message, 'message', contains('Trash')),
      ),
    );
    expect(server.downloads, 0);
  });
  test('list paginates CSVs and sharing targets the Drive file', () async {
    var pages = 0;
    final adapter = GoogleDrive(
      auth,
      client: MockClient((r) async {
        if (r.method == 'POST') {
          expect(r.url.path, '/drive/v3/files/csv123456789/permissions');
          expect(jsonDecode(r.body)['role'], 'writer');
          expect(r.url.queryParameters['sendNotificationEmail'], 'true');
          expect(
            r.url.queryParameters['emailMessage'],
            contains('Baby’s baby log in Little Log'),
          );
          expect(
            r.url.queryParameters['emailMessage'],
            contains('Sign in with synthetic@example.com'),
          );
          expect(
            r.url.queryParameters['emailMessage'],
            contains('Join baby log'),
          );
          expect(
            r.url.queryParameters['emailMessage'],
            isNot(contains('littlelog://')),
          );
          expect(jsonDecode(r.body)['emailAddress'], 'synthetic@example.com');
          return http.Response('{}', 200);
        }
        expect(r.url.queryParameters['q'], contains('text/csv'));
        pages++;
        return pages == 1
            ? http.Response(
                '{"files":[{"id":"a","name":"A.csv"}],"nextPageToken":"next"}',
                200,
              )
            : http.Response('{"files":[{"id":"b","name":"B.csv"}]}', 200);
      }),
    );
    expect(await adapter.listFamilies(), [
      {
        'id': 'a',
        'babyName': 'A',
        'ownerEmail': '',
        'ownedByMe': 'false',
        'shared': 'false',
        'sharedByEmail': '',
        'modifiedTime': '',
      },
      {
        'id': 'b',
        'babyName': 'B',
        'ownerEmail': '',
        'ownedByMe': 'false',
        'shared': 'false',
        'sharedByEmail': '',
        'modifiedTime': '',
      },
    ]);
    await adapter.invite(family, 'synthetic@example.com');
    adapter.dispose();
  });

  test('same-name logs retain separate file IDs and owners', () async {
    final adapter = GoogleDrive(
      TestAuth(),
      client: MockClient((r) async {
        expect(
          r.url.queryParameters['fields'],
          contains('owners(emailAddress,displayName)'),
        );
        expect(r.url.queryParameters['fields'], contains('modifiedTime'));
        expect(r.url.queryParameters['orderBy'], 'modifiedTime desc');
        return http.Response(
          jsonEncode({
            'files': [
              {
                'id': 'owner-a-file',
                'name': 'Little Log · Lila.csv',
                'ownedByMe': true,
                'shared': false,
                'modifiedTime': '2026-09-27T18:00:00Z',
                'owners': [
                  {'emailAddress': 'a@example.com'},
                ],
              },
              {
                'id': 'owner-b-file',
                'name': 'Little Log · Lila.csv',
                'ownedByMe': false,
                'shared': true,
                'modifiedTime': '2026-09-28T20:30:00Z',
                'sharingUser': {'emailAddress': 'inviter@example.com'},
                'owners': [
                  {'emailAddress': 'b@example.com'},
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final logs = await adapter.listFamilies();
    expect(logs.map((f) => f['babyName']), ['Lila', 'Lila']);
    expect(logs.map((f) => f['ownerEmail']), [
      'a@example.com',
      'b@example.com',
    ]);
    expect(logs.map((f) => f['id']).toSet().length, 2);
    expect(logs.last['modifiedTime'], '2026-09-28T20:30:00Z');
    expect(logs.last['sharedByEmail'], 'inviter@example.com');
    adapter.dispose();
  });

  test('cached CSV still refreshes owner and sharing metadata', () async {
    final server = FakeDrive()
      ..ownerEmail = 'owner@example.com'
      ..shared = false;
    final adapter = GoogleDrive(TestAuth(), client: MockClient(server.handle));
    final first = await adapter.openFamily('csv123456789', 'a');
    expect(first.ownerEmail, 'owner@example.com');
    expect(first.storageLabel, 'Private Google Drive log');
    server.shared = true;
    final second = await adapter.openFamily('csv123456789', 'a');
    expect(second.storageLabel, 'Shared Google Drive log');
    expect(server.downloads, 1);
    adapter.dispose();
  });

  test('lists who the baby log is shared with and their access', () async {
    final adapter = GoogleDrive(
      auth,
      client: MockClient((request) async {
        expect(request.url.path, '/drive/v3/files/csv123456789/permissions');
        expect(request.url.queryParameters['fields'], contains('emailAddress'));
        return http.Response(
          jsonEncode({
            'permissions': [
              {
                'id': 'caregiver',
                'type': 'user',
                'role': 'writer',
                'displayName': 'Care Giver',
                'emailAddress': 'care@example.com',
              },
              {
                'id': 'owner',
                'type': 'user',
                'role': 'owner',
                'displayName': 'Parent',
                'emailAddress': 'parent@example.com',
              },
            ],
          }),
          200,
        );
      }),
    );

    expect(await adapter.listCollaborators(family), [
      {'name': 'Parent', 'email': 'parent@example.com', 'role': 'owner'},
      {'name': 'Care Giver', 'email': 'care@example.com', 'role': 'writer'},
    ]);
    adapter.dispose();
  });
}
