import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/monthly_history.dart';

void main() {
  const family = Family(id: 'family', name: 'Demo', babyName: 'Baby');
  Feeding record(String id, String time, {String familyId = 'family'}) =>
      Feeding(
        id: id,
        familyId: familyId,
        at: DateTime.parse(time),
        method: 'bottle',
        amountMl: 90,
      );

  test(
    'month is independent of a caregiver timezone and handles year rollover',
    () {
      expect(
        MonthlyHistory.monthFor(DateTime.parse('2026-12-31T23:30:00-08:00')),
        '2027-01',
      );
      expect(
        MonthlyHistory.monthFor(DateTime.parse('2027-01-01T07:30:00Z')),
        '2027-01',
      );
    },
  );

  test('late records use their event month and old history is retained', () {
    final records = [
      record('new', '2027-02-01T00:00:00Z'),
      record('late', '2026-01-31T23:59:59Z'),
      record('boundary', '2026-02-01T00:00:00Z'),
    ];
    final files = MonthlyHistory.encode(family, records);
    expect(files.keys, ['2026-01.csv', '2026-02.csv', '2027-02.csv']);
    expect(FamilyCsv.decode(files['2026-01.csv']!).feeds.single.id, 'late');
    expect(files.values.expand((csv) => FamilyCsv.decode(csv).feeds).length, 3);
    for (final csv in files.values) {
      expect(FamilyCsv.decode(csv).family.id, family.id);
    }
  });

  test('output is deterministic regardless of arrival order', () {
    final records = [
      record('b', '2026-09-10T00:00:00Z'),
      record('a', '2026-09-10T00:00:00Z'),
    ];
    expect(
      MonthlyHistory.encode(family, records),
      MonthlyHistory.encode(family, records.reversed.toList()),
    );
  });

  test('partitioning refuses another family', () {
    expect(
      () => MonthlyHistory.encode(family, [
        record('foreign', '2026-09-10T00:00:00Z', familyId: 'other'),
      ]),
      throwsFormatException,
    );
  });
}
