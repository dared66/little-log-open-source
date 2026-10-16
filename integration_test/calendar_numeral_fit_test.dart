import 'package:integration_test/integration_test.dart';
import '../test/calendar_numeral_fit_test.dart' as fit;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  fit.calendarFitTests(native: true);
}
