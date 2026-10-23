import 'package:integration_test/integration_test.dart';
import '../test/backup_flow_test.dart' as backup;
import '../test/invitation_harness_test.dart' as invitations;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  backup.runBackupFlow(native: true);
  if (!const bool.fromEnvironment('BACKUP_ONLY')) {
    invitations.runInvitationHarness(native: true);
  }
}
