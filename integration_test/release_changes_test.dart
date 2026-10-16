import 'package:integration_test/integration_test.dart';

import 'onboarding_smoke_test.dart' as onboarding;
import '../test/edit_log_test.dart' as editing;
import '../test/history_summary_layout_test.dart' as history;

// Native checks for the user-facing changes since the previous Family beta.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  onboarding.main();
  editing.main();
  history.main();
}
