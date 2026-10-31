// Synthetic CSV and fresh temporary databases only; no app or Drive storage.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import '../test/support/nara_medical_csv_fixture.dart';

const _baby = Family(
  id: 'medical-recovery',
  name: 'Synthetic',
  babyName: 'Schema Baby',
);
const _other = Family(
  id: 'unrelated-baby',
  name: 'Synthetic',
  babyName: 'Other',
);
const _batches = 200;
const _supported = 50 * _batches;
const _note = 'Synthetic medical note\nSecond line, "quoted" 👶';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> _reject(Future<void> Function() action, String reason) async {
  try {
    await action();
  } on StateError catch (error) {
    _check(error.message.contains(reason), 'Unexpected rejection: $error');
    return;
  }
  throw StateError('Expected rejection: $reason');
}

// Interrupt after every record, report and undo receipt has been written to the
// transaction, but before commit. Reopening must expose none of those writes.
class _InterruptedCommit implements Database {
  _InterruptedCommit(this.inner);
  final Database inner;

  @override
  Future<T> transaction<T>(FutureOr<T> Function(Transaction) action) =>
      inner.transaction((txn) async {
        await action(txn);
        throw StateError('Synthetic interruption before commit');
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

String _csv({bool corrected = false}) {
  final rows = FamilyCsv.parseRows(
    naraMedicalCsvFixture(
      medicalRow: 51,
      note: _note,
      medical: corrected
          ? {
              'Medication': 'Synthetic syrup, 1 (ML)',
              'Temperature': '37.2',
              'Temperature Unit': 'C',
            }
          : const {},
    ),
  );
  final id = rows.first.indexOf('_activityKey');
  return [
        rows.first,
        for (var batch = 0; batch < _batches; batch++)
          for (final row in rows.skip(1))
            [...row]..[id] = '${row[id]}-batch-$batch',
      ]
      .map((row) => row.map((s) => '"${s.replaceAll('"', '""')}"').join(','))
      .join('\r\n');
}

Future<Map<String, Object>> runMedicalRecoveryProbe() async {
  final stopwatch = Stopwatch()..start();
  final directory = await Directory.systemTemp.createTemp('medical-recovery-');
  final path = '${directory.path}/history.db';
  Database? opened;
  try {
    opened = await databaseFactoryIo.openDatabase(path);
    var repo = Repository(opened);
    Future<void> reopen() async {
      await opened!.close();
      opened = null;
      opened = await databaseFactoryIo.openDatabase(path);
      repo = Repository(opened!);
    }

    final manual = Feeding(
      id: 'manual',
      familyId: _baby.id,
      at: DateTime.utc(2026),
      method: 'bottle',
      amountMl: 42,
      note: 'Preserve manual record',
    );
    final unrelated = Feeding(
      id: 'unrelated',
      familyId: _other.id,
      at: DateTime.utc(2026),
      method: 'bottle',
      amountMl: 60,
    );
    final session = NursingSession(
      id: 'paused-session',
      familyId: _other.id,
      startedAt: DateTime.utc(2026),
      segmentAt: DateTime.utc(2026),
      side: 'left',
      leftSeconds: 30,
      paused: true,
      note: 'Preserve timer',
    );
    await repo.saveFamily(_baby);
    await repo.saveFamily(_other);
    await repo.add(manual);
    await repo.add(unrelated);
    await repo.saveSession(session);
    await repo.saveQuickLog(['sleep', 'diaper']);
    final untouchedSession = jsonEncode(session.toJson());

    Future<void> checkUnrelated() async {
      _check(
        snapshotFingerprint(await repo.feeds(_other.id)) ==
            snapshotFingerprint([unrelated]),
        'Unrelated baby changed',
      );
      _check(
        jsonEncode((await repo.nursingSession(_other.id))!.toJson()) ==
            untouchedSession,
        'Unrelated timer changed',
      );
      _check(
        jsonEncode(await repo.quickLog()) == '["sleep","diaper"]',
        'Quick Log settings changed',
      );
    }

    Future<void> checkUncommitted(List<Feeding> before) async {
      _check(
        snapshotFingerprint(await repo.feeds(_baby.id)) ==
            snapshotFingerprint(before),
        'Uncommitted import changed history',
      );
      _check(
        (await repo.importReports(_baby.id)).isEmpty,
        'Uncommitted report survived',
      );
      _check(
        !await repo.canUndoImport(_baby.id),
        'Uncommitted undo receipt survived',
      );
      await checkUnrelated();
    }

    final csv = _csv();
    final blocked = HistoryImport.preview(csv, _baby, [manual]);
    _check(
      blocked.activityCount == _supported &&
          blocked.issues.length == _batches &&
          blocked.needsConsent,
      'Medical exclusions or supported records lost',
    );
    _check(
      blocked.issues.first.row == 51 &&
          blocked.issues.last.row == 51 + 51 * (_batches - 1),
      'Multiline notes changed logical issue rows',
    );
    await _reject(() => repo.applyImport(blocked), 'Review the excluded');
    await checkUncommitted([manual]);
    final consented = HistoryImport.preview(csv, _baby, [
      manual,
    ], allowPartial: true);
    await _reject(
      () => Repository(_InterruptedCommit(opened!)).applyImport(consented),
      'Synthetic interruption',
    );
    await reopen();
    await checkUncommitted([manual]);

    final concurrent = Feeding.fromJson({
      ...manual.toJson(),
      'id': 'concurrent',
    });
    await repo.add(concurrent);
    await _reject(() => repo.applyImport(consented), 'History changed');
    await reopen();
    await checkUncommitted([manual, concurrent]);
    final plan = HistoryImport.preview(
      csv,
      _baby,
      await repo.feeds(_baby.id, includeDeleted: true),
      allowPartial: true,
    );
    await repo.applyImport(plan);
    final imported = await repo.feeds(_baby.id);
    _check(imported.length == _supported + 2, 'Partial import committed');
    await reopen();
    _check(
      snapshotFingerprint(await repo.feeds(_baby.id)) ==
          snapshotFingerprint(imported),
      'Committed import lost after reopen',
    );
    final report = (await repo.importReports(_baby.id)).single;
    _check(
      report['added'] == _supported &&
          jsonEncode(report['issues']) ==
              jsonEncode(plan.issues.map((i) => i.toJson()).toList()),
      'Exclusion report disagrees with committed records',
    );
    await repo.applyImport(
      HistoryImport.preview(csv, _baby, imported, allowPartial: true),
    );
    _check(
      (await repo.importReports(_baby.id)).length == 1 &&
          await repo.canUndoImport(_baby.id),
      'Duplicate replaced undo receipt',
    );

    final correctedCsv = _csv(corrected: true);
    final correction = HistoryImport.preview(correctedCsv, _baby, imported);
    _check(
      correction.issues.isEmpty &&
          correction.duplicates == _supported &&
          correction.additions.length == 2 * _batches,
      'Corrected medical components duplicated surrounding records',
    );
    _check(
      correction.additions.every(
        (r) =>
            r.note == _note &&
            r.source['original'] is Map &&
            (r.source['original'] as Map)['Note'] == _note,
      ),
      'Corrected medical notes or provenance lost',
    );
    await repo.applyImport(correction);
    await reopen();
    final corrected = await repo.feeds(_baby.id);
    _check(
      corrected.length == _supported + 2 * _batches + 2 &&
          corrected.map((r) => r.id).toSet().length == corrected.length,
      'Corrected import lost records or component identities',
    );
    await repo.applyImport(
      HistoryImport.preview(correctedCsv, _baby, corrected),
    );
    _check(
      (await repo.importReports(_baby.id)).length == 2,
      'Corrected duplicate wrote another report',
    );

    final medical = correction.additions.first;
    await repo.add(
      Feeding.fromJson({...medical.toJson(), 'note': 'Edited after import'}),
    );
    final edited = snapshotFingerprint(
      await repo.feeds(_baby.id, includeDeleted: true),
    );
    await _reject(() => repo.undoImport(_baby.id), 'has since changed');
    await reopen();
    _check(
      snapshotFingerprint(await repo.feeds(_baby.id, includeDeleted: true)) ==
              edited &&
          await repo.canUndoImport(_baby.id),
      'Rejected undo changed records or receipt',
    );
    _check(
      (await repo.importReports(_baby.id)).every((r) => r['undone'] != true),
      'Rejected undo marked a report undone',
    );
    await repo.add(medical);
    await repo.undoImport(_baby.id);
    await reopen();
    _check(
      snapshotFingerprint(await repo.feeds(_baby.id)) ==
          snapshotFingerprint(imported),
      'Undo changed the prior import or manual rows',
    );
    _check(
      !await repo.canUndoImport(_baby.id) &&
          (await repo.importReports(
                _baby.id,
              )).where((r) => r['undone'] == true).length ==
              1,
      'Undo report or receipt incorrect after reopen',
    );
    final retry = HistoryImport.preview(
      correctedCsv,
      _baby,
      await repo.feeds(_baby.id, includeDeleted: true),
    );
    _check(
      retry.additions.isEmpty && retry.duplicates == _supported + 2 * _batches,
      'Retry resurrected deleted medical components',
    );
    await checkUnrelated();
    return {
      'passed': true,
      'supported_activities': _supported,
      'medical_exclusions': _batches,
      'corrected_components': 2 * _batches,
      'csv_bytes': utf8.encode(csv).length,
      'total_ms': stopwatch.elapsedMilliseconds,
    };
  } finally {
    await opened?.close();
    await directory.delete(recursive: true);
  }
}

Future<void> main() async {
  stdout.writeln(jsonEncode(await runMedicalRecoveryProbe()));
}
