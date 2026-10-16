// Run only on emulators: this named QA database never opens the app's real log.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/volume.dart';
import '../test/support/nara_export_fixture.dart';
import '../test/support/nara_csv_fixture.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final path = '${support.path}/qa-import-upgrade-v1.db';
  final db = await databaseFactoryIo.openDatabase(path);
  final repo = Repository(db);
  const family = Family(id: 'upgrade-qa', name: 'Synthetic', babyName: 'Robin');
  const seed = bool.fromEnvironment('QA_UPGRADE_SEED');
  var result = <String, Object?>{'seed': seed, 'passed': false};
  try {
    if (seed) {
      check((await repo.families()).isEmpty, 'QA seed already exists');
      await repo.saveFamily(family);
      await repo.saveVolumeUnit(VolumeUnit.oz);
      await repo.saveWeightUnit('lb');
      await repo.saveLengthUnit('in');
      await repo.saveTemperatureUnit('°F');
      await repo.saveQuickLog(['sleep', 'diaper']);
      await repo.add(
        Feeding(
          id: 'manual',
          familyId: family.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 42,
          note: 'Keep this manual record',
        ),
      );
      await repo.applyImport(
        HistoryImport.preview(
          naraExportFixture(),
          family,
          await repo.feeds(family.id),
        ),
      );
      await repo.saveSession(
        NursingSession(
          id: 'running',
          familyId: family.id,
          startedAt: DateTime.utc(2026),
          segmentAt: DateTime.utc(2026),
          side: 'left',
          leftSeconds: 30,
          paused: true,
          note: 'Keep paused timer',
        ),
      );
    } else {
      check((await repo.families()).single.id == family.id, 'Family lost');
      check(
        await repo.volumeUnit() == VolumeUnit.oz &&
            await repo.weightUnit() == 'lb' &&
            await repo.lengthUnit() == 'in' &&
            await repo.temperatureUnit() == '°F',
        'Units lost',
      );
      check(
        jsonEncode(await repo.quickLog()) == jsonEncode(['sleep', 'diaper']),
        'Quick log lost',
      );
      check(
        (await repo.nursingSession(family.id))!.note == 'Keep paused timer',
        'Timer lost',
      );
      check((await repo.feeds(family.id)).length == 5, 'Old records lost');
      check(
        await repo.canUndoImport(family.id),
        'Legacy recovery receipt lost',
      );
      await repo.undoImport(family.id);
      check(
        (await repo.feeds(family.id)).single.note == 'Keep this manual record',
        'Legacy undo damaged manual history',
      );
      await repo.applyImport(
        HistoryImport.preview(
          naraCsvFixture,
          family,
          await repo.feeds(family.id, includeDeleted: true),
        ),
      );
      check(
        (await repo.feeds(family.id)).length == 6,
        'New CSV failed after upgrade',
      );
      await repo.undoImport(family.id);
      check(
        (await repo.feeds(family.id)).single.id == 'manual',
        'New undo failed',
      );
    }
    result = {
      ...result,
      'passed': true,
      'records': (await repo.feeds(family.id)).length,
    };
  } catch (e, st) {
    result = {...result, 'error': e.toString(), 'stack': st.toString()};
  }
  await db.close();
  final encoded = jsonEncode(result);
  await File(
    '${support.path}/qa-import-upgrade-result.json',
  ).writeAsString(encoded, flush: true);
  if (Platform.isAndroid) {
    final external = await getExternalStorageDirectory();
    if (external != null) {
      await File(
        '${external.path}/qa-import-upgrade-result.json',
      ).writeAsString(encoded, flush: true);
    }
  }
  // ignore: avoid_print
  print('QA_UPGRADE $encoded');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(
            result['passed'] == true
                ? 'Upgrade QA passed'
                : 'Upgrade QA failed',
          ),
        ),
      ),
    ),
  );
}
