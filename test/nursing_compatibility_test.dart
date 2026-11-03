import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/models.dart';
import 'package:little_log/record_validation.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';

import 'google_drive_test.dart' show FakeDrive, TestAuth, family, feed;
import 'support/shared_log_builds_52_55/models.dart' as released;
import 'support/shared_log_builds_52_55/services/family_csv.dart' as released;

void main() {
  final start = DateTime.utc(2026, 1, 2, 8);

  Feeding inconsistent({Map<String, Object?> source = const {}}) => Feeding(
    id: 'resumed-manual',
    familyId: family.id,
    at: start,
    endedAt: start.add(const Duration(seconds: 270)),
    method: 'nursing',
    leftSeconds: 120,
    rightSeconds: 180,
    minutes: 5,
    note: 'Keep this note',
    author: 'caregiver@example.com',
    source: source,
  );

  // Use the actual frozen writer: current toRow must never create this format.
  String legacyCsv(List<Feeding> records) => released.FamilyCsv(
    released.Family.fromJson(family.toJson()),
    records.map((r) => released.Feeding.fromJson(r.toJson())).toList(),
  ).encode();

  void preserved(Feeding original, Feeding recovered) {
    final expected = original.toJson()
      ..remove('endedAt')
      ..remove('source')
      ..remove('synced');
    final actual = recovered.toJson()
      ..remove('endedAt')
      ..remove('source')
      ..remove('synced');
    expect(actual, expected);
    expect(recovered.endedAt, isNull);
    expect(recovered.source['littleLogNursingTiming'], {
      'version': 1,
      'startedAt': original.at.toUtc().toIso8601String(),
      'recordedEndedAt': original.endedAt!.toUtc().toIso8601String(),
      'leftSeconds': original.leftSeconds,
      'rightSeconds': original.rightSeconds,
    });
    validateRecord(recovered, family.id);
  }

  test('resuming a manual duration writes a readable combined session', () {
    final manual = NursingSession(
      id: 'manual-timer',
      familyId: family.id,
      startedAt: start,
      segmentAt: start.add(const Duration(seconds: 90)),
      side: 'right',
      leftSeconds: 120,
    );
    final saved = manual.pause(start.add(const Duration(seconds: 270)))
        .finish(start.add(const Duration(seconds: 270)), 'caregiver');
    expect(saved.leftSeconds, 120);
    expect(saved.rightSeconds, 180);
    expect(saved.endedAt, isNull);
    expect(saved.toRow()[8], 6);
    validateRecord(saved, family.id);
    final older = released.Feeding.fromRow(saved.toRow(), family.id);
    expect(older.leftSeconds, 120);
    expect(older.rightSeconds, 180);
    expect(older.source, saved.source);
    expect(older.toRow(), saved.toRow());
  });

  for (final source in [
    <String, Object?>{},
    <String, Object?>{
      'system': 'Example import',
      'recordId': 'example-import',
      'original': {'duration': 120000},
      'extra': 'keep',
    },
  ]) {
    test('legacy CSV and local JSON recover with provenance: $source', () {
      final original = inconsistent(source: source);
      final csv = legacyCsv([feed('unrelated'), original]);
      expect(() => released.FamilyCsv.decode(csv), throwsFormatException);
      final recovered = FamilyCsv.decode(csv);
      final record = recovered.feeds.last;
      preserved(original, record);
      for (final entry in source.entries) {
        expect(record.source[entry.key], entry.value);
      }
      expect(recovered.needsCompatibilityRewrite, isTrue);
      expect(Feeding.fromJson(original.toJson()).toRow(), record.toRow());
      expect(original.toRow(), record.toRow());
      final portable = recovered.encode();
      final older = released.FamilyCsv.decode(portable);
      expect(older.feeds.last.toRow(), record.toRow());
      expect(FamilyCsv.decode(older.encode()).encode(), portable);
      expect(FamilyCsv.decode(portable).needsCompatibilityRewrite, isFalse);
      expect(recovered.feeds.first.toRow(), feed('unrelated').toRow());
    });
  }

  test('deleted incompatible nursing remains deleted through older edits', () {
    final original = inconsistent();
    final deleted = released.Feeding.fromJson(original.toJson()).asDeleted();
    final broken = released.FamilyCsv(
      released.Family.fromJson(family.toJson()), [deleted],
    ).encode();
    final recovered = FamilyCsv.decode(broken);
    expect(recovered.needsCompatibilityRewrite, isTrue);
    expect(recovered.feeds.single.deleted, isTrue);
    expect(recovered.feeds.single.id, original.id);
    final old = released.FamilyCsv.decode(recovered.encode());
    expect(old.feeds.single.deleted, isTrue);
    expect(FamilyCsv.decode(old.encode()).feeds.single.toRow(),
        recovered.feeds.single.toRow());

    final active = released.FamilyCsv.decode(
      FamilyCsv(family, [original]).encode(),
    ).feeds.single;
    final edited = released.Feeding.fromJson({
      ...active.toJson(), 'id': 'edited', 'note': 'Older edit',
    });
    final roundTrip = FamilyCsv.decode(released.FamilyCsv(old.family, [
      active.asDeleted(), edited,
    ]).encode());
    expect(roundTrip.feeds.first.deleted, isTrue);
    expect(roundTrip.feeds.last.note, 'Older edit');
    expect(roundTrip.feeds.last.source, active.source);
  });

  test('ordinary timers and invalid negative values keep their validation', () {
    final valid = NursingSession(
      id: 'ordinary', familyId: family.id,
      startedAt: start, segmentAt: start, side: 'left',
    ).finish(start.add(const Duration(seconds: 300)), '');
    expect(valid.endedAt, start.add(const Duration(seconds: 300)));
    expect(valid.source, isEmpty);
    expect(valid.toRow()[8], 2);
    expect(Feeding.fromRow(valid.toRow(), family.id).toRow(), valid.toRow());
    for (final index in [10, 11]) {
      final bad = released.Feeding.fromJson(inconsistent().toJson()).toRow();
      bad[index] = -1;
      expect(() => Feeding.fromRow(bad, family.id), throwsFormatException);
    }
    final badEnd = released.Feeding.fromJson(inconsistent().toJson()).toRow();
    badEnd[9] = start.subtract(const Duration(seconds: 1)).toIso8601String();
    expect(() => Feeding.fromRow(badEnd, family.id), throwsFormatException);
  });

  for (final hasLocalCopy in [false, true]) {
    test('sync recovers blocked history and retries safely: local=$hasLocalCopy', () async {
      final repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
      addTearDown(repo.db.close);
      final original = inconsistent();
      if (hasLocalCopy) await repo.add(original.acknowledged());
      final pending = feed('pending');
      await repo.add(pending);
      final server = FakeDrive()
        ..contents = legacyCsv([feed('unrelated'), original])
        ..loseResponse = true;
      final auth = TestAuth();
      addTearDown(auth.dispose);
      final cloud = GoogleDrive(auth, client: MockClient(server.handle));
      addTearDown(cloud.dispose);
      final sync = SyncService(repo, cloud);
      await expectLater(sync.sync(family, accountId: 'a'),
          throwsA(isA<TimeoutException>()));
      await sync.sync(family, accountId: 'a');
      final records = await repo.feeds(family.id);
      expect(records.map((r) => r.id).toSet(),
          {'unrelated', original.id, pending.id});
      expect(records.every((r) => r.synced), isTrue);
      preserved(original, records.singleWhere((r) => r.id == original.id));
      final older = released.FamilyCsv.decode(server.contents);
      expect(older.feeds.length, 3);
      final writes = server.writes;
      await sync.sync(family, accountId: 'a');
      expect(server.writes, writes);
      expect(jsonEncode(older.feeds.map((r) => r.toRow()).toList()),
          jsonEncode(FamilyCsv.decode(server.contents).feeds.map((r) => r.toRow()).toList()));
    });
  }
}
