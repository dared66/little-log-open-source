import 'package:integration_test/integration_test.dart';
import '../test/import/file_import_test.dart' as files;
import '../test/import_confirmation_test.dart' as confirmations;
import '../test/history_import_test.dart' as history;
import 'portable_widget_harness.dart';
import '../test/import/import_sync_test.dart' as sync;
import '../test/import/import_edit_provenance_test.dart' as provenance;
import '../test/import/nara_csv_test.dart' as csv;
import '../test/import/nara_full_csv_test.dart' as full_csv;
import '../test/import/import_storage_test.dart' as storage;
import '../test/import/nara_medical_recovery_test.dart' as medical_recovery;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  history.main();
  csv.main();
  full_csv.main();
  storage.main();
  medical_recovery.main();
  sync.main();
  provenance.main();
  portableWidgetChecks(files.main);
  portableWidgetChecks(confirmations.main);
}
