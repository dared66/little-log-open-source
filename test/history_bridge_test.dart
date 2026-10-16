import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/history_bridge.dart';
import 'support/nara_export_fixture.dart';

void main() {
  test(
    'Nara history converts to native CSV and reverses without losing source or precision',
    () {
      final csv = HistoryBridge.naraToCsv(naraExportFixture());
      expect(csv.feeds.where((f) => f.method != 'profile').length, 3);
      final nurse = csv.feeds.singleWhere((f) => f.method == 'nursing');
      expect(nurse.endedAt, isNull);
      expect(nurse.source['leftDurationMs'], 600123);
      final diaper = csv.feeds.singleWhere((f) => f.method == 'diaper');
      expect(diaper.details['poopColors'], ['black', 'green']);
      final bridge = HistoryBridge.csvToNara(csv);
      final parsed = jsonDecode(bridge) as Map;
      expect(parsed['format'], HistoryBridge.format);
      expect((parsed['tracks'] as Map).length, 4);
      final restored = HistoryBridge.naraToCsv(bridge);
      expect(restored.family.id, csv.family.id);
      expect(
        restored.feeds.map((f) => f.toRow()).toList(),
        csv.feeds.map((f) => f.toRow()).toList(),
      );
      expect(
        HistoryBridge.naraToCsv(naraExportFixture(), base: csv).feeds.length,
        csv.feeds.length,
      );
    },
  );
  test(
    'all native categories, profile and tombstones roundtrip through bridge',
    () {
      const family = Family(id: 'family', name: 'Family', babyName: 'Robin');
      final now = DateTime.utc(2026, 9, 1);
      final records = <Feeding>[
        Feeding(
          id: 'profile',
          familyId: family.id,
          at: now,
          method: 'profile',
          details: {
            'birthDate': '2026-01-01',
            'gender': 'FEMALE',
            'nightStart': '19:00',
            'nightEnd': '07:00',
          },
        ),
        Feeding(
          id: 'bottle',
          familyId: family.id,
          at: now,
          method: 'bottle',
          amountMl: 90,
          details: {'breastMilkMl': 60, 'formulaMl': 30},
        ),
        Feeding(
          id: 'diaper',
          familyId: family.id,
          at: now,
          method: 'diaper',
          diaperKind: 'both',
          details: {
            'poopColors': ['green', 'yellow'],
            'poopConsistencies': ['mushy', 'watery'],
          },
        ),
        Feeding(
          id: 'nurse',
          familyId: family.id,
          at: now,
          method: 'nursing',
          leftSeconds: 70,
          rightSeconds: 35,
          minutes: 2,
        ),
        Feeding(
          id: 'sleep',
          familyId: family.id,
          at: now,
          endedAt: now.add(const Duration(hours: 1)),
          method: 'sleep',
        ),
        Feeding(
          id: 'pump',
          familyId: family.id,
          at: now,
          method: 'pumping',
          amountMl: 75,
        ),
        Feeding(
          id: 'solids',
          familyId: family.id,
          at: now,
          method: 'solids',
          details: {'food': 'Pear', 'reaction': 'Not recorded'},
        ),
        Feeding(
          id: 'growth',
          familyId: family.id,
          at: now,
          method: 'growth',
          details: {'measurement': 'Weight', 'value': 5.2, 'unit': 'kg'},
        ),
        Feeding(
          id: 'health',
          familyId: family.id,
          at: now,
          method: 'health',
          details: {'kind': 'Temperature', 'value': 37, 'unit': '°C'},
        ),
        Feeding(
          id: 'routine',
          familyId: family.id,
          at: now,
          method: 'routine',
          details: {'name': 'Bath'},
        ),
        Feeding(
          id: 'milestone',
          familyId: family.id,
          at: now,
          method: 'milestone',
          details: {'name': 'Smile'},
        ),
        Feeding(
          id: 'deleted',
          familyId: family.id,
          at: now,
          method: 'bottle',
          amountMl: 30,
        ).asDeleted(),
      ];
      final original = FamilyCsv.decode(FamilyCsv(family, records).encode());
      final bridge = HistoryBridge.csvToNara(original);
      final restored = HistoryBridge.naraToCsv(bridge);
      expect(
        restored.feeds.map((f) => f.toRow()).toList(),
        original.feeds.map((f) => f.toRow()).toList(),
      );
      expect(restored.feeds.last.deleted, true);
      expect(
        (jsonDecode(bridge)['profile'] as Map)['nightBeginEnd'],
        '19:00,07:00',
      );
    },
  );
  test(
    'unknown Nara activity and conflicting base file fail before any output',
    () {
      final raw = jsonDecode(naraExportFixture()) as Map<String, dynamic>;
      (raw['tracks'] as Map)['unknown'] = {
        'type': 'UNVERIFIED',
        'beginDt': 1768000030000,
        'childKey': 'child',
      };
      expect(
        () => HistoryBridge.naraToCsv(jsonEncode(raw)),
        throwsFormatException,
      );
      final csv = HistoryBridge.naraToCsv(naraExportFixture());
      final changed = [...csv.feeds];
      final first = changed.first;
      changed[0] = Feeding.fromJson({
        ...first.toJson(),
        'note': 'conflicting edit',
      });
      final conflicting = FamilyCsv(csv.family, changed);
      expect(
        () => HistoryBridge.naraToCsv(naraExportFixture(), base: conflicting),
        throwsFormatException,
      );
    },
  );
  test(
    'command line converts both ways and rejects invalid input without replacing output',
    () async {
      final dir = await Directory.systemTemp.createTemp('little-log-bridge-');
      addTearDown(() => dir.delete(recursive: true));
      final input = File('${dir.path}/nara.json')
        ..writeAsStringSync(naraExportFixture());
      final csv = File('${dir.path}/little.csv');
      final back = File('${dir.path}/back.json');
      final first = await Process.run('dart', [
        'run',
        'tool/history_bridge.dart',
        'from-nara',
        '--input',
        input.path,
        '--output',
        csv.path,
      ]);
      expect(first.exitCode, 0, reason: '${first.stderr}');
      expect(FamilyCsv.decode(csv.readAsStringSync()).feeds.length, 4);
      final second = await Process.run('dart', [
        'run',
        'tool/history_bridge.dart',
        'to-nara',
        '--input',
        csv.path,
        '--output',
        back.path,
      ]);
      expect(second.exitCode, 0, reason: '${second.stderr}');
      expect(HistoryBridge.naraToCsv(back.readAsStringSync()).feeds.length, 4);
      final previous = csv.readAsStringSync();
      input.writeAsStringSync('{bad');
      final failed = await Process.run('dart', [
        'run',
        'tool/history_bridge.dart',
        'from-nara',
        '--input',
        input.path,
        '--output',
        csv.path,
      ]);
      expect(failed.exitCode, isNot(0));
      expect(csv.readAsStringSync(), previous);
    },
  );
}
