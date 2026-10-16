import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_import.dart';
import '../support/nara_csv_fixture.dart';
import 'package:little_log/services/nara_csv.dart';

const baby = Family(id: 'csv-test', name: 'Family', babyName: 'Robin');
String changed(void Function(List<List<String>> rows) change) {
  final rows = FamilyCsv.parseRows(naraCsvFixture);
  for (final row in rows.skip(1)) {
    while (row.length < rows.first.length) {
      row.add('');
    }
  }
  change(rows);
  return rows
      .map((row) => row.map((s) => '"${s.replaceAll('"', '""')}"').join(','))
      .join('\r\n');
}

void cell(List<List<String>> rows, int row, String key, String value) =>
    rows[row][rows.first.indexOf(key)] = value;

void main() {
  for (final input in [
    'Date,Amount,Category\n2026-10-08,25,Food',
    'Type,Profile Name\nBottle Feed,Robin',
    '<html>Not a CSV export</html>',
  ]) {
    test('unrelated input is rejected: ${input.split('\n').first}', () {
      expect(NaraCsv.matches(input), isFalse);
      expect(
        () => HistoryImport.preview(input, baby, []),
        throwsFormatException,
      );
    });
  }
  for (final column in NaraCsv.requiredColumns) {
    test('missing $column cannot be recognized or imported as Nara', () {
      final input = changed((rows) {
        final index = rows.first.indexOf(column);
        for (final row in rows) {
          row.removeAt(index);
        }
      });
      expect(NaraCsv.matches(input), isFalse);
      expect(
        () => HistoryImport.preview(input, baby, []),
        throwsFormatException,
      );
      expect(() => NaraCsv.decode(input, baby), throwsFormatException);
    });
  }
  test('blank rows do not shift exclusion source row numbers', () {
    final input = changed((rows) {
      cell(rows, 1, 'Type', 'Unknown');
      rows.insert(1, List.filled(rows.first.length, ''));
    });
    final plan = HistoryImport.preview(input, baby, []);
    expect(plan.issues.first.row, 3);
  });
  test(
    'real Nara CSV layout preserves times, units, durations, notes, and caregivers',
    () {
      final p = HistoryImport.preview(naraCsvFixture, baby, []);
      expect(p.label, 'Nara Baby CSV');
      expect(p.activityCount, 4);
      expect(p.additions.length, 5);
      expect(p.unassignedPumps, 1);
      final bottle = p.additions.singleWhere((r) => r.method == 'bottle');
      expect(bottle.amountMl, closeTo(3.5 * 29.5735295625, 1e-10));
      expect(bottle.details['breastMilkMl'], bottle.amountMl);
      expect(bottle.at.millisecondsSinceEpoch, 1767980800000);
      expect(bottle.author, 'Alex');
      expect(bottle.source['timezone'], 'America/Los_Angeles');
      expect(
        (bottle.source['original'] as Map)['Last Updated By Caregiver'],
        'Sam',
      );
      final nursing = p.additions.singleWhere((r) => r.method == 'nursing');
      expect(nursing.leftSeconds, 600);
      expect(nursing.rightSeconds, 300);
      expect(nursing.endedAt, isNull);
      final diaper = p.additions.singleWhere((r) => r.method == 'diaper');
      expect(diaper.note, 'Two colors, "quoted" note\nSecond line 👶');
      expect(diaper.diaperKind, 'both');
      expect(diaper.details['poopColors'], ['green', 'yellow']);
      expect(diaper.details['poopConsistencies'], ['mushy', 'watery']);
      expect(diaper.details['blowout'], true);
      final pump = p.additions.singleWhere((r) => r.method == 'pumping');
      expect(pump.amountMl, closeTo(1.75 * 29.5735295625, 1e-10));
      expect(pump.endedAt!.difference(pump.at).inSeconds, 1200);
    },
  );
  test('unassigned pumping needs explicit inclusion', () {
    final p = HistoryImport.preview(
      naraCsvFixture,
      baby,
      [],
      includeUnassignedPumps: true,
    );
    expect(p.activityCount, 5);
    expect(p.unassignedPumps, 1);
    expect(p.additions.where((r) => r.method == 'pumping').length, 2);
  });
  test(
    'reordered headers and extra empty columns do not create duplicates',
    () {
      final p = HistoryImport.preview(naraCsvFixture, baby, []);
      final reordered = changed((rows) {
        for (var i = 0; i < rows.length; i++) {
          rows[i] = rows[i].reversed.toList()
            ..add(i == 0 ? '[Future] Empty' : '');
        }
      });
      final repeat = HistoryImport.preview(reordered, baby, p.additions);
      expect(repeat.additions, isEmpty);
      expect(repeat.duplicates, 5);
    },
  );
  test('BOM and CRLF input produce the same records', () {
    final p = HistoryImport.preview('\ufeff${changed((_) {})}', baby, []);
    expect(p.activityCount, 4);
  });
  test('ML and mixed milk/formula amounts retain their values', () {
    final s = changed((rows) {
      cell(rows, 2, '[Bottle Feed] Type', 'Breast Milk Formula');
      cell(rows, 2, '[Bottle Feed] Breast Milk Volume', '60');
      cell(rows, 2, '[Bottle Feed] Breast Milk Volume Unit', 'ML');
      cell(rows, 2, '[Bottle Feed] Formula Volume', '30');
      cell(rows, 2, '[Bottle Feed] Formula Volume Unit', 'ML');
      cell(rows, 2, '[Bottle Feed] Volume', '90');
      cell(rows, 2, '[Bottle Feed] Volume Unit', 'ML');
    });
    final r = HistoryImport.preview(
      s,
      baby,
      [],
    ).additions.singleWhere((r) => r.method == 'bottle');
    expect(r.amountMl, 90);
    expect(r.details['formulaMl'], 30);
  });
  test(
    'CSV formula-like text remains literal, including leading apostrophes',
    () {
      final s = changed((rows) => cell(rows, 1, 'Note', "'=SUM(1,2)"));
      expect(
        HistoryImport.preview(s, baby, []).additions.first.note,
        "'=SUM(1,2)",
      );
    },
  );
  final badCases = <String, void Function(List<List<String>>)>{
    'unnamed header': (r) => r.first[r.first.indexOf('Note')] = '',
    'blank activity type': (r) => cell(r, 1, 'Type', ' '),
    'blank activity ID': (r) => cell(r, 1, '_activityKey', ' '),
    'wrong baby': (r) => cell(r, 1, 'Profile Name', 'Sam'),
    'mixed profile ids': (r) => cell(r, 1, '_profileKey', 'other-baby'),
    'mixed family ids': (r) => cell(r, 1, '_familyKey', 'other-family'),
    'missing activity id': (r) => cell(r, 1, '_activityKey', ''),
    'duplicate activity id': (r) => cell(r, 2, '_activityKey', 'diaper-1'),
    'unknown unit': (r) =>
        cell(r, 2, '[Bottle Feed] Breast Milk Volume Unit', 'OZ_UNKNOWN'),
    'missing unit': (r) =>
        cell(r, 2, '[Bottle Feed] Breast Milk Volume Unit', ''),
    'negative amount': (r) =>
        cell(r, 2, '[Bottle Feed] Breast Milk Volume', '-3'),
    'nonfinite amount': (r) =>
        cell(r, 2, '[Bottle Feed] Breast Milk Volume', 'NaN'),
    'invalid epoch': (r) => cell(r, 1, 'Start Date/time (Epoch)', 'not a date'),
    'unknown diaper contents': (r) => cell(r, 1, '[Diaper] Type', 'Unknown'),
    'unknown diaper texture': (r) =>
        cell(r, 1, '[Diaper] Dirty Texture', 'UNKNOWN'),
    'negative nursing seconds': (r) =>
        cell(r, 3, '[Breastfeed] Left Duration (Seconds)', '-1'),
    'fractional nursing seconds': (r) =>
        cell(r, 3, '[Breastfeed] Left Duration (Seconds)', '1.5'),
    'missing nursing duration': (r) {
      cell(r, 3, '[Breastfeed] Left Duration (Seconds)', '');
      cell(r, 3, '[Breastfeed] Right Duration (Seconds)', '');
    },
    'inconsistent pump duration': (r) =>
        cell(r, 4, '[Pump] Duration (Seconds)', '10'),
    'incomplete row': (r) => r[1].removeLast(),
    'duplicate column': (r) => r.first[1] = 'Type',
    'invalid unassigned pump even when excluded': (r) =>
        cell(r, 5, '[Pump] Total Volume', '-2'),
  };
  for (final e in badCases.entries) {
    test(
      '${e.key} blocks the entire preview',
      () => expect(
        () => HistoryImport.preview(changed(e.value), baby, []),
        throwsFormatException,
      ),
    );
  }
  test('changed contents under an existing ID fail without overwriting', () {
    final p = HistoryImport.preview(naraCsvFixture, baby, []);
    expect(
      () => HistoryImport.preview(
        changed((r) => cell(r, 2, '[Bottle Feed] Breast Milk Volume', '4')),
        baby,
        p.additions,
      ),
      throwsFormatException,
    );
  });
  test('truncated quote and empty file fail', () {
    expect(
      () => HistoryImport.preview('"Type","Profile Name"\n"broken', baby, []),
      throwsFormatException,
    );
    expect(() => HistoryImport.preview('', baby, []), throwsFormatException);
  });
  test(
    'unsupported activity is reported by row and ID and requires consent',
    () {
      final s = changed((r) => cell(r, 1, 'Type', 'Unknown'));
      final p = HistoryImport.preview(s, baby, []);
      expect(p.needsConsent, isTrue);
      final issue = p.issues.firstWhere((i) => i.requiresConsent);
      expect(issue.row, 2);
      expect(issue.recordId, 'diaper-1');
      expect(issue.type, 'Unknown');
      expect(p.additions.any((r) => r.method == 'diaper'), isFalse);
      expect(
        HistoryImport.preview(s, baby, [], allowPartial: true).needsConsent,
        isFalse,
      );
    },
  );
  test(
    'unknown populated fields report every affected row instead of dropping data',
    () {
      final s = changed((rows) {
        rows.first.add('[Future] Detail');
        for (var i = 1; i < rows.length; i++) {
          rows[i].add(i <= 2 ? 'value' : '');
        }
      });
      final p = HistoryImport.preview(s, baby, []);
      expect(p.issues.where((i) => i.requiresConsent).map((i) => i.row), [
        2,
        3,
      ]);
      expect(p.needsConsent, true);
    },
  );
}
