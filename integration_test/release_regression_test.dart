import '../test/care_entry_test.dart' as care_entries;
import '../test/today_page_test.dart' as today;
import '../test/history_summary_layout_test.dart' as history_summary;
import '../test/volume_test.dart' as volume;
import '../test/selection_chip_test.dart' as chips;
import '../test/toggle_pill_test.dart' as pills;
import '../test/entry_labels_test.dart' as headings;
import '../test/long_timer_edit_test.dart' as nursing_sides;
import '../test/nursing_controls_test.dart' as nursing_controls;
import 'app_journey_test.dart' as journey;
import 'recovery_test.dart' as recovery;
import 'timer_edit_test.dart' as timers;
import 'format_upgrade_test.dart' as format;
import '../test/quick_log_test.dart' as quick_log;
import '../test/baby_picker_test.dart' as babies;
import '../test/tip_jar_test.dart' as tips;
import 'portable_widget_harness.dart';

// Synthetic fixtures only. Run the complete release journey on a native engine.
void main() {
  journey.main();
  recovery.main();
  portableWidgetChecks(() {
    timers.main();
    format.main();
    quick_log.main();
    babies.main();
    tips.main();
    care_entries.main();
    today.main();
    history_summary.main();
    volume.main();
    chips.main();
    pills.main();
    headings.main();
    nursing_sides.main();
    nursing_controls.main();
  });
}
