import 'package:integration_test/integration_test.dart';
import '../test/long_timer_edit_test.dart' as timer_tests;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  timer_tests.main();
}
