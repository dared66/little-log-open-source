import 'package:integration_test/integration_test.dart';
import '../test/invitation_harness_test.dart' as harness;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  harness.runInvitationHarness(native: true);
}
