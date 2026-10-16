import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import '../support/nara_csv_fixture.dart';
import '../support/nara_full_csv_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppController c;
  setUp(() async {
    final auth = GoogleAuth();
    c = AppController(
      Repository(await databaseFactoryMemory.openDatabase(newId.v4())),
      auth,
      GoogleDrive(auth),
    );
    await c.createLocal('QA', 'Robin');
    await c.repository.applyImport(
      HistoryImport.preview(naraCsvFixture, c.family!, []),
    );
    await c.refresh();
  });
  tearDown(() async {
    c.dispose();
    await c.repository.db.close();
  });
  test(
    'editing newly supported growth, solids and health keeps component identity and source fields',
    () async {
      await c.createLocal('Schema test', 'Schema Baby');
      await c.repository.applyImport(
        HistoryImport.preview(
          naraFullCsvFixture,
          c.family!,
          [],
          includeUnassignedPumps: true,
        ),
      );
      await c.refresh();
      final imported = await c.repository.feeds(c.family!.id);
      for (final method in ['growth', 'solids', 'health']) {
        final original = imported.firstWhere((r) => r.method == method);
        await c.addActivity(
          method: method,
          at: DateTime.utc(2026, 1, 1),
          details: original.details,
          note: 'Edited synthetic note',
          original: original,
        );
        final edited = (await c.repository.feeds(c.family!.id)).singleWhere(
          (r) => r.method == method && r.note == 'Edited synthetic note',
        );
        expect(edited.source, original.source);
        expect(edited.source['component'], isNotNull);
      }
      final repeat = HistoryImport.preview(
        naraFullCsvFixture,
        c.family!,
        await c.repository.feeds(c.family!.id, includeDeleted: true),
        includeUnassignedPumps: true,
      );
      expect(repeat.additions, isEmpty);
      expect(repeat.duplicates, 33);
      await expectLater(
        c.repository.undoImport(c.family!.id),
        throwsStateError,
      );
    },
  );

  test('editing an imported baby profile preserves its Nara origin', () async {
    final original = c.profileRecord!;
    await c.saveBabyProfile({
      ...original.details,
      'birthDate': '2026-01-02',
    }, c.family!.id);
    expect(c.profileRecord!.source, original.source);
  });
  test(
    'resumed imported nursing retains origin and note through pause restart and finish',
    () async {
      final original = c.feeds.firstWhere((r) => r.method == 'nursing');
      final withNote = Feeding.fromJson({
        ...original.toJson(),
        'note': 'Original note',
      });
      await c.repository.add(withNote);
      await c.reopenNursing(withNote, 'left');
      await c.nursingAction('pause');
      final stored = await c.repository.nursingSession(c.family!.id);
      final reopened = NursingSession.fromJson(stored!.toJson());
      final finished = reopened
          .resume(DateTime.now())
          .finish(DateTime.now(), 'QA');
      expect(finished.source, original.source);
      expect(finished.note, 'Original note');
      await c.repository.finishSession(reopened, finished);
      expect(
        (await c.repository.feeds(
          c.family!.id,
        )).singleWhere((r) => r.method == 'nursing').source,
        original.source,
      );
    },
  );
}
