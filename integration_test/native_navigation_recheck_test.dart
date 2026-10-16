import 'app_journey_test.dart' as journey;
import 'portable_widget_harness.dart';
import '../test/header_alignment_test.dart' as header;
import '../test/quick_log_test.dart' as shortcuts;
import '../test/log_navigation_test.dart' as log;
import '../test/activity_polish_test.dart' as activity;
import '../test/ux_accessibility_test.dart' as accessibility;

void main() {
  journey.main();
  portableWidgetChecks(() {
    shortcuts.main();
    log.main();
    activity.main();
    header.main();
    accessibility.main();
  });
}
