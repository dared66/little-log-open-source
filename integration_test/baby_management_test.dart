import 'package:integration_test/integration_test.dart';
import '../test/add_baby_storage_test.dart' as storage;
import '../test/baby_picker_test.dart' as management;
import 'portable_widget_harness.dart';

// Isolated synthetic histories and injected Drive responses; no live accounts.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  portableWidgetChecks(storage.main);
  portableWidgetChecks(management.main);
}
