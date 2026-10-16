import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import 'sync_test.dart' show FakeCloud, family;

void main() {
  final start = DateTime(2026, 9, 17, 23, 30);
  Feeding entry(
    String method, {
    Map<String, Object?> details = const {},
    double? amount,
    DateTime? end,
  }) => Feeding(
    id: method,
    familyId: family.id,
    at: start,
    method: method,
    details: details,
    amountMl: amount,
    endedAt: end,
    note: 'A note, with "quotes"\nand a newline',
  );
  final records = [
    entry('sleep', end: start.add(const Duration(hours: 2))),
    entry('pumping', amount: 120),
    entry('solids', details: {'food': 'Avocado', 'reaction': 'Not recorded'}),
    entry(
      'growth',
      details: {'measurement': 'Weight', 'value': 4.2, 'unit': 'kg'},
    ),
    entry(
      'health',
      details: {
        'kind': 'Medication',
        'name': 'Recorded medicine',
        'dose': '1 ml',
        'temperature': 37.8,
        'temperatureUnit': '°C',
      },
    ),
    entry('routine', details: {'name': 'Tummy time'}),
    entry('milestone', details: {'name': 'First smile'}),
  ];
  test('all new activities survive CSV, local JSON and acknowledgment', () {
    final decoded = FamilyCsv.decode(FamilyCsv(family, records).encode());
    for (var i = 0; i < records.length; i++) {
      expect(decoded.feeds[i].toRow(), records[i].toRow());
      expect(Feeding.fromJson(records[i].toJson()).toRow(), records[i].toRow());
      expect(records[i].acknowledged().details, records[i].details);
    }
  });
  test(
    'legacy 17-column CSV loads without changing existing record identity',
    () {
      final old = Feeding(
        id: 'old',
        familyId: family.id,
        at: start,
        method: 'bottle',
        amountMl: 90,
      );
      final current = FamilyCsv(family, [old]).encode();
      final legacy = current
          .split('\r\n')
          .where((s) => s.isNotEmpty)
          .map((line) => line.substring(0, line.lastIndexOf(',')))
          .join('\r\n');
      final restored = FamilyCsv.decode(legacy).feeds.single;
      expect(restored.toRow(), old.toRow());
      expect(
        FamilyCsv.decode(
          FamilyCsv(family, [restored, ...records]).encode(),
        ).feeds.length,
        8,
      );
    },
  );
  test(
    'invalid measurements, units, durations and medication doses are rejected',
    () {
      for (final bad in [
        entry('sleep', end: start.subtract(const Duration(minutes: 1))),
        entry('sleep'),
        entry('pumping', amount: double.nan),
        entry(
          'growth',
          details: {'measurement': 'Weight', 'value': 4, 'unit': 'cm'},
        ),
        entry('health', details: {'kind': 'Medication', 'name': 'Medicine'}),
        entry(
          'health',
          details: {'kind': 'Temperature', 'value': 37, 'unit': 'kg'},
        ),
        entry('solids', details: {'food': '', 'reaction': 'Not recorded'}),
      ]) {
        expect(
          () => Feeding.fromRow(bad.toRow(), family.id),
          throwsFormatException,
        );
      }
      final unknown = records.first.toRow()..[8] = 99;
      expect(() => Feeding.fromRow(unknown, family.id), throwsFormatException);
    },
  );
  test(
    'sleep overlaps midnight; milk totals and feed counts exclude pumping',
    () {
      final first = DaySummary(records, start);
      final next = DaySummary(records, DateTime(2026, 9, 18));
      expect(first.sleepSeconds, 1800);
      expect(next.sleepSeconds, 5400);
      expect(first.feeds, 1);
      expect(first.bottleMl, 0);
      expect(first.pumpedMl, 120);
      expect(next.feeds, 0);
    },
  );
  test(
    'timers reopen, remain isolated, finish once and sync with lost-response recovery',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-timers-');
      final path = '${dir.path}/records.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      await repo.saveFamily(family);
      final timer = ActivityTimer(
        id: 'sleep',
        familyId: family.id,
        method: 'sleep',
        startedAt: start,
      );
      await repo.startTimer(timer);
      await repo.startTimer(
        ActivityTimer(
          id: 'duplicate',
          familyId: family.id,
          method: 'sleep',
          startedAt: start,
        ),
      );
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      expect((await repo.activityTimers(family.id)).single.id, 'sleep');
      expect(await repo.activityTimers('another-child'), isEmpty);
      expect(jsonDecode(await repo.export(family))['activeTimers'].length, 1);
      await repo.finishTimer(timer, records.first);
      await repo.finishTimer(timer, records.first);
      expect(await repo.activityTimers(family.id), isEmpty);
      expect((await repo.feeds(family.id)).length, 1);
      for (final record in records.skip(1)) {
        await repo.add(record);
      }
      final cloud = FakeCloud()..loseResponse = true;
      final sync = SyncService(repo, cloud);
      try {
        await sync.sync(family, accountId: family.accountId!);
      } catch (_) {}
      await sync.sync(family, accountId: family.accountId!);
      expect(cloud.rows.length, records.length);
      expect((await repo.feeds(family.id)).every((f) => f.synced), isTrue);
      final exported = jsonDecode(await repo.export(family));
      expect(exported['activities'].length, 6);
      expect(exported['feedings'].single['method'], 'solids');
      await db.close();
      await dir.delete(recursive: true);
    },
  );
}
