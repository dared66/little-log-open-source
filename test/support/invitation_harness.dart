import 'dart:async';
import 'dart:convert';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import '../google_drive_test.dart' show FakeDrive;

class HarnessAccount implements GoogleSignInAccount {
  HarnessAccount(this.email);
  @override
  final String email;
  @override
  String get id => email;
  @override
  String? get displayName => email.split('@').first;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class HarnessAuth extends GoogleAuth {
  HarnessAuth(String email) {
    use(email);
  }
  void use(String email) {
    user = HarnessAccount(email);
    ready = true;
    driveConnected = true;
    notifyListeners();
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<String> accessToken() async => user!.email;
  @override
  Future<void> acceptPickerToken(
    String token, {
    required String expectedEmail,
  }) async {
    if (token != expectedEmail || user?.email != expectedEmail) {
      throw StateError('Wrong picker account');
    }
  }

  @override
  Future<void> signOut() async {
    user = null;
    driveConnected = false;
    notifyListeners();
  }
}

/// Permission-aware fake HTTP service; never contacts Google or sends mail.
class InvitationHarness {
  final file = FakeDrive()..owned = false;
  final editors = <String>{'sender@example.com'};
  final appAuthorized = <String>{'sender@example.com'};
  final invitations = <http.Request>[];
  int searches = 0;
  int? listError;
  int? inviteError;
  Completer<void>? gate;
  GoogleDrive client(HarnessAuth auth) => GoogleDrive(
    auth,
    client: MockClient((request) async {
      final email = request.headers['authorization']!.substring(
        'Bearer '.length,
      );
      if (request.url.path.endsWith('/permissions') &&
          request.method == 'POST') {
        if (inviteError != null) return file.json({}, inviteError!);
        if (email != 'sender@example.com') return file.json({}, 403);
        invitations.add(request);
        await gate?.future;
        editors.add(jsonDecode(request.body)['emailAddress'] as String);
        return file.json({'id': 'permission'});
      }
      if (request.url.path == '/drive/v3/files' && request.method == 'GET') {
        searches++;
        if (listError != null) return file.json({}, listError!);
        return file.json({
          'files': [
            if (editors.contains(email) && appAuthorized.contains(email))
              {
                'id': 'csv123456789',
                'name': 'Little Log · Baby.csv',
                'ownedByMe': email == 'sender@example.com',
                'shared': true,
                'modifiedTime': '2026-09-28T20:30:00Z',
                'sharingUser': {'emailAddress': 'sender@example.com'},
                'owners': [
                  {'emailAddress': 'sender@example.com'},
                ],
              },
          ],
        });
      }
      if (!editors.contains(email) || !appAuthorized.contains(email)) {
        return file.json({}, 404);
      }
      await gate?.future;
      return file.handle(request);
    }),
  );
}
