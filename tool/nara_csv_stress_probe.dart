// Derived synthetic Nara CSV only. All databases are newly created temporary
// files; this probe never opens a real log or calls a cloud service.
import 'dart:convert';
import 'dart:io';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import '../test/support/nara_full_csv_fixture.dart';

const family = Family(
  id: 'nara-stress-qa',
  name: 'Synthetic',
  babyName: 'Schema Baby',
);
const batches = 200;

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

String encodeRows(List<List<String>> rows) => rows
    .map((row) => row.map((s) => '"${s.replaceAll('"', '""')}"').join(','))
    .join('\r\n');

String stressCsv() {
  final rows = FamilyCsv.parseRows(naraFullCsvFixture);
  final idIndex = rows.first.indexOf('_activityKey');
  final profile = rows.skip(1).singleWhere((r) => r.first == 'Profile');
  return encodeRows([
    rows.first,
    for (var batch = 0; batch < batches; batch++)
      for (final source in rows.skip(1).where((r) => r.first != 'Profile'))
        [...source]..[idIndex] = '${source[idIndex]}-batch-$batch',
    profile,
  ]);
}

Future<void> main() async {
  final text = stressCsv();
  final timer = Stopwatch()..start();
  final plan = HistoryImport.preview(
    text,
    family,
    [],
    includeUnassignedPumps: true,
  );
  final previewMs = timer.elapsedMilliseconds;
  check(
    plan.activityCount == 32 * batches &&
        plan.additions.length == 32 * batches + 1,
    'Split activity count mismatch',
  );
  check(plan.issues.isEmpty, 'Unexpected exclusion');
  check(
    plan.additions.map((r) => r.id).toSet().length == plan.additions.length,
    'Component ID collision',
  );
  check(
    plan.additions
            .where((r) => r.method != 'profile')
            .map((r) => r.source['recordId'])
            .toSet()
            .length ==
        23 * batches,
    'Missing source entry',
  );
  final dir = await Directory.systemTemp.createTemp('little-log-nara-stress-');
  Database? db;
  try {
    final path = '${dir.path}/history.db';
    db = await databaseFactoryIo.openDatabase(path);
    var repo = Repository(db);
    await repo.saveFamily(family);
    final manual = Feeding(
      id: 'manual',
      familyId: family.id,
      at: DateTime.utc(2026),
      method: 'bottle',
      amountMl: 35,
      note: 'Keep this synthetic manual record',
    );
    await repo.add(manual);
    final withManual = HistoryImport.preview(text, family, [
      manual,
    ], includeUnassignedPumps: true);
    await repo.applyImport(withManual);
    var saved = await repo.feeds(family.id);
    final fingerprint = snapshotFingerprint(saved);
    check(saved.length == plan.additions.length + 1, 'Partial save');
    final repeat = HistoryImport.preview(
      text,
      family,
      saved,
      includeUnassignedPumps: true,
    );
    check(
      repeat.additions.isEmpty && repeat.duplicates == plan.additions.length,
      'Reimport duplicated split components',
    );
    final csvBackup = FamilyCsv(family, saved).encode();
    final csvRoundTrip = HistoryImport.preview(csvBackup, family, []).additions;
    final jsonRoundTrip = HistoryImport.preview(
      await repo.export(family),
      family,
      [],
    ).additions;
    check(
      snapshotFingerprint(csvRoundTrip) == fingerprint,
      'CSV backup lost data',
    );
    check(
      snapshotFingerprint(jsonRoundTrip) == fingerprint,
      'JSON backup lost data',
    );
    await db.close();
    db = null;
    db = await databaseFactoryIo.openDatabase(path);
    repo = Repository(db);
    saved = await repo.feeds(family.id);
    check(snapshotFingerprint(saved) == fingerprint, 'Disk reopen lost data');
    final malformed = FamilyCsv.parseRows(text);
    malformed[malformed.length - 2][malformed.first.indexOf(
          '[Growth] Head Size',
        )] =
        '-1';
    var rejected = false;
    try {
      HistoryImport.preview(
        encodeRows(malformed),
        family,
        saved,
        includeUnassignedPumps: true,
      );
    } on FormatException {
      rejected = true;
    }
    check(rejected, 'Malformed final source row was accepted');
    check(
      snapshotFingerprint(await repo.feeds(family.id)) == fingerprint,
      'Malformed preview changed saved data',
    );
    check(
      (await repo.importReports(family.id)).length == 1,
      'Unexpected report mutation',
    );
    await repo.undoImport(family.id);
    check(
      (await repo.feeds(family.id)).single.id == manual.id,
      'Undo damaged manual history',
    );
    final deleted = HistoryImport.preview(
      text,
      family,
      await repo.feeds(family.id, includeDeleted: true),
      includeUnassignedPumps: true,
    );
    check(
      deleted.additions.isEmpty && deleted.duplicates == plan.additions.length,
      'Undo/reimport revived a deleted component',
    );
    stdout.writeln(
      jsonEncode({
        'passed': true,
        'derived_source_activities': 23 * batches,
        'destination_activities': plan.activityCount,
        'profile_records': 1,
        'csv_input_bytes': utf8.encode(text).length,
        'csv_backup_bytes': utf8.encode(csvBackup).length,
        'preview_ms': previewMs,
        'total_ms': timer.elapsedMilliseconds,
        'checks': [
          'complete coverage',
          'component ID uniqueness',
          'reimport',
          'CSV/JSON backups',
          'disk reopen',
          'malformed final row rejection',
          'atomic reports',
          'undo preserves manual record',
          'deleted component deduplication',
        ],
      }),
    );
  } finally {
    await db?.close();
    await dir.delete(recursive: true);
  }
}
