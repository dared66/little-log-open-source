import 'release_regression_test.dart' as regressions;
import 'onboarding_smoke_test.dart' as onboarding;
import '../test/edit_log_test.dart' as editing;
import 'invitation_harness_test.dart' as invitations;
import 'performance_test.dart' as performance;
import '../test/discard_session_test.dart' as discard;
import '../test/extended_widget_test.dart' as forms;
import '../test/import_confirmation_test.dart' as import_confirmation;
import '../test/delete_scope_test.dart' as delete_scope;
import 'portable_widget_harness.dart';
import '../test/unit_polish_test.dart' as unit_polish;
import '../test/google_project_migration_test.dart' as google_migration;
import '../test/google_auth_lifecycle_test.dart' as google_auth;

// Complete synthetic native harness. Real-account probes remain opt-in.
void main() {
  regressions.main();
  portableWidgetChecks(unit_polish.main);
  onboarding.main();
  portableWidgetChecks(editing.main);
  portableWidgetChecks(invitations.main);
  performance.main();
  portableWidgetChecks(discard.main);
  portableWidgetChecks(forms.main);
  portableWidgetChecks(import_confirmation.main);
  portableWidgetChecks(delete_scope.main);
  google_migration.main();
  google_auth.main();
}
