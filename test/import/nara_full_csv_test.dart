import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/models.dart';
import 'package:little_log/record_validation.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import '../support/nara_full_csv_fixture.dart';
import 'import_sync_test.dart' show CsvCloud;

const baby = Family(id: 'full-csv', name: 'Synthetic', babyName: 'Schema Baby');
String rewrite(
  void Function(List<Map<String, String>>) edit, {
  String input = naraFullCsvFixture,
}) {
  final csv = FamilyCsv.parseRows(input);
  final rows = [
    for (final cells in csv.skip(1))
      {
        for (var i = 0; i < csv.first.length; i++)
          csv.first[i]: i < cells.length ? cells[i] : '',
      },
  ];
  edit(rows);
  final header = {...csv.first, ...rows.expand((r) => r.keys)}.toList();
  String line(Iterable<String> cells) =>
      cells.map((s) => '"${s.replaceAll('"', '""')}"').join(',');
  return [
    line(header),
    for (final row in rows) line(header.map((k) => row[k] ?? '')),
  ].join('\r\n');
}

List<Feeding> sample(ImportPlan plan, String marker) =>
    plan.additions.where((r) => r.note.startsWith('SCHEMA $marker')).toList();
ImportPlan preview(String text, [List<Feeding> existing = const []]) =>
    HistoryImport.preview(text, baby, existing, includeUnassignedPumps: true);

void main() {
  test('all 23 baby source entries map to 32 activities and one profile', () {
    final plan = preview(naraFullCsvFixture);
    expect(plan.issues, isEmpty);
    expect(plan.needsConsent, false);
    expect(plan.activityCount, 32);
    expect(plan.additions, hasLength(33));
    expect(plan.additions.map((r) => r.id).toSet(), hasLength(33));
    final counts = <String, int>{};
    for (final r in plan.additions) {
      validateRecord(r, baby.id);
      counts.update(r.method, (v) => v + 1, ifAbsent: () => 1);
    }
    expect(counts, {
      'nursing': 3,
      'bottle': 3,
      'diaper': 4,
      'pumping': 2,
      'sleep': 2,
      'solids': 2,
      'growth': 7,
      'health': 6,
      'routine': 1,
      'milestone': 2,
      'profile': 1,
    });
    expect(
      plan.additions
          .where((r) => r.method != 'profile')
          .map((r) => r.source['recordId'])
          .toSet(),
      hasLength(23),
    );
    expect(
      plan.additions
          .singleWhere((r) => r.method == 'profile')
          .source['original'],
      containsPair('[Profile] Birth Date (Adjusted)', '2026-10-13'),
    );
    final withoutPumps = HistoryImport.preview(naraFullCsvFixture, baby, []);
    expect(withoutPumps.activityCount, 30);
    expect(withoutPumps.unassignedPumps, 2);
    expect(withoutPumps.issues, hasLength(2));
    expect(withoutPumps.needsConsent, false);
    expect(withoutPumps.issues.every((i) => !i.requiresConsent), true);
  });

  test('every component retains the full source row, note and attribution', () {
    final csv = FamilyCsv.parseRows(naraFullCsvFixture);
    final original = <String, Map<String, String>>{};
    for (final cells in csv.skip(1)) {
      final row = {
        for (var i = 0; i < cells.length; i++) csv.first[i]: cells[i],
      };
      final id = row['_activityKey'];
      if (id != null && id.isNotEmpty) {
        original[id] = Map.fromEntries(
          row.entries.where((e) => e.value.isNotEmpty),
        );
      }
    }
    for (final record in preview(
      naraFullCsvFixture,
    ).additions.where((r) => r.method != 'profile')) {
      expect(record.source['original'], original[record.source['recordId']]);
      expect(record.source['timezone'], 'America/Los_Angeles');
      expect(record.author, 'Migration QA');
      expect(
        record.note,
        startsWith((record.source['original'] as Map)['Note'] as String),
      );
    }
  });

  test(
    'combo feeds retain side seconds and independently normalized bottle contents',
    () {
      final records = sample(preview(naraFullCsvFixture), 'combo-mixed-04');
      expect(records, hasLength(2));
      final nursing = records.singleWhere((r) => r.method == 'nursing');
      final bottle = records.singleWhere((r) => r.method == 'bottle');
      expect(nursing.leftSeconds, 360);
      expect(nursing.rightSeconds, 180);
      expect(nursing.endedAt, isNull);
      expect(nursing.source['component'], 'combo:nursing');
      expect(
        (nursing.source['original'] as Map)['[Combo Feed] End Side'],
        'RIGHT.nonTimer',
      );
      expect(bottle.amountMl, closeTo(60 + 1.5 * 29.5735295625, 1e-10));
      expect(bottle.details['formulaMl'], 60);
      expect(
        bottle.details['breastMilkMl'],
        closeTo(1.5 * 29.5735295625, 1e-10),
      );
      expect(bottle.details['formulaName'], 'Aptamil');
      expect(bottle.source['recordId'], nursing.source['recordId']);
    },
  );

  test(
    'growth splits only populated measurements with independent units and date precision',
    () {
      final plan = preview(naraFullCsvFixture);
      final metric = sample(plan, 'growth-metric-09');
      expect(metric.map((r) => r.details['measurement']).toSet(), {
        'Weight',
        'Length',
        'Head circumference',
      });
      expect(
        metric.singleWhere((r) => r.details['measurement'] == 'Weight').details,
        {'measurement': 'Weight', 'value': 6.4, 'unit': 'kg'},
      );
      final imperial = sample(plan, 'growth-imperial-33');
      expect(
        imperial
            .singleWhere((r) => r.details['measurement'] == 'Weight')
            .details['value'],
        12.21875,
      );
      expect(
        imperial
            .singleWhere((r) => r.details['measurement'] == 'Length')
            .details['unit'],
        'in',
      );
      expect(
        imperial
            .singleWhere(
              (r) => r.details['measurement'] == 'Head circumference',
            )
            .details['unit'],
        'cm',
      );
      final head = sample(plan, 'growth-head-only-inch-33b').single;
      expect(head.details, {
        'measurement': 'Head circumference',
        'value': 15.25,
        'unit': 'in',
      });
      expect(head.at, DateTime.utc(2026, 10, 13, 7));
      expect(head.source['dateOnly'], true);
    },
  );

  test(
    'medical entries split medicines and record temperature exactly once; vaccines split',
    () {
      final plan = preview(naraFullCsvFixture);
      final medical = sample(plan, 'medical-multi-dose-temp-11');
      expect(medical, hasLength(3));
      expect(
        medical.where((r) => r.details['kind'] == 'Temperature'),
        hasLength(1),
      );
      expect(
        medical.singleWhere((r) => r.details['kind'] == 'Temperature').details,
        {'kind': 'Temperature', 'value': 99.1, 'unit': '°F'},
      );
      expect(
        medical
            .singleWhere((r) => r.details['name'] == 'Amoxicillin')
            .details['dose'],
        '1.25 mL',
      );
      expect(
        medical
            .singleWhere((r) => r.details['name'] == 'Panadol')
            .details['dose'],
        '2.5 mg',
      );
      expect(medical.every((r) => !r.details.containsKey('temperature')), true);
      expect(sample(plan, 'medical-temperature-only-34').single.details, {
        'kind': 'Temperature',
        'value': 36.6,
        'unit': '°C',
      });
      expect(
        sample(plan, 'vaccines-multi-12').map((r) => r.details['name']).toSet(),
        {'DTaP', 'HepB'},
      );
    },
  );

  test(
    'solids keep food-specific allergy separate from preference and preserve extra attributes',
    () {
      final records = sample(
        preview(naraFullCsvFixture),
        'solids-multi-food-05',
      );
      expect(records, hasLength(2));
      final apple = records.singleWhere((r) => r.details['food'] == 'Apple');
      final banana = records.singleWhere((r) => r.details['food'] == 'Banana');
      expect(apple.details['reaction'], 'Reaction observed');
      expect(banana.details['reaction'], 'Not recorded');
      expect(apple.source['foodAttributes'], {
        'allergy': 'true',
        'amountKey': 'ALL',
        'preparationKeyz': 'PUREE',
        'reactionKey': 'LOVE',
        'note': 'Synthetic food note',
      });
      expect(banana.source['foodAttributes'], {
        'amountKey': 'SOME',
        'preparationKeyz': 'RAW',
        'reactionKey': 'LIKE',
      });
      expect(apple.source['meal'], 'BREAKFAST');
      expect(apple.note, contains('Synthetic food note'));
      final explicitNo = preview(
        rewrite((rows) {
          final r = rows.singleWhere((r) => r['Type'] == 'Solid Feed');
          r['[Solid Feed] Food'] = 'Pear: allergy=false; reactionKey=LOVE';
        }),
      );
      expect(
        explicitNo.additions
            .singleWhere((r) => r.method == 'solids')
            .details['reaction'],
        'No reaction observed',
      );
    },
  );

  test(
    'routine, baby first and curated milestone become existing editable activities',
    () {
      final plan = preview(naraFullCsvFixture);
      expect(sample(plan, 'routine-bath-07').single.details, {'name': 'Bath'});
      expect(sample(plan, 'baby-first-08').single.details, {
        'name': 'Schema first smile',
      });
      expect(sample(plan, 'milestone-curated-10').single.details, {
        'name': 'Looks at your face',
      });
      expect(sample(plan, 'baby-first-08').single.method, 'milestone');
    },
  );

  test(
    'open sleep is reported; its completed export imports later under the same source ID',
    () {
      final open = preview(naraOpenSleepCsvFixture);
      expect(open.issues, hasLength(1));
      expect(open.issues.single.type, 'Sleep');
      expect(open.issues.single.reason, contains('no end time'));
      expect(open.needsConsent, true);
      expect(sample(open, 'sleep-timer-18'), isEmpty);
      final finished = preview(naraFullCsvFixture);
      final sleep = sample(finished, 'sleep-timer-18').single;
      expect(sleep.source['recordId'], open.issues.single.recordId);
      expect(sleep.endedAt!.difference(sleep.at).inSeconds, 586);
      final noChangedProfile = open.additions
          .where((r) => r.method != 'profile')
          .toList();
      final later = preview(naraFullCsvFixture, noChangedProfile);
      expect(sample(later, 'sleep-timer-18'), hasLength(1));
    },
  );

  test(
    'repeated imports, header/row reorder and upgrade from original CSV coverage preserve IDs',
    () {
      final plan = preview(naraFullCsvFixture);
      expect(preview(naraFullCsvFixture, plan.additions).duplicates, 33);
      expect(preview(naraFullCsvFixture, plan.additions).additions, isEmpty);
      final rows = FamilyCsv.parseRows(naraFullCsvFixture);
      final reordered = [
        rows.first.reversed.toList(),
        ...rows
            .skip(1)
            .map(
              (r) => [
                ...r,
                if (r.length < rows.first.length) '',
              ].reversed.toList(),
            )
            .toList()
            .reversed,
      ];
      final text = reordered
          .map(
            (row) => row.map((s) => '"${s.replaceAll('"', '""')}"').join(','),
          )
          .join('\n');
      expect(preview(text, plan.additions).duplicates, 33);
      const originalTypes = {
        'Bottle Feed',
        'Breastfeed',
        'Pump',
        'Diaper',
        'Profile',
      };
      final old = plan.additions
          .where(
            (r) =>
                originalTypes.contains((r.source['original'] as Map)['Type']),
          )
          .toList();
      expect(old, hasLength(11));
      final upgrade = preview(naraFullCsvFixture, old);
      expect(upgrade.duplicates, 11);
      expect(upgrade.activityCount, 22);
    },
  );

  test(
    'component IDs are stable under list reordering; changed groups cannot append a replacement',
    () {
      final initial = preview(naraFullCsvFixture);
      final reordered = preview(
        rewrite((rows) {
          for (final r in rows) {
            for (final field in [
              '[Medical] Medication',
              '[Vaccine] Vaccine',
              '[Solid Feed] Food',
            ]) {
              if ((r[field] ?? '').isNotEmpty) {
                r[field] = r[field]!.split('\n').reversed.join('\n');
              }
            }
          }
        }),
      );
      expect(
        reordered.additions.map((r) => r.id).toSet(),
        initial.additions.map((r) => r.id).toSet(),
      );
      final replaced = rewrite(
        (rows) => rows
            .singleWhere(
              (r) => r['Note'] == 'SCHEMA medical-multi-dose-temp-11',
            )
            .addAll({
              '[Medical] Medication': 'New medicine, 5 (ML)',
              '[Medical] Temperature': '',
              '[Medical] Temperature Unit': '',
            }),
      );
      expect(() => preview(replaced, initial.additions), throwsFormatException);
    },
  );

  test(
    'missing medication dose is explicit; commas and semicolons in names/notes remain literal',
    () {
      final changed = rewrite((rows) {
        rows.singleWhere(
          (r) => r['Note'] == 'SCHEMA medical-multi-dose-temp-11',
        )['[Medical] Medication'] = 'Custom, compound, 2 (TSP)\nNo dose';
        rows.singleWhere(
              (r) => r['Type'] == 'Solid Feed',
            )['[Solid Feed] Food'] =
            'Custom: food: allergy=true; note=Contains; semicolon, "quote" 👶';
      });
      final plan = preview(changed);
      final meds = sample(plan, 'medical-multi-dose-temp-11');
      expect(
        meds
            .singleWhere((r) => r.details['name'] == 'Custom, compound')
            .details['dose'],
        '2 tsp',
      );
      expect(
        meds.singleWhere((r) => r.details['name'] == 'No dose').details['dose'],
        'Not recorded',
      );
      final food = plan.additions.singleWhere((r) => r.method == 'solids');
      expect(food.details['food'], 'Custom: food');
      expect(food.note, contains('Contains; semicolon, "quote" 👶'));
    },
  );

  for (final input in [naraPostpartumCsvFixture, naraPregnancyCsvFixture]) {
    test(
      'parent and pregnancy exports are rejected as the wrong subject before baby matching',
      () {
        expect(
          () => preview(input),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'reason',
              'Choose a baby export. Parent and pregnancy logs aren’t supported.',
            ),
          ),
        );
      },
    );
  }

  for (final change in <String, void Function(Map<String, String>)>{
    'negative growth': (r) => r['[Growth] Weight'] = '-1',
    'missing growth unit': (r) => r['[Growth] Weight Unit'] = '',
    'unknown growth unit': (r) => r['[Growth] Weight Unit'] = 'STONE',
    'invalid medical unit': (r) => r['[Medical] Temperature Unit'] = 'K',
    'invalid medicine dose': (r) => r['[Medical] Medication'] = 'A, NaN (ML)',
    'unknown medicine unit': (r) => r['[Medical] Medication'] = 'A, 2 (XYZ)',
    'blank medicine names': (r) => r['[Medical] Medication'] = ' \n ',
    'blank food names': (r) => r['[Solid Feed] Food'] = ' \n ',
    'negative sleep duration': (r) => r['[Sleep] Duration (Seconds)'] = '-2',
    'sleep duration mismatch': (r) => r['[Sleep] Duration (Seconds)'] = '1',
    'sleep end before start': (r) => r['[Sleep] End Date/time (Epoch)'] = '0',
    'invalid combo volume': (r) => r['[Combo Feed] Formula Volume'] = '-3',
    'unknown allergy': (r) => r['[Solid Feed] Food'] = 'Apple: allergy=UNKNOWN',
  }.entries) {
    test('${change.key} prevents the entire import', () {
      final text = rewrite((rows) {
        final type = change.key.contains('growth')
            ? 'Growth'
            : change.key.contains('medical') || change.key.contains('medicine')
            ? 'Medical'
            : change.key.contains('sleep')
            ? 'Sleep'
            : change.key.contains('combo')
            ? 'Combo Feed'
            : 'Solid Feed';
        change.value(rows.firstWhere((r) => r['Type'] == type));
      });
      expect(() => preview(text), throwsFormatException);
    });
  }

  test(
    'unknown populated fields and ambiguous lists are explicitly excluded without partial components',
    () {
      final text = rewrite((rows) {
        rows.singleWhere((r) => r['Type'] == 'Combo Feed')['[Future] Detail'] =
            'Future value';
        rows.singleWhere(
          (r) => r['Type'] == 'Solid Feed',
        )['[Solid Feed] Food'] = 'Apple: note=First line\nSecond line';
        rows.singleWhere(
          (r) => r['Note'] == 'SCHEMA medical-multi-dose-temp-11',
        )['[Medical] Medication'] = 'A, 2 (ML)\nA, 3 (ML)';
      });
      final plan = preview(text);
      expect(plan.issues, hasLength(3));
      expect(plan.needsConsent, true);
      expect(sample(plan, 'combo-mixed-04'), isEmpty);
      expect(sample(plan, 'solids-multi-food-05'), isEmpty);
      expect(sample(plan, 'medical-multi-dose-temp-11'), isEmpty);
    },
  );

  test(
    'cross-midnight sleep uses epoch times and contributes to both days',
    () {
      final at = DateTime(2026, 10, 12, 23, 50),
          end = DateTime(2026, 10, 13, 0, 10);
      final text = rewrite((rows) {
        rows.removeWhere(
          (r) =>
              r['Type'] != 'Profile' && r['Note'] != 'SCHEMA sleep-manual-17',
        );
        rows.firstWhere((r) => r['Type'] == 'Sleep').addAll({
          'Start Date/time (Epoch)': '${at.millisecondsSinceEpoch}',
          '[Sleep] End Date/time (Epoch)': '${end.millisecondsSinceEpoch}',
          '[Sleep] Duration (Seconds)': '1200',
          'Time Zone': 'America/Los_Angeles',
        });
      });
      final sleep = preview(
        text,
      ).additions.singleWhere((r) => r.method == 'sleep');
      expect(sleep.at, at.toUtc());
      expect(sleep.endedAt, end.toUtc());
      expect(DaySummary([sleep], DateTime.utc(2026, 10, 12)).sleepSeconds, 600);
      expect(DaySummary([sleep], DateTime.utc(2026, 10, 13)).sleepSeconds, 600);
    },
  );

  test(
    'disk persistence, CSV/JSON backup, undo and deleted split records preserve provenance',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'little-log-full-nara-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/history.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      final manual = Feeding(
        id: 'manual',
        familyId: baby.id,
        at: DateTime.utc(2026),
        method: 'bottle',
        amountMl: 20,
      );
      await repo.add(manual);
      await repo.applyImport(preview(naraFullCsvFixture, [manual]));
      final saved = await repo.feeds(baby.id);
      final jsonBackup = HistoryImport.preview(
        await repo.export(baby),
        baby,
        [],
      );
      final csvBackup = HistoryImport.preview(
        FamilyCsv(baby, saved).encode(),
        baby,
        [],
      );
      expect(
        snapshotFingerprint(jsonBackup.additions),
        snapshotFingerprint(saved),
      );
      expect(
        snapshotFingerprint(csvBackup.additions),
        snapshotFingerprint(saved),
      );
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      final report = (await repo.importReports(baby.id)).single;
      expect(report['added'], 32);
      expect(report['issues'], isEmpty);
      expect(
        snapshotFingerprint(await repo.feeds(baby.id)),
        snapshotFingerprint(saved),
      );
      await repo.undoImport(baby.id);
      expect((await repo.feeds(baby.id)).single.id, 'manual');
      final repeat = preview(
        naraFullCsvFixture,
        await repo.feeds(baby.id, includeDeleted: true),
      );
      expect(repeat.additions, isEmpty);
      expect(repeat.duplicates, 33);
      await db.close();
    },
  );

  test(
    'all split components survive two-device CSV sync, removal, undo and reimport',
    () async {
      const shared = Family(
        id: 'full-csv-sync',
        name: 'Synthetic',
        babyName: 'Schema Baby',
        driveFileId: 'synthetic',
        accountId: 'test',
      );
      final a = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      final b = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      addTearDown(a.db.close);
      addTearDown(b.db.close);
      final cloud = CsvCloud();
      Future<void> sync(Repository repo) =>
          SyncService(repo, cloud).sync(shared, accountId: 'test');
      await a.applyImport(
        HistoryImport.preview(
          naraFullCsvFixture,
          shared,
          [],
          includeUnassignedPumps: true,
        ),
      );
      await sync(a);
      await sync(b);
      expect(await b.feeds(shared.id), hasLength(33));
      expect(
        snapshotFingerprint(await a.feeds(shared.id)),
        snapshotFingerprint(await b.feeds(shared.id)),
      );
      final before = await a.feeds(shared.id, includeDeleted: true);
      await a.applyImport(
        ImportPlan(
          familyId: shared.id,
          before: before,
          additions: [],
          removals: before,
          duplicates: 0,
          label: 'Remove Nara Baby imports',
        ),
      );
      await sync(a);
      await sync(b);
      expect(await b.feeds(shared.id), isEmpty);
      await a.undoImport(shared.id);
      await sync(a);
      await sync(b);
      expect(await b.feeds(shared.id), hasLength(33));
      final repeat = HistoryImport.preview(
        naraFullCsvFixture,
        shared,
        await b.feeds(shared.id, includeDeleted: true),
        includeUnassignedPumps: true,
      );
      expect(repeat.additions, isEmpty);
      expect(repeat.duplicates, 33);
    },
  );
}
