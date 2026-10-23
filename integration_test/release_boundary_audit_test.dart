import 'package:integration_test/integration_test.dart';
import '../test/drive_account_boundary_test.dart' as accounts;
import '../test/release_boundary_regression_test.dart' as boundaries;
import '../test/native_handoff_regression_test.dart' as handoffs;
import '../test/inactive_timer_sync_test.dart' as timers;
import 'portable_widget_harness.dart';

// Synthetic timing/failure injection on disposable devices. This does not
// replace opt-in verification against actual signed-in Google accounts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  accounts.main();
  boundaries.main();
  timers.main();
  portableWidgetChecks(handoffs.main);
}
