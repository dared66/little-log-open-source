import 'package:integration_test/integration_test.dart';
import '../test/quick_log_test.dart' as quick_log;
import 'portable_widget_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  portableWidgetChecks(quick_log.main);
}
