import 'package:integration_test/integration_test.dart';
import '../test/entry_time_test.dart' as time_picker;
import 'session_stress_test.dart' as sessions;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  time_picker.main();
  sessions.main();
}
