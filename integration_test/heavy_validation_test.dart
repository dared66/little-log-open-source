import '../test/released_build54_compatibility_test.dart'
    as released_compatibility;
import '../test/pumping_compatibility_test.dart' as pumping_compatibility;
import '../test/nursing_compatibility_test.dart' as nursing_compatibility;
import '../test/write_integrity_test.dart' as write_integrity;
import '../test/recovery_boundary_test.dart' as repair;
import '../test/backup_flow_test.dart' as backup;
import 'full_harness_test.dart' as full;
import 'import_harness_test.dart' as imports;
import 'feature_validation_test.dart' as features;
import 'calendar_numeral_fit_test.dart' as calendar;
import 'portable_widget_harness.dart';
import '../test/header_alignment_test.dart' as header;
import '../test/log_navigation_test.dart' as log;
import '../test/ux_accessibility_test.dart' as accessibility;
import '../test/activity_polish_test.dart' as activity;
import '../test/swipe_reminder_test.dart' as reminders;

// Full synthetic coverage; no live-account probe or production storage.
// Run with scripts/run_native_tests.py for automatic Android profiler routing.
void main() {
  full.main();
  released_compatibility.main();
  pumping_compatibility.main();
  nursing_compatibility.main();
  write_integrity.main();
  repair.main();
  backup.runBackupFlow(native: true);
  imports.main();
  features.main();
  calendar.main();
  portableWidgetChecks(() {
    log.main();
    accessibility.main();
    activity.main();
    header.main();
    reminders.main();
  });
}
