import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models.dart';
import 'family_cloud.dart';
import 'family_csv.dart';
import 'google_auth.dart';
import 'invitation_link.dart';

class CloudException implements Exception {
  CloudException(this.message, [this.status, this.reason]);
  final String message;
  final int? status;
  final String? reason;
  @override
  String toString() => message;
}

class _Snapshot {
  _Snapshot(this.etag, this.csv);
  final String etag;
  final FamilyCsv csv;
}

class GoogleDrive implements FamilyCloud {
  GoogleDrive(this.auth, {http.Client? client})
    : _client = client ?? http.Client();
  final GoogleAuth auth;
  final http.Client _client;
  final _cache = <String, _Snapshot>{};

  Family? cachedFamily(Family family) =>
      _cache['${family.accountId}/${family.driveFileId}']?.csv.family;

  final _folderRequests = <String, Future<String>>{};
  final _organized = <String>{};

  String _babyNameFromDriveName(String fileName) {
    var name = fileName.trim();
    const prefix = 'Little Log · ';
    if (name.startsWith(prefix)) name = name.substring(prefix.length);
    if (name.toLowerCase().endsWith('.csv')) {
      name = name.substring(0, name.length - 4);
    }
    name = name.replaceFirst(
      RegExp(r"[’']s family$", caseSensitive: false),
      '',
    );
    return name.trim().isEmpty ? 'Baby' : name.trim();
  }

  String _queryValue(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  Future<List<Map<String, dynamic>>> _files(
    String query, {
    required GoogleAccountSession session,
    String fields = 'id,name,parents,ownedByMe,appProperties',
  }) async {
    final files = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final result = _json(
        await _request(
          session,
          'GET',
          '/drive/v3/files',
          query: {
            'q': query,
            'fields': 'nextPageToken,files($fields)',
            'pageSize': '100',
            'pageToken': ?pageToken,
          },
        ),
      );
      files.addAll(
        (result['files'] as List? ?? []).cast<Map<String, dynamic>>(),
      );
      pageToken = result['nextPageToken'] as String?;
    } while (pageToken != null);
    return files;
  }

  Future<String> littleLogFolder(String accountId) async =>
      _littleLogFolder(auth.captureAccount(expectedAccountId: accountId));

  Future<String> _littleLogFolder(GoogleAccountSession session) async {
    auth.checkAccount(session);
    final accountId = '${session.accountId}/${session.revision}';
    final active = _folderRequests[accountId];
    if (active != null) return active;
    final request = _findOrCreateFolder(session);
    _folderRequests[accountId] = request;
    try {
      return await request;
    } finally {
      if (identical(_folderRequests[accountId], request)) {
        _folderRequests.remove(accountId);
      }
    }
  }

  Future<String> _findOrCreateFolder(GoogleAccountSession session) async {
    final folders = await _files(
      session: session,
      "trashed = false and 'me' in owners and mimeType = 'application/vnd.google-apps.folder' and (name = 'Little Log' or appProperties has { key='littleLogRole' and value='root' })",
    );
    if (folders.isNotEmpty) {
      folders.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
      return (folders
                  .where((f) => f['appProperties']?['littleLogRole'] == 'root')
                  .firstOrNull ??
              folders.first)['id']
          as String;
    }
    final folder = _json(
      await _request(
        session,
        'POST',
        '/drive/v3/files',
        query: {'fields': 'id'},
        json: {
          'name': 'Little Log',
          'mimeType': 'application/vnd.google-apps.folder',
          'appProperties': {'littleLogRole': 'root'},
        },
      ),
    );
    return folder['id'] as String;
  }

  /// Move an existing owned log in place, preserving its ID, links and sharing.
  /// Shared logs stay in their owner's folder; a caregiver cannot relocate them.
  Future<void> prepareSync(Family family, {bool force = false}) async =>
      _prepareSync(
        family,
        auth.captureAccount(expectedAccountId: family.accountId),
        force: force,
      );

  Future<void> _prepareSync(
    Family family,
    GoogleAccountSession session, {
    bool force = false,
  }) async {
    auth.checkAccount(session);
    final key = '${family.accountId}/${family.driveFileId}';
    if (force) {
      _cache.remove(key);
      _organized.remove(key);
    }
    if (_organized.contains(key)) return;
    await _familySnapshot(
      family,
      session,
    ); // Validate before changing file metadata.
    final meta = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files/${family.driveFileId}',
        query: {'fields': 'id,parents,ownedByMe,trashed,writersCanShare'},
      ),
    );
    if (meta['trashed'] == true) {
      throw CloudException(
        'This baby’s Drive log is in Trash. Restore it in Google Drive, then retry. Entries remain on this device.',
        404,
        'trashed',
      );
    }
    if (meta['ownedByMe'] == true) {
      final folder = await _littleLogFolder(session);
      final parents = (meta['parents'] as List? ?? []).cast<String>();
      if (!parents.contains(folder) || meta['writersCanShare'] != false) {
        await _request(
          session,
          'PATCH',
          '/drive/v3/files/${family.driveFileId}',
          query: {
            if (!parents.contains(folder)) 'addParents': folder,
            if (!parents.contains(folder) && parents.isNotEmpty)
              'removeParents': parents.join(','),
            'fields': 'id,parents',
          },
          json: {'writersCanShare': false},
        );
        _cache.remove(key);
      }
    }
    _organized.add(key);
  }

  // v2 exposes a file ETag in JSON (including to web clients). v3 is used for
  // discovery, creation and sharing. No Sheets endpoint is used.
  Future<http.Response> _request(
    GoogleAccountSession session,
    String method,
    String path, {
    Map<String, String>? query,
    Object? json,
    String? media,
    Map<String, String>? headers,
    String? contentType,
  }) async {
    auth.checkAccount(session);
    final token = await auth.accessToken();
    auth.checkAccount(session);
    final request = http.Request(
      method,
      Uri.https('www.googleapis.com', path, query),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type':
          contentType ??
          (media == null
              ? 'application/json; charset=utf-8'
              : 'text/csv; charset=utf-8'),
      ...?headers,
    });
    if (json != null) request.body = jsonEncode(json);
    if (media != null) request.body = media;
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 25));
    // A response from the old account must not update caches or acknowledge
    // local history after an account switch, including a switch away and back.
    auth.checkAccount(session);
    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        // Play Services can leave token clearing unresolved. Still surface the
        // original expired-access error so sync unlocks and the user can retry.
        await auth
            .invalidateToken(token)
            .timeout(const Duration(seconds: 10), onTimeout: () {});
      }
      String? reason;
      try {
        final body = jsonDecode(response.body);
        final errors = body['error']?['errors'];
        if (errors is List && errors.isNotEmpty) {
          reason = errors.first['reason'] as String?;
        }
      } catch (_) {
        // Preserve the HTTP error when Drive returns an unexpected body.
      }
      throw CloudException(
        switch (response.statusCode) {
          401 => 'Google access expired. Connect Google Drive again.',
          403 =>
            'Google denied this request. Check file permissions or retry if Drive is rate limiting.',
          404 =>
            'This baby’s Drive log is unavailable. It may be in Trash, deleted, or no longer shared with you. Entries remain on this device.',
          412 =>
            'Another caregiver updated the CSV. Sync will merge and retry.',
          429 =>
            'Drive is busy. Your entries are saved locally and will retry later.',
          _ =>
            'Drive could not finish syncing (${response.statusCode}). Local entries are retained.',
        },
        response.statusCode,
        reason,
      );
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> _metadata(
    String id,
    GoogleAccountSession session,
  ) async => _json(
    await _request(
      session,
      'GET',
      '/drive/v2/files/$id',
      query: {
        'fields':
            'id,etag,mimeType,fileSize,labels/trashed,owners(emailAddress,displayName),shared',
      },
    ),
  );

  String _etag(Map<String, dynamic> meta) {
    if (meta['labels']?['trashed'] == true) {
      throw CloudException(
        'This baby’s Drive log is in Trash. Restore it in Google Drive, then retry. Entries remain on this device.',
        404,
        'trashed',
      );
    }
    if (!['text/csv', 'application/csv'].contains(meta['mimeType'])) {
      throw const FormatException(
        'Choose a Little Log CSV file. Sheets are not supported by this build.',
      );
    }
    final size = int.tryParse(meta['fileSize']?.toString() ?? '0') ?? 0;
    if (size > FamilyCsv.maxBytes) {
      throw const FormatException('CSV exceeds the 10 MB limit.');
    }
    final tag = meta['etag'];
    if (tag is! String || tag.isEmpty || tag.startsWith('W/')) {
      throw CloudException(
        'Drive did not provide a safe file version. Sync stopped without overwriting your CSV.',
      );
    }
    return tag;
  }

  FamilyCsv _identify(FamilyCsv csv, Map<String, dynamic> metadata) {
    final owners = metadata['owners'] as List? ?? const [];
    final owner = owners.isEmpty ? null : owners.first as Map;
    return FamilyCsv(
      csv.family.withDriveIdentity(
        email: owner?['emailAddress'] as String?,
        name: owner?['displayName'] as String?,
        shared: metadata['shared'] as bool?,
      ),
      csv.feeds,
      needsCompatibilityRewrite: csv.needsCompatibilityRewrite,
    );
  }

  Future<_Snapshot> _read(String id, GoogleAccountSession session) async {
    final accountId = session.accountId;
    final key = '$accountId/$id';
    for (var attempt = 0; attempt < 4; attempt++) {
      final metadata = await _metadata(id, session);
      final before = _etag(metadata);
      final cached = _cache[key];
      if (cached?.etag == before) {
        final refreshed = _Snapshot(before, _identify(cached!.csv, metadata));
        _cache[key] = refreshed;
        return refreshed;
      }
      final response = await _request(
        session,
        'GET',
        '/drive/v2/files/$id',
        query: {'alt': 'media'},
      );
      final after = _etag(await _metadata(id, session));
      // Bind content to its metadata ETag even if someone wrote during download.
      if (before != after) continue;
      final csv = FamilyCsv.decode(
        utf8.decode(response.bodyBytes),
        fileId: id,
        accountId: accountId,
      );
      final snapshot = _Snapshot(after, _identify(csv, metadata));
      _cache[key] = snapshot;
      return snapshot;
    }
    throw CloudException(
      'This CSV is changing quickly. Your entries are retained; retry sync shortly.',
    );
  }

  Future<Family> createFamily(Family local, String accountId) async {
    final session = auth.captureAccount(expectedAccountId: accountId);
    final folder = await _littleLogFolder(session);
    // Reuse a previous creation if its response or local persistence was lost.
    final existing = await _files(
      session: session,
      "trashed = false and 'me' in owners and mimeType = 'text/csv' and appProperties has { key='littleLogFamilyId' and value='${_queryValue(local.id)}' }",
    );
    if (existing.isNotEmpty) {
      final recovered = await _openFamily(
        existing.first['id'] as String,
        session,
      );
      if (recovered.id != local.id) {
        throw const FormatException(
          'The existing Drive log belongs to another family.',
        );
      }
      await _prepareSync(recovered, session);
      return recovered;
    }
    final boundary = 'little_log_${newId.v4()}';
    final csv = FamilyCsv(local, []).encode();
    final body =
        '--$boundary\r\nContent-Type: application/json; charset=utf-8\r\n\r\n'
        '${jsonEncode({
          'name': 'Little Log · ${local.name}.csv',
          'mimeType': 'text/csv',
          'parents': [folder],
          'appProperties': {'littleLogFamilyId': local.id},
          'writersCanShare': false,
        })}\r\n'
        '--$boundary\r\nContent-Type: text/csv; charset=utf-8\r\n\r\n$csv\r\n--$boundary--\r\n';
    final result = _json(
      await _request(
        session,
        'POST',
        '/upload/drive/v3/files',
        query: {'uploadType': 'multipart', 'fields': 'id'},
        media: body,
        contentType: 'multipart/related; boundary=$boundary',
      ),
    );
    final id = result['id'] as String;
    // Exercise a real stale version, not a fabricated tag that the service may
    // reject while parsing. All probe writes use identical EMPTY content.
    // Never perform this probe on an existing family file.
    final initialTag = _etag(await _metadata(id, session));
    await _request(
      session,
      'PUT',
      '/upload/drive/v2/files/$id',
      query: {'uploadType': 'media'},
      media: csv,
      headers: {'If-Match': initialTag},
    );
    final updatedTag = _etag(await _metadata(id, session));
    if (initialTag == updatedTag) {
      throw CloudException(
        'Drive did not advance the test file version. Safe shared writes could not be verified. The empty test file remains in Drive.',
      );
    }
    try {
      await _request(
        session,
        'PUT',
        '/upload/drive/v2/files/$id',
        query: {'uploadType': 'media'},
        media: csv,
        headers: {'If-Match': initialTag},
      );
      throw CloudException(
        'Drive accepted an invalid file version. Shared CSV writes are unsafe in this environment. The empty test file remains in Drive.',
      );
    } on CloudException catch (e) {
      if (e.status != 412) rethrow;
    }
    return (await _read(id, session)).csv.family;
  }

  Future<Family> openFamily(String id, String accountId) async =>
      _openFamily(id, auth.captureAccount(expectedAccountId: accountId));

  Future<Family> _openFamily(String id, GoogleAccountSession session) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{10,200}$').hasMatch(id)) {
      throw const FormatException('Choose a valid Drive CSV file.');
    }
    final access = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files/$id',
        query: {'fields': 'capabilities(canModifyContent)'},
      ),
    );
    if (access['capabilities']?['canModifyContent'] != true) {
      throw StateError(
        'You have view-only access to this log. Ask the sender to give your Google account Editor access, then try again.',
      );
    }
    return (await _read(id, session)).csv.family;
  }

  Future<List<Map<String, String>>> listFamilies() async {
    final session = auth.captureAccount();
    final files = <Map<String, String>>[];
    String? pageToken;
    do {
      final result = _json(
        await _request(
          session,
          'GET',
          '/drive/v3/files',
          query: {
            'q':
                "trashed = false and (mimeType = 'text/csv' or mimeType = 'application/csv') and name contains 'Little Log'",
            'fields':
                'nextPageToken,files(id,name,owners(emailAddress,displayName),ownedByMe,shared,sharingUser(emailAddress,displayName),modifiedTime)',
            'orderBy': 'modifiedTime desc',
            'pageSize': '100',
            'pageToken': ?pageToken,
          },
        ),
      );
      for (final f in result['files'] as List<dynamic>? ?? []) {
        files.add({
          'id': f['id'] as String,
          'babyName': _babyNameFromDriveName(f['name'] as String),
          'ownerEmail':
              ((f['owners'] as List? ?? []).firstOrNull?['emailAddress']
                  as String?) ??
              '',
          'ownedByMe': '${f['ownedByMe'] == true}',
          'shared': '${f['shared'] == true}',
          'sharedByEmail': (f['sharingUser']?['emailAddress'] as String?) ?? '',
          'modifiedTime': (f['modifiedTime'] as String?) ?? '',
        });
      }
      pageToken = result['nextPageToken'] as String?;
    } while (pageToken != null);
    return files;
  }

  Future<List<Map<String, String>>> listCollaborators(Family family) async {
    if (family.driveFileId == null) return const [];
    final session = auth.captureAccount(expectedAccountId: family.accountId);
    final result = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files/${family.driveFileId}/permissions',
        query: {
          'fields': 'permissions(id,type,role,emailAddress,displayName)',
          'pageSize': '100',
        },
      ),
    );
    final people = <Map<String, String>>[];
    for (final raw in result['permissions'] as List<dynamic>? ?? const []) {
      final permission = raw as Map<String, dynamic>;
      final type = permission['type'] as String? ?? 'user';
      final email = permission['emailAddress'] as String? ?? '';
      final displayName = permission['displayName'] as String? ?? '';
      final fallback = switch (type) {
        'anyone' => 'Anyone with the link',
        'domain' => 'People in your Google Workspace',
        'group' => email.isEmpty ? 'Google group' : email,
        _ => email.isEmpty ? 'Google user' : email,
      };
      people.add({
        'name': displayName.isEmpty ? fallback : displayName,
        'email': email,
        'role': permission['role'] as String? ?? 'reader',
      });
    }
    people.sort((a, b) {
      if (a['role'] == 'owner' && b['role'] != 'owner') return -1;
      if (b['role'] == 'owner' && a['role'] != 'owner') return 1;
      return a['name']!.toLowerCase().compareTo(b['name']!.toLowerCase());
    });
    return people;
  }

  /// Share an exact-log HTTPS invitation through the user's chosen app.
  String invitationEmailMessage(Family family, String email) =>
      '${auth.user?.email ?? 'A caregiver'} invited you to ${family.babyName}’s log.\n\n'
      'Join in Little Log:\n'
      '${InvitationLink.webForFamily(family, email)}\n\n'
      'Use ${email.trim()} to sign in.';

  String invitationInstructions(Family family, String email) =>
      invitationEmailMessage(family, email);

  Future<void> invite(Family family, String email) async {
    email = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const FormatException('Enter a valid Google email address.');
    }
    if (family.isLocal) {
      throw StateError('Save this baby’s log to Drive first.');
    }
    final accountId = auth.user?.id;
    if (accountId == null || accountId != family.accountId) {
      throw StateError('Sign in with this log’s Google account to continue.');
    }
    final session = auth.captureAccount(expectedAccountId: accountId);
    // Editing a CSV does not grant permission to invite. Never trust the
    // cached owner email or the account used to connect a shared log.
    final metadata = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files/${family.driveFileId}',
        query: {'fields': 'ownedByMe,trashed,writersCanShare'},
      ),
    );
    if (metadata['ownedByMe'] != true || metadata['trashed'] == true) {
      throw StateError('Only the log’s owner can invite caregivers.');
    }
    // Enforce the same rule in Drive, including for older app versions.
    if (metadata['writersCanShare'] != false) {
      await _request(
        session,
        'PATCH',
        '/drive/v3/files/${family.driveFileId}',
        json: {'writersCanShare': false},
      );
    }
    await _request(
      session,
      'POST',
      '/drive/v3/files/${family.driveFileId}/permissions',
      // Drive's notification opens its CSV viewer, not Little Log.
      // The caller opens the native share sheet after access is granted.
      query: {'sendNotificationEmail': 'false'},
      json: {'type': 'user', 'role': 'writer', 'emailAddress': email},
    );
  }

  Future<_Snapshot> _familySnapshot(
    Family family,
    GoogleAccountSession session,
  ) async {
    final snapshot = await _read(family.driveFileId!, session);
    if (snapshot.csv.family.id != family.id) {
      throw const FormatException(
        'The CSV belongs to a different family. Nothing was uploaded.',
      );
    }
    return snapshot;
  }

  @override
  Future<RemoteHistory> readFeeds(Family family) async {
    final session = auth.captureAccount(expectedAccountId: family.accountId);
    final csv = (await _familySnapshot(family, session)).csv;
    return RemoteHistory(
      csv.feeds,
      needsCompatibilityRewrite: csv.needsCompatibilityRewrite,
    );
  }

  @override
  Future<void> appendFeeds(Family family, List<Feeding> feeds) async {
    final session = auth.captureAccount(expectedAccountId: family.accountId);
    final key = '${family.accountId}/${family.driveFileId}';
    for (var attempt = 0; attempt < 4; attempt++) {
      final snapshot = await _familySnapshot(family, session);
      final merged = {for (final f in snapshot.csv.feeds) f.id: f};
      var changed = snapshot.csv.needsCompatibilityRewrite;
      for (final feed in feeds) {
        if (feed.familyId != family.id) {
          throw const FormatException('Cannot upload another family’s entry.');
        }
        final existing = merged[feed.id];
        if (existing != null &&
            jsonEncode(existing.originalRow) != jsonEncode(feed.originalRow)) {
          throw const FormatException(
            'An entry ID has conflicting contents. No cloud records were overwritten.',
          );
        }
        if (existing == null || (feed.deleted && !existing.deleted)) {
          merged[feed.id] = feed;
          changed = true;
        }
      }
      if (!changed) return; // Lost-response retry already exists remotely.
      final csv = FamilyCsv(snapshot.csv.family, merged.values.toList());
      try {
        await _request(
          session,
          'PUT',
          '/upload/drive/v2/files/${family.driveFileId}',
          query: {'uploadType': 'media'},
          media: csv.encode(),
          headers: {'If-Match': snapshot.etag},
        );
        _cache.remove(key);
        // Verify committed IDs/content before acknowledging the local outbox.
        final verified = await _familySnapshot(family, session);
        final byId = {for (final f in verified.csv.feeds) f.id: f};
        final expected = snapshot.csv.needsCompatibilityRewrite
            ? merged.values
            : feeds;
        if (verified.csv.needsCompatibilityRewrite ||
            expected.any(
              (f) =>
                  byId[f.id] == null ||
                  jsonEncode(byId[f.id]!.originalRow) !=
                      jsonEncode(f.originalRow) ||
                  (f.deleted && !byId[f.id]!.deleted),
            )) {
          throw CloudException(
            'Could not verify the CSV upload. Local entries remain pending.',
          );
        }
        return;
      } on CloudException catch (e) {
        _cache.remove(key);
        if (e.status != 412) rethrow;
      } catch (_) {
        _cache.remove(key);
        rethrow;
      }
    }
    throw CloudException(
      'Other caregivers are updating the CSV. Local entries remain pending; retry shortly.',
    );
  }

  // Development-only UI calls these methods against marked synthetic fixtures.
  Future<String> createMonthlyProbeFolder() async {
    final session = auth.captureAccount();
    final folder = await _littleLogFolder(session);
    final meta = _json(
      await _request(
        session,
        'POST',
        '/drive/v3/files',
        json: {
          'name': 'Little Log monthly permission test',
          'parents': [folder],
          'mimeType': 'application/vnd.google-apps.folder',
          'appProperties': {'littleLogFixture': 'monthly-permissions-v1'},
        },
        query: {'fields': 'id'},
      ),
    );
    return meta['id'] as String;
  }

  Future<void> _checkProbeFolder(
    String id,
    GoogleAccountSession session,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{10,200}$').hasMatch(id)) {
      throw const FormatException('Enter the synthetic test folder ID.');
    }
    final meta = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files/$id',
        query: {'fields': 'mimeType,appProperties,trashed'},
      ),
    );
    if (meta['mimeType'] != 'application/vnd.google-apps.folder' ||
        meta['trashed'] == true ||
        meta['appProperties']?['littleLogFixture'] !=
            'monthly-permissions-v1') {
      throw const FormatException(
        'This is not a Little Log synthetic test folder.',
      );
    }
  }

  Future<void> shareMonthlyProbe(String folderId, String email) async {
    final session = auth.captureAccount();
    await _checkProbeFolder(folderId, session);
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      throw const FormatException('Enter the caregiver test account email.');
    }
    await _request(
      session,
      'POST',
      '/drive/v3/files/$folderId/permissions',
      query: {'sendNotificationEmail': 'false'},
      json: {'type': 'user', 'role': 'writer', 'emailAddress': email},
    );
  }

  Future<String> createMonthlyProbeFile(String folderId, String month) async {
    final session = auth.captureAccount();
    await _checkProbeFolder(folderId, session);
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month)) {
      throw const FormatException('Enter a month as YYYY-MM.');
    }
    final family = Family(
      id: folderId,
      name: 'Synthetic monthly test',
      babyName: 'Synthetic baby',
    );
    final csv = FamilyCsv(family, []).encode();
    final boundary = 'little_log_${newId.v4()}';
    final body =
        '--$boundary\r\nContent-Type: application/json; charset=utf-8\r\n\r\n'
        '${jsonEncode({
          'name': '$month.csv',
          'mimeType': 'text/csv',
          'parents': [folderId],
        })}\r\n'
        '--$boundary\r\nContent-Type: text/csv; charset=utf-8\r\n\r\n$csv\r\n--$boundary--\r\n';
    final result = _json(
      await _request(
        session,
        'POST',
        '/upload/drive/v3/files',
        query: {'uploadType': 'multipart', 'fields': 'id'},
        media: body,
        contentType: 'multipart/related; boundary=$boundary',
      ),
    );
    return result['id'] as String;
  }

  Future<String> verifyMonthlyProbe(String folderId) async {
    final session = auth.captureAccount();
    await _checkProbeFolder(folderId, session);
    final account = auth.user;
    if (account == null) throw StateError('Sign in first.');
    final result = _json(
      await _request(
        session,
        'GET',
        '/drive/v3/files',
        query: {
          'q':
              "'$folderId' in parents and trashed = false and mimeType = 'text/csv'",
          'fields': 'files(id,name,isAppAuthorized),nextPageToken',
          'pageSize': '20',
        },
      ),
    );
    final files = result['files'] as List;
    if (files.isEmpty) {
      throw StateError('No monthly CSVs are visible to this account.');
    }
    if (result['nextPageToken'] != null) {
      throw StateError('Unexpectedly large test fixture.');
    }
    final reports = <String>[];
    for (final file in files) {
      final family = await _openFamily(file['id'] as String, session);
      if (family.id != folderId || family.name != 'Synthetic monthly test') {
        throw const FormatException('Unexpected file in test folder; stopped.');
      }
      final entry = Feeding(
        id: newId.v4(),
        familyId: folderId,
        at: DateTime.now().toUtc(),
        method: 'bottle',
        amountMl: 90,
        note: 'Synthetic monthly permission test',
        author: account.email,
      );
      auth.checkAccount(session);
      await appendFeeds(family, [entry]);
      reports.add(
        '${file['name']}: read, conditional write and readback passed; appAuthorized=${file['isAppAuthorized']}',
      );
    }
    return '${account.email}\n${reports.join('\n')}';
  }

  void dispose() {
    _cache.clear();
    _client.close();
  }
}
