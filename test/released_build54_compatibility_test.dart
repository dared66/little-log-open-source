import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/models.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import 'google_drive_test.dart' show FakeDrive, TestAuth, family;
import 'support/build54_history_fixture.dart';
import 'support/shared_log_builds_52_55/models.dart' as build54;
import 'support/shared_log_builds_52_55/services/family_csv.dart' as build54;

void sameHistory(Iterable<Feeding> expected, Iterable<Feeding> actual) {
  Map<String, String> contents(Iterable<Feeding> records) => {
    for (final r in records)
      r.id: jsonEncode({'row': r.originalRow, 'deleted': r.deleted}),
  };
  expect(contents(actual), contents(expected));
}

void main() {
  group('released build 54 compatibility — mandatory', () {
    test('frozen released history covers every activity and schemas 1–6', () {
      final released = build54.FamilyCsv.decode(build54HistoryCsv);
      final current = FamilyCsv.decode(build54HistoryCsv);
      expect(current.feeds.length, 22);
      expect(
        current.feeds
            .where((f) => f.method != 'profile')
            .map((f) => f.method)
            .toSet(),
        quickLogActivities.keys.toSet(),
        reason:
            'Every new activity must have an explicit build-54 compatibility strategy.',
      );
      expect(
        FamilyCsv.parseRows(
          build54HistoryCsv,
        ).skip(2).map((row) => row[12]).toSet(),
        {'1', '2', '3', '4', '5', '6'},
      );
      expect(current.feeds.where((f) => f.deleted).length, 2);
      expect(
        current.family.toJson(),
        Family.fromJson(released.family.toJson()).toJson(),
      );
      for (final text in [
        released.encode(),
        current.encode(),
        build54.FamilyCsv.decode(current.encode()).encode(),
      ]) {
        sameHistory(current.feeds, FamilyCsv.decode(text).feeds);
      }
    });

    test(
      'released writer can edit every existing kind without losing data or reviving deletions',
      () {
        final current = FamilyCsv.decode(build54HistoryCsv);
        final older = build54.FamilyCsv.decode(current.encode());
        final edited = [
          for (final record in older.feeds)
            if (record.deleted) record else record.asDeleted(),
          for (final record in older.feeds.where((f) => !f.deleted))
            build54.Feeding.fromJson({
              ...record.toJson(),
              'id': '${record.id}-edited-54',
              'note': 'Updated by build 54',
            }),
        ];
        final back = FamilyCsv.decode(
          build54.FamilyCsv(older.family, edited).encode(),
        );
        expect(back.feeds.where((f) => f.deleted).length, 22);
        expect(back.feeds.where((f) => !f.deleted).length, 20);
        for (final original in current.feeds) {
          expect(
            back.feeds.singleWhere((f) => f.id == original.id).deleted,
            isTrue,
          );
          if (original.deleted) continue;
          final replacement = back.feeds.singleWhere(
            (f) => f.id == '${original.id}-edited-54',
          );
          expect(
            replacement.originalRow,
            Feeding.fromJson({
              ...original.toJson(),
              'id': replacement.id,
              'note': 'Updated by build 54',
            }).originalRow,
          );
        }
        sameHistory(
          back.feeds,
          FamilyCsv.decode(
            build54.FamilyCsv.decode(back.encode()).encode(),
          ).feeds,
        );
      },
    );

    test(
      'current timer state upgrades running pumps and paused nursing saved by build 54',
      () {
        final oldPump = build54PumpingTimerJson;
        final currentPump = ActivityTimer.fromJson(
          Map<String, Object?>.from(oldPump),
        );
        final start = DateTime.parse(oldPump['startedAt'] as String);
        expect(currentPump.id, oldPump['id']);
        expect(currentPump.phase, 'running');
        expect(
          currentPump.elapsedAt(start.add(const Duration(minutes: 10))),
          const Duration(minutes: 10),
        );
        final nursing = NursingSession.fromJson(
          Map<String, Object?>.from(build54PausedNursingJson),
        );
        expect(nursing.paused, isTrue);
        expect(nursing.leftSeconds, 60);
        expect(nursing.rightSeconds, 30);
        expect(
          nursing.secondsFor('right', start.add(const Duration(hours: 1))),
          30,
        );
        final reopened = NursingSession.fromJson(nursing.toJson());
        expect(reopened.paused, isTrue);
        expect(reopened.leftSeconds, 60);
        expect(reopened.rightSeconds, 30);
      },
    );

    test('the released reader rejects the original broken pumping format', () {
      // Negative control: if this starts passing, the frozen reader was weakened.
      final record = build54.Feeding(
        id: 'broken-56',
        familyId: family.id,
        at: DateTime.utc(2026, 9, 1),
        endedAt: DateTime.utc(2026, 9, 1, 0, 10),
        method: 'pumping',
        amountMl: 60,
        details: const {'activeSeconds': 120},
      );
      final broken = build54.FamilyCsv(
        build54.Family.fromJson(family.toJson()),
        [record],
      ).encode();
      expect(() => build54.FamilyCsv.decode(broken), throwsFormatException);
      final repaired = FamilyCsv.decode(broken).encode();
      expect(build54.FamilyCsv.decode(repaired).feeds.single.amountMl, 60);
      expect(
        FamilyCsv.decode(repaired).feeds.single.details['activeSeconds'],
        120,
      );
    });

    test(
      '54 and current caregivers share, edit, delete and recover a lost sync response',
      () async {
        final repo = Repository(
          await databaseFactoryMemory.openDatabase(newId.v4()),
        );
        addTearDown(repo.db.close);
        final server = FakeDrive()..contents = build54HistoryCsv;
        final cloud = GoogleDrive(
          TestAuth(),
          client: MockClient(server.handle),
        );
        addTearDown(cloud.dispose);
        final sync = SyncService(repo, cloud);
        await sync.sync(family, accountId: 'a');
        sameHistory(
          FamilyCsv.decode(build54HistoryCsv).feeds,
          await repo.feeds(family.id, includeDeleted: true),
        );
        final start = DateTime.utc(2026, 9, 1, 11);
        final pump = Feeding(
          id: 'new-paused-pump',
          familyId: family.id,
          at: start,
          endedAt: start.add(const Duration(minutes: 20)),
          method: 'pumping',
          amountMl: 80,
          details: const {'activeSeconds': 600},
        );
        await repo.add(pump);
        await sync.sync(family, accountId: 'a');
        final older = build54.FamilyCsv.decode(server.contents);
        final oldPump = older.feeds.singleWhere((f) => f.id == pump.id);
        final oldBottle = older.feeds.singleWhere((f) => f.id == 'bottle');
        final replacement = build54.Feeding.fromJson({
          ...oldPump.toJson(),
          'id': 'pump-edited-on-54',
          'amountMl': 95.0,
          'note': 'Older caregiver note',
        });
        final olderAddition = build54.Feeding(
          id: 'bottle-from-54',
          familyId: family.id,
          at: start,
          method: 'bottle',
          amountMl: 45,
        );
        server.contents = build54.FamilyCsv(older.family, [
          for (final record in older.feeds)
            if (record.id == oldPump.id || record.id == oldBottle.id)
              record.asDeleted()
            else
              record,
          replacement,
          olderAddition,
        ]).encode();
        server.version++;
        final newAddition = Feeding(
          id: 'routine-current',
          familyId: family.id,
          at: start,
          method: 'routine',
          details: const {'name': 'Synthetic routine'},
        );
        await repo.add(newAddition);
        server.loseResponse = true;
        await expectLater(
          sync.sync(family, accountId: 'a'),
          throwsA(isA<TimeoutException>()),
        );
        await sync.sync(family, accountId: 'a');
        final local = await repo.feeds(family.id, includeDeleted: true);
        final finalOlder = build54.FamilyCsv.decode(server.contents);
        sameHistory(local, FamilyCsv.decode(finalOlder.encode()).feeds);
        final saved = local.singleWhere((f) => f.id == replacement.id);
        expect(saved.details['activeSeconds'], 600);
        expect(saved.amountMl, 95);
        expect(saved.note, 'Older caregiver note');
        expect(local.singleWhere((f) => f.id == pump.id).deleted, isTrue);
        expect(local.singleWhere((f) => f.id == oldBottle.id).deleted, isTrue);
        expect(local.where((f) => f.id == olderAddition.id).length, 1);
        expect(local.where((f) => f.id == newAddition.id).length, 1);
        expect(local.every((f) => f.synced), isTrue);
        final writes = server.writes;
        await sync.sync(family, accountId: 'a');
        expect(
          server.writes,
          writes,
          reason: 'Retry must not duplicate or rewrite already-synced history.',
        );
      },
    );
  });
}
