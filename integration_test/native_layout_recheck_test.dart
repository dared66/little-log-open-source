import 'package:integration_test/integration_test.dart';
import 'portable_widget_harness.dart';
import '../test/header_alignment_test.dart' as header;
import '../test/log_navigation_test.dart' as log;
import '../test/activity_polish_test.dart' as activity;
import '../test/ux_accessibility_test.dart' as accessibility;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  portableWidgetChecks(() {
    log.main();
    activity.main();
    header.main();
    accessibility.main();
  });
}
