// SIGKILL probes use newly created synthetic databases only.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import '../test/support/nara_csv_fixture.dart';

const family = Family(id: 'crash-test', name: 'Synthetic', babyName: 'Robin');

class BeforeCommitDatabase implements Database {
  BeforeCommitDatabase(this.inner);
  final Database inner;
  @override
  Future<T> transaction<T>(FutureOr<T> Function(Transaction) action) =>
      inner.transaction((txn) async {
        await action(txn);
        stdout.writeln('BEFORE_COMMIT');
        await stdout.flush();
        return Completer<T>().future;
      });
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> worker(String mode, String path) async {
  final db = await databaseFactoryIo.openDatabase(path);
  final repo = Repository(db);
  final before = await repo.feeds(family.id, includeDeleted: true);
  final fixture = HistoryImport.preview(naraCsvFixture, family, []).additions;
  final additions = [
    for (var i = 0; i < 300; i++)
      for (final r in fixture)
        Feeding.fromJson({...r.toJson(), 'id': '${r.id}-$i'}),
  ];
  final plan = ImportPlan(
    familyId: family.id,
    before: before,
    additions: additions,
    removals: [],
    duplicates: 0,
    label: 'Crash test',
  );
  stdout.writeln('SAVING');
  await stdout.flush();
  await Repository(
    mode == 'before' ? BeforeCommitDatabase(db) : db,
  ).applyImport(plan);
  stdout.writeln('COMMITTED');
  await stdout.flush();
  await Completer<void>().future;
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> args) async {
  if (args.length == 2) {
    await worker(args[0], args[1]);
    return;
  }
  final dir = await Directory.systemTemp.createTemp('little-log-crash-qa-');
  try {
    for (final scenario in [
      'before',
      'during-0',
      'during-1',
      'during-5',
      'during-20',
      'after',
    ]) {
      final path = '${dir.path}/$scenario.db';
      var db = await databaseFactoryIo.openDatabase(path);
      await Repository(db).saveFamily(family);
      await Repository(db).add(
        Feeding(
          id: 'manual',
          familyId: family.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 55,
        ),
      );
      await db.close();
      final process = await Process.start(Platform.resolvedExecutable, [
        'run',
        Platform.script.toFilePath(),
        scenario == 'before' ? 'before' : 'normal',
        path,
      ]);
      final errors = process.stderr.transform(utf8.decoder).join();
      final marker = scenario == 'before'
          ? 'BEFORE_COMMIT'
          : scenario == 'after'
          ? 'COMMITTED'
          : 'SAVING';
      try {
        await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line == marker)
            .timeout(const Duration(seconds: 45));
        if (scenario.startsWith('during-')) {
          await Future<void>.delayed(
            Duration(milliseconds: int.parse(scenario.split('-').last)),
          );
        }
      } catch (_) {
        process.kill(ProcessSignal.sigkill);
        rethrow;
      }
      require(
        process.kill(ProcessSignal.sigkill),
        'Worker could not be terminated',
      );
      await process.exitCode;
      final error = await errors;
      require(
        error.replaceAll('Running build hooks...', '').trim().isEmpty,
        'Worker error: $error',
      );
      db = await databaseFactoryIo.openDatabase(path);
      final repo = Repository(db);
      final rows = await repo.feeds(family.id);
      final reports = await repo.importReports(family.id);
      final undo = await repo.canUndoImport(family.id);
      require(
        rows.length == 1 || rows.length == 1501,
        'Partial records after $scenario: ${rows.length}',
      );
      final committed = rows.length == 1501;
      require(
        reports.length == (committed ? 1 : 0) && undo == committed,
        'Records/receipt/report disagree after $scenario',
      );
      require(
        rows.singleWhere((r) => r.id == 'manual').amountMl == 55,
        'Manual entry changed',
      );
      if (scenario == 'before') {
        require(!committed, 'Uncommitted transaction survived');
      }
      if (scenario == 'after') require(committed, 'Committed transaction lost');
      if (committed) {
        await repo.undoImport(family.id);
        require(
          (await repo.feeds(family.id)).single.id == 'manual',
          'Undo failed',
        );
      }
      await db.close();
      stdout.writeln(
        'PASS $scenario: ${committed ? "complete import and undo" : "unchanged history"}',
      );
    }
  } finally {
    await dir.delete(recursive: true);
  }
}
