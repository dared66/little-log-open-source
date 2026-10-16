import 'package:flutter/foundation.dart';
import 'package:integration_test/integration_test.dart';
import 'portable_widget_harness.dart';
import '../test/siri_actions_test.dart' as actions;
import '../test/assistant_history_test.dart' as history;
import '../test/android_voice_actions_test.dart' as android_voice;
import '../test/assistant_help_test.dart' as help;
import '../test/elapsed_icon_preference_test.dart' as elapsed;
import '../test/log_navigation_test.dart' as log;

// Safe to rerun after a local fix without repeating the large-history stress
// suite. All records and timers are synthetic and isolated from the app log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  actions.main();
  history.main();
  portableWidgetChecks(() {
    if (defaultTargetPlatform == TargetPlatform.android) android_voice.main();
    help.main();
    elapsed.main();
    log.main();
  });
}
