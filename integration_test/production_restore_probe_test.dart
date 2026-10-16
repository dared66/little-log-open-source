// Opt-in, read-only live Google diagnostic. Never requests interactive consent.
// ignore_for_file: avoid_print
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:little_log/config.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import '../tool/live_test_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'production account restoration and existing sharing file',
    (tester) async {
      await tester.runAsync(() async {
        const live = LiveTestConfig();
        live.validate();
        expect(AppConfig.configured, isTrue);
        print('LIVE_OAUTH_CLIENT: ${AppConfig.iosClientId}');
        final directory = await getApplicationSupportDirectory();
        final database = File('${directory.path}/little-log.db');
        print('LIVE_LOCAL_DATABASE_PRESENT: ${await database.exists()}');
        final auth = GoogleAuth();
        final drive = GoogleDrive(auth);
        try {
          await auth.initialize();
          for (
            var i = 0;
            i < 15 && (auth.user == null || auth.checkingDrive);
            i++
          ) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          print('LIVE_SDK_READY: ${auth.ready}');
          print('LIVE_ACCOUNT_RESTORED: ${auth.user != null}');
          print('LIVE_DRIVE_GRANT_RESTORED: ${auth.driveConnected}');
          expect(
            auth.ready,
            isTrue,
            reason: 'Production SDK configuration must initialize.',
          );
          expect(
            auth.user,
            isNotNull,
            reason:
                'Live verification requires an existing signed-in account on this simulator.',
          );
          expect(
            auth.driveConnected,
            isTrue,
            reason:
                'Production Drive consent must exist before checking the sharing file.',
          );
          live.checkAccount(auth.user?.email);
          final family = await drive.openFamily(live.fileId, auth.user!.id);
          live.checkOwner(family.ownerEmail);
          final feeds = (await drive.readFeeds(family)).feeds;
          expect(
            feeds.where(
              (entry) =>
                  entry.note == 'Android test entry - disposable sharing proof',
            ),
            hasLength(1),
          );
          expect(
            feeds.where(
              (entry) =>
                  entry.note == 'iPhone test entry - disposable sharing proof',
            ),
            hasLength(1),
          );
          print('LIVE_EXISTING_SHARING_PROOF_READABLE: true');
        } finally {
          drive.dispose();
          auth.dispose();
        }
      });
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_DRIVE'),
  );
}
