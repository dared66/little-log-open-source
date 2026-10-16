import '../test/care_entry_test.dart' as entries;
import '../test/volume_test.dart' as volume;
import '../test/toggle_pill_test.dart' as pills;
import '../test/nursing_controls_test.dart' as nursing;
import 'package:integration_test/integration_test.dart';

// Exercise persisted settings, exact unit conversion and boolean forms on-device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  entries.main();
  volume.main();
  pills.main();
  nursing.main();
}
