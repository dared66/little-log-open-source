// Opt-in real Google test. Never runs in the ordinary harness.
// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import '../tool/live_test_config.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real two-account sharing probe',
    (tester) async {
      await tester.runAsync(() async {
        const live = LiveTestConfig();
        live.validate(requireFile: live.mode != 'create');
        final auth = GoogleAuth();
        await auth.initialize();
        for (var i = 0; i < 3 && auth.user == null; i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (auth.user == null) {
          await auth.signIn().timeout(const Duration(seconds: 90));
        }
        live.checkAccount(auth.user?.email);
        print('LIVE_ACCOUNT_VERIFIED: true');
        final drive = GoogleDrive(auth);
        final files = await drive.listFamilies();
        print('LIVE_FILE_COUNT: ${files.length}');
        final target = live.fileId;
        if (target.isNotEmpty) {
          try {
            final f = await drive.openFamily(target, auth.user!.id);
            live.checkOwner(f.ownerEmail);
            print('LIVE_TARGET_READABLE: true');
            final entries = (await drive.readFeeds(f)).feeds;
            print('LIVE_ENTRY_COUNT: ${entries.length}');
            if (const bool.fromEnvironment('LIVE_VERIFY_BOTH')) {
              expect(
                entries.where(
                  (e) =>
                      e.note == 'Android test entry - disposable sharing proof',
                ),
                hasLength(1),
              );
              expect(
                entries.where(
                  (e) =>
                      e.note == 'iPhone test entry - disposable sharing proof',
                ),
                hasLength(1),
              );
              live.checkOwner(f.ownerEmail);
              print('LIVE_BIDIRECTIONAL_VERIFIED: true');
            }
          } on CloudException catch (e) {
            print('LIVE_TARGET_STATUS: ${e.status}');
            if (const bool.fromEnvironment('LIVE_VERIFY_BOTH')) rethrow;
          }
        }
        if (live.mode == 'create') {
          final recipient = live.recipient;
          live.checkOwner(auth.user?.email);
          final f = await drive.createFamily(
            const Family(
              id: 'qa-live-sharing-20260928',
              name: 'Sharing proof 0928',
              babyName: 'Sharing proof 0928',
            ),
            auth.user!.id,
          );
          await drive.appendFeeds(f, [
            Feeding(
              id: 'android-proof-0928',
              familyId: f.id,
              at: DateTime.utc(2026, 9, 29, 4, 35),
              method: 'bottle',
              amountMl: 10,
              note: 'Android test entry - disposable sharing proof',
            ),
          ]);
          await drive.invite(f, recipient);
          print('LIVE_CREATED: true');
          print('LIVE_INVITATION_ACCEPTED: true');
        }
        drive.dispose();
        auth.dispose();
      });
    },
    skip: !const bool.fromEnvironment('RUN_LIVE_DRIVE'),
  );
}
