import 'dart:convert';
import 'google_drive_test.dart' show TestAccount;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/monthly_probe_panel.dart';
import 'package:sembast/sembast_memory.dart';

class ProbeAuth extends GoogleAuth {
  ProbeAuth() {
    user = TestAccount('probe');
  }
  @override
  Future<String> accessToken() async => 'synthetic-token';
}

void main() {
  testWidgets('monthly panel follows its build flag', (tester) async {
    final db = await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('monthly-visibility'),
    );
    final auth = GoogleAuth();
    final drive = GoogleDrive(auth);
    final controller = AppController(Repository(db!), auth, drive);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FamilyPanel(controller: controller)),
      ),
    );
    const enabled = bool.fromEnvironment('MONTHLY_PERMISSION_PROBE');
    expect(
      find.byType(MonthlyProbePanel),
      enabled ? findsOneWidget : findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(db.close);
  });

  test('probe refuses to share or populate an unmarked folder', () async {
    final auth = ProbeAuth();
    var mutations = 0;
    final drive = GoogleDrive(
      auth,
      client: MockClient((request) async {
        if (request.method != 'GET') mutations++;
        return http.Response(
          jsonEncode({'mimeType': 'application/vnd.google-apps.folder'}),
          200,
        );
      }),
    );
    await expectLater(
      drive.shareMonthlyProbe('folder123456', 'test@example.com'),
      throwsFormatException,
    );
    await expectLater(
      drive.createMonthlyProbeFile('folder123456', '2026-09'),
      throwsFormatException,
    );
    expect(mutations, 0);
    drive.dispose();
    auth.dispose();
  });

  test(
    'fixture sharing is private writer access without notification',
    () async {
      final auth = ProbeAuth();
      var shares = 0;
      final drive = GoogleDrive(
        auth,
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'mimeType': 'application/vnd.google-apps.folder',
                'appProperties': {'littleLogFixture': 'monthly-permissions-v1'},
              }),
              200,
            );
          }
          shares++;
          expect(request.url.path, '/drive/v3/files/folder123456/permissions');
          expect(request.url.queryParameters['sendNotificationEmail'], 'false');
          expect(jsonDecode(request.body), {
            'type': 'user',
            'role': 'writer',
            'emailAddress': 'test@example.com',
          });
          return http.Response('{}', 200);
        }),
      );
      await drive.shareMonthlyProbe('folder123456', 'test@example.com');
      expect(shares, 1);
      drive.dispose();
      auth.dispose();
    },
  );
}
