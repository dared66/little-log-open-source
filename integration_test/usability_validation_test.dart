import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';
import '../test/appearance_quick_actions_test.dart' as appearance;
import '../test/android_voice_actions_test.dart' as android_voice;
import '../test/emulator_review_layout_test.dart' as layout;
import '../test/siri_actions_test.dart' as assistant;
import 'portable_widget_harness.dart';
import 'performance_test.dart' as performance;

// Synthetic controllers and isolated memory stores; no live account or logs.
// Run with scripts/run_native_tests.py for automatic Android profiler routing.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) performance.main();
  assistant.main();
  portableWidgetChecks(() {
    appearance.main();
    layout.main();
    if (defaultTargetPlatform == TargetPlatform.android) android_voice.main();
  });
}
