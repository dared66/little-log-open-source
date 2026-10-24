import 'package:integration_test/integration_test.dart';
import '../test/backup_flow_test.dart' as backup;
import '../test/inactive_timer_sync_test.dart' as timers;
import '../test/manual_sync_test.dart' as refresh;

// Synthetic histories and injected Drive responses on isolated devices.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  backup.runBackupFlow(native: true);
  timers.main();
  refresh.main();
}
