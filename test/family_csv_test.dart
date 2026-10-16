import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';

void main() {
  const family = Family(id: 'family', name: 'Family, "A"', babyName: 'Bébé 👶');
  test(
    'CSV round trips quotes, newlines, Unicode and formula-looking text',
    () {
      for (final note in [
        'a,b',
        '"quoted"\r\nnext\nline',
        '=1+1',
        '+SUM(A1)',
        '-text',
        '@x',
        "'literal",
        "'=x",
        '\ttext',
        '👶',
      ]) {
        final feed = Feeding(
          id: 'event',
          familyId: family.id,
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 90.5,
          note: note,
        );
        final encoded = FamilyCsv(family, [feed]).encode();
        final decoded = FamilyCsv.decode(encoded);
        expect(decoded.family.name, family.name);
        expect(decoded.family.babyName, family.babyName);
        expect(decoded.feeds.single.toRow(), feed.toRow());
        if (note == '=1+1') expect(encoded, contains('"\'=1+1"'));
      }
    },
  );
  test('all activity fields survive CSV round trip', () {
    final start = DateTime.utc(2026);
    final nurse = NursingSession(
      id: 'n',
      familyId: family.id,
      startedAt: start,
      segmentAt: start,
      side: 'left',
    ).finish(start.add(const Duration(seconds: 70)), 'caregiver');
    final diaper = Feeding(
      id: 'd',
      familyId: family.id,
      at: start,
      method: 'diaper',
      diaperKind: 'both',
    );
    final decoded = FamilyCsv.decode(
      FamilyCsv(family, [nurse, diaper]).encode(),
    );
    expect(decoded.feeds[0].leftSeconds, 70);
    expect(decoded.feeds[1].diaperKind, 'both');
  });
  test('unknown versions, malformed quotes and foreign rows fail closed', () {
    final csv = FamilyCsv(family, []).encode();
    expect(
      () => FamilyCsv.decode(csv.replaceFirst('"family","1"', '"family","99"')),
      throwsFormatException,
    );
    expect(() => FamilyCsv.decode('$csv"unterminated'), throwsFormatException);
    expect(() => FamilyCsv.decode('wrong,header\n'), throwsFormatException);
    final foreign = Feeding(
      id: 'x',
      familyId: 'other',
      at: DateTime.utc(2026),
      method: 'bottle',
      amountMl: 50,
    );
    expect(
      () => FamilyCsv.decode(FamilyCsv(family, [foreign]).encode()),
      throwsFormatException,
    );
  });
  test('legacy sheet connection is local, never mistaken for a CSV', () {
    final result = Family.fromJson({
      'id': 'a',
      'name': 'Family',
      'babyName': 'Baby',
      'sheetId': 'old-sheet',
      'accountId': 'a',
    });
    expect(result.isLocal, true);
    expect(result.driveFileId, null);
  });
}
