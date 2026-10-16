import 'package:integration_test/integration_test.dart';
import 'performance_test.dart' as performance;
import '../test/baby_picker_test.dart' as babies;
import '../test/quick_log_test.dart' as quick_log;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  babies.main();
  quick_log.main();
  performance.main();
}
