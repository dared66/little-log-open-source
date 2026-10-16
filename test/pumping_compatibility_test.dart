import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/design.dart';
import 'package:little_log/volume.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import 'google_drive_test.dart' show FakeDrive, TestAuth, family, feed;
import 'support/shared_log_builds_52_55/models.dart' as old;
import 'support/shared_log_builds_52_55/services/family_csv.dart' as old;

final start = DateTime.utc(2026, 10, 1, 10);
Feeding pump({int seconds = 120, Map<String, Object?> source = const {}}) =>
    Feeding(
      id: 'pump',
      familyId: family.id,
      at: start,
      endedAt: start.add(const Duration(minutes: 10)),
      method: 'pumping',
      amountMl: 60,
      details: {'activeSeconds': seconds},
      source: source,
      note: 'An unchanged note',
      author: 'Caregiver',
    );

// This is the exact build-56 wire shape, before compatible encoding was added.
String build56Csv(List<Feeding> records) => old.FamilyCsv(
  old.Family.fromJson(family.toJson()),
  records.map((f) => old.Feeding.fromJson(f.toJson())).toList(),
).encode();

void main() {
  group('pumping compatibility', () {
    testWidgets('local timer metadata is not presented as an import', (
      t,
    ) async {
      for (final source in [
        <String, Object?>{},
        {'system': 'Nara Baby', 'recordId': 'nara', 'original': {}},
      ]) {
        final record = Feeding.fromRow(pump(source: source).toRow(), family.id);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordRow(
                key: ValueKey(source.isEmpty),
                record: record,
                volumeUnit: VolumeUnit.ml,
              ),
            ),
          ),
        );
        await t.tap(find.byIcon(Icons.expand_more));
        await t.pumpAndSettle();
        expect(find.text('Imported from Little Log'), findsNothing);
        expect(
          find.text('Imported from Nara Baby'),
          source.isEmpty ? findsNothing : findsOneWidget,
        );
      }
    });

    test('manual pumping keeps the existing wire representation', () {
      final manual = Feeding.fromJson({...pump().toJson(), 'details': {}});
      final older = old.Feeding.fromRow(manual.toRow(), family.id);
      expect(manual.toRow()[8], 3);
      expect(older.toRow(), manual.toRow());
      expect(older.source, isEmpty);
    });

    for (final seconds in [0, 120, 600]) {
      test('builds 52–55 read and preserve $seconds active seconds', () {
        final original = pump(seconds: seconds);
        final csv = FamilyCsv(family, [original]).encode();
        final older = old.FamilyCsv.decode(csv);
        final record = older.feeds.single;
        expect(record.details, isEmpty);
        expect(record.at, original.at);
        expect(record.endedAt, original.endedAt);
        expect(record.note, original.note);
        expect(record.amountMl, original.amountMl);
        expect(record.author, original.author);
        expect(jsonEncode(record.toRow()), jsonEncode(original.toRow()));
        final restored = FamilyCsv.decode(older.encode()).feeds.single;
        expect(restored.details['activeSeconds'], seconds);
        expect(restored.toRow(), original.toRow());
        expect(
          FamilyCsv.decode(older.encode()).needsCompatibilityRewrite,
          isFalse,
        );
      });
    }

    test('older note/amount edits preserve active time and tombstones', () {
      final original = pump();
      final older = old.FamilyCsv.decode(
        FamilyCsv(family, [original]).encode(),
      );
      final record = older.feeds.single;
      final edited = old.Feeding.fromJson({
        ...record.toJson(),
        'id': 'edited',
        'amountMl': 75.0,
        'note': 'Edited on an older app',
      });
      final mixed = old.FamilyCsv(older.family, [record.asDeleted(), edited]);
      final restored = FamilyCsv.decode(mixed.encode());
      expect(restored.feeds.first.deleted, isTrue);
      expect(restored.feeds.first.originalRow, original.originalRow);
      expect(restored.feeds.last.details['activeSeconds'], 120);
      expect(restored.feeds.last.amountMl, 75);
      expect(restored.feeds.last.note, 'Edited on an older app');
      expect(
        old.FamilyCsv.decode(restored.encode()).feeds.first.deleted,
        isTrue,
      );
    });

    for (final field in ['at', 'endedAt']) {
      test('older $field edit invalidates only the stale timer duration', () {
        final original = pump();
        final older = old.Feeding.fromRow(original.toRow(), family.id);
        final edited = old.Feeding.fromJson({
          ...older.toJson(),
          field:
              (field == 'at'
                      ? start.add(const Duration(minutes: 1))
                      : start.add(const Duration(minutes: 12)))
                  .toIso8601String(),
        });
        final restored = Feeding.fromRow(edited.toRow(), family.id);
        expect(restored.details, isEmpty);
        expect(restored.at, edited.at);
        expect(restored.endedAt, edited.endedAt);
        expect(jsonEncode(restored.toRow()), jsonEncode(edited.toRow()));
        expect(
          old.Feeding.fromRow(restored.toRow(), family.id).source,
          edited.source,
        );
      });
    }

    test('import provenance and unrelated source extensions survive', () {
      const source = {
        'system': 'Nara Baby',
        'recordId': 'nara-original-id',
        'format': 'csv',
        'original': {'duration': '10:00', 'amount': '60'},
        'component': 'pumping',
        'futureExtension': {'anything': true},
      };
      final original = pump(source: source);
      final older = old.Feeding.fromRow(original.toRow(), family.id);
      final restored = Feeding.fromRow(older.toRow(), family.id);
      for (final key in source.keys) {
        expect(older.source[key], source[key]);
        expect(restored.source[key], source[key]);
      }
      expect(restored.details['activeSeconds'], 120);
      expect(restored.toRow(), original.toRow());
    });

    test('all ten activities remain readable together in older apps', () {
      final records = [
        pump(),
        feed('bottle'),
        Feeding(
          id: 'diaper',
          familyId: family.id,
          at: start,
          method: 'diaper',
          diaperKind: 'wet',
        ),
        NursingSession(
          id: 'nursing',
          familyId: family.id,
          startedAt: start,
          segmentAt: start,
          side: 'left',
        ).finish(start.add(const Duration(minutes: 2)), 'Caregiver'),
        for (final method in [
          'sleep',
          'solids',
          'growth',
          'health',
          'routine',
          'milestone',
        ])
          Feeding(
            id: method,
            familyId: family.id,
            at: start,
            method: method,
            endedAt: method == 'sleep'
                ? start.add(const Duration(minutes: 30))
                : null,
            details: switch (method) {
              'solids' => {'food': 'Avocado', 'reaction': 'Not recorded'},
              'growth' => {'measurement': 'Weight', 'value': 4.2, 'unit': 'kg'},
              'health' => {'kind': 'Temperature', 'value': 37, 'unit': '°C'},
              'routine' || 'milestone' => {'name': 'Synthetic activity'},
              _ => {},
            },
          ),
      ];
      final older = old.FamilyCsv.decode(FamilyCsv(family, records).encode());
      expect(older.feeds.length, 10);
      final restored = FamilyCsv.decode(older.encode());
      expect(
        restored.feeds.map((r) => r.toRow()),
        records.map((r) => r.toRow()),
      );
    });

    test('existing build-56 records and tombstones export compatibly', () {
      for (final original in [
        pump(),
        pump(source: {'system': 'Nara Baby', 'recordId': 'n', 'original': {}}),
      ]) {
        for (final deleted in [false, true]) {
          final record = deleted ? original.asDeleted() : original;
          final brokenCsv = build56Csv([record]);
          expect(() => old.FamilyCsv.decode(brokenCsv), throwsFormatException);
          final current = FamilyCsv.decode(brokenCsv);
          expect(current.needsCompatibilityRewrite, isTrue);
          expect(current.feeds.single.details['activeSeconds'], 120);
          final older = old.FamilyCsv.decode(current.encode());
          expect(older.feeds.single.deleted, deleted);
          final restored = FamilyCsv.decode(older.encode());
          expect(restored.needsCompatibilityRewrite, isFalse);
          expect(restored.feeds.single.originalRow, original.originalRow);
        }
      }
    });

    test(
      'legacy and compatible copies of an ID deduplicate without conflict',
      () {
        final original = pump();
        final legacyLine = build56Csv([original]).split('\r\n')[2];
        final safeCsv = FamilyCsv(family, [original]).encode();
        final decoded = FamilyCsv.decode('$safeCsv$legacyLine\r\n');
        expect(decoded.feeds.length, 1);
        expect(decoded.needsCompatibilityRewrite, isTrue);
        expect(decoded.feeds.single.details['activeSeconds'], 120);
      },
    );

    test(
      'invalid or unknown timer extensions do not break older shared rows',
      () {
        for (final value in [
          null,
          'bad',
          {'version': 2},
          {
            'version': 1,
            'startedAt': 'bad',
            'endedAt': 'bad',
            'activeSeconds': 5,
          },
          for (final seconds in [-1, 601, 1.5, '120'])
            {
              'version': 1,
              'startedAt': start.toIso8601String(),
              'endedAt': start
                  .add(const Duration(minutes: 10))
                  .toIso8601String(),
              'activeSeconds': seconds,
            },
        ]) {
          final original = old.Feeding.fromRow(pump().toRow(), family.id);
          final record = old.Feeding.fromJson({
            ...original.toJson(),
            'source': {...original.source, 'littleLogTimer': value},
          });
          final restored = Feeding.fromRow(record.toRow(), family.id);
          expect(restored.details, isEmpty);
          expect(jsonEncode(restored.toRow()), jsonEncode(record.toRow()));
        }
      },
    );

    group('shared Drive repair', () {
      late Repository repo;
      late FakeDrive server;
      late GoogleDrive cloud;
      late SyncService sync;
      setUp(() async {
        repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
        server = FakeDrive();
        cloud = GoogleDrive(TestAuth(), client: MockClient(server.handle));
        sync = SyncService(repo, cloud);
      });
      tearDown(() async {
        cloud.dispose();
        await repo.db.close();
      });

      test(
        'repairs already-acknowledged rows without new pending entries',
        () async {
          final original = pump();
          server.contents = build56Csv([original]);
          await repo.add(original.acknowledged());
          await sync.sync(family, accountId: 'a');
          expect(server.writes, 1);
          expect(old.FamilyCsv.decode(server.contents).feeds.length, 1);
          expect(
            (await repo.feeds(family.id)).single.details['activeSeconds'],
            120,
          );
          await sync.sync(family, accountId: 'a');
          expect(
            server.writes,
            1,
            reason: 'A repaired file must not be rewritten again',
          );
        },
      );

      test('repairs a joined log, including deleted pumping records', () async {
        server.contents = build56Csv([pump().asDeleted(), feed('bottle')]);
        await sync.sync(family, accountId: 'a');
        final older = old.FamilyCsv.decode(server.contents);
        expect(older.feeds.first.deleted, isTrue);
        expect(older.feeds.last.id, 'bottle');
        expect((await repo.feeds(family.id)).single.id, 'bottle');
      });

      test(
        'concurrent build-56 append survives the conditional repair',
        () async {
          server.contents = build56Csv([pump()]);
          server.beforeWrite = () async {
            // Another build-56 caregiver writes while repair is in flight.
            server.contents = build56Csv([pump(), feed('caregiver')]);
            server.version++;
          };
          await sync.sync(family, accountId: 'a');
          expect(server.conflicts, 1);
          expect(
            old.FamilyCsv.decode(
              server.contents,
            ).feeds.map((r) => r.id).toSet(),
            {'pump', 'caregiver'},
          );
          await sync.sync(family, accountId: 'a');
          expect((await repo.feeds(family.id)).map((r) => r.id).toSet(), {
            'pump',
            'caregiver',
          });
        },
      );

      test(
        'lost repair response retries without duplication or duration loss',
        () async {
          server.contents = build56Csv([pump()]);
          server.loseResponse = true;
          await expectLater(
            sync.sync(family, accountId: 'a'),
            throwsA(isA<Exception>()),
          );
          await sync.sync(family, accountId: 'a');
          expect(server.writes, 1);
          expect(old.FamilyCsv.decode(server.contents).feeds.length, 1);
          expect(
            (await repo.feeds(family.id)).single.details['activeSeconds'],
            120,
          );
        },
      );

      test('failed repair preserves local data and later retries', () async {
        server.contents = build56Csv([pump()]);
        server.rejectAll = true;
        await expectLater(
          sync.sync(family, accountId: 'a'),
          throwsA(isA<CloudException>()),
        );
        expect(server.writes, 0);
        expect(
          (await repo.feeds(family.id)).single.details['activeSeconds'],
          120,
        );
        server.rejectAll = false;
        await sync.sync(family, accountId: 'a');
        expect(old.FamilyCsv.decode(server.contents).feeds.length, 1);
      });

      test(
        'older edits, deletions and new entries sync back without conflicts',
        () async {
          await repo.add(pump());
          await sync.sync(family, accountId: 'a');
          final older = old.FamilyCsv.decode(server.contents);
          final original = older.feeds.single;
          final edited = old.Feeding.fromJson({
            ...original.toJson(),
            'id': 'edited',
            'note': 'Older caregiver edit',
          });
          server.contents = old.FamilyCsv(older.family, [
            original.asDeleted(),
            edited,
            old.Feeding.fromJson(feed('caregiver').toJson()),
          ]).encode();
          server.version++;
          await sync.sync(family, accountId: 'a');
          final records = await repo.feeds(family.id);
          expect(records.map((r) => r.id).toSet(), {'edited', 'caregiver'});
          expect(
            records
                .firstWhere((r) => r.id == 'edited')
                .details['activeSeconds'],
            120,
          );
          expect(
            (await repo.feeds(
              family.id,
              includeDeleted: true,
            )).firstWhere((r) => r.id == 'pump').deleted,
            isTrue,
          );
          expect(server.writes, 1);
        },
      );
    });
  });
}
