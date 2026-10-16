import '../test/released_build54_compatibility_test.dart'
    as released_compatibility;
import '../test/paused_timer_state_test.dart' as paused_timers;
import '../test/pumping_compatibility_test.dart' as pumping_compatibility;
import '../test/live_timer_finish_test.dart' as live_timers;
import '../test/edit_delete_action_test.dart' as edit_delete;
import 'heavy_validation_test.dart' as heavy;
import 'assistant_features_test.dart' as features;
import 'portable_widget_harness.dart';
import '../test/appearance_quick_actions_test.dart' as appearance;
import '../test/emulator_review_layout_test.dart' as layout;

// Synthetic data only. Combines existing native stress/recovery/navigation
// coverage with the optional icons, read-only voice questions and Settings Help.
void main() {
  released_compatibility.main();
  pumping_compatibility.main();
  heavy.main();
  features.main();
  portableWidgetChecks(() {
    paused_timers.main();
    live_timers.main();
    edit_delete.main();
    appearance.main();
    layout.main();
  });
}
