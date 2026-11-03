import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/models.dart';
import 'package:little_log/record_validation.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

import 'google_drive_test.dart' show FakeDrive, TestAuth, family, feed;
import 'support/build54_history_fixture.dart';
import 'support/shared_log_builds_52_55/services/family_csv.dart' as released;

void main() {
  final start = DateTime.utc(2026, 1, 2);
  // This passes the model validator, but the shipped schema-1 reader rejects it.
  // The write boundary must exercise the reader, not merely repeat validation.
  final unreadable = Feeding(
    id: 'unreadable', familyId: family.id, at: start,
    method: 'nursing', minutes: 241,
  );

  Future<Repository> repository() async {
    final db = await databaseFactoryMemory.openDatabase(newId.v4());
    addTearDown(db.close);
    return Repository(db);
  }

  test('add, edit, merge and join reject unreadable data atomically', () async {
    validateRecord(unreadable, family.id);
    expect(() => Feeding.fromRow(unreadable.toRow(), family.id), throwsFormatException);
    final repo = await repository();
    final original = feed('original');
    await repo.add(original);
    await expectLater(repo.add(unreadable), throwsFormatException);
    await expectLater(repo.replace(original, unreadable), throwsFormatException);
    await expectLater(repo.merge([feed('batch'), unreadable]), throwsFormatException);
    await expectLater(repo.joinFamily(family, [feed('joined'), unreadable]), throwsFormatException);
    expect(await repo.families(), isEmpty);
    expect(await repo.activeFamilyId(), isNull);
    final saved = await repo.feeds(family.id, includeDeleted: true);
    expect(saved.single.toRow(), original.toRow());
    expect(saved.single.deleted, isFalse);
  });

  test('failed nursing finish keeps the durable timer for recovery', () async {
    final repo = await repository();
    final session = NursingSession(
      id: unreadable.id, familyId: family.id,
      startedAt: start, segmentAt: start, side: 'left', paused: true,
    );
    await repo.saveSession(session);
    await expectLater(repo.finishSession(session, unreadable), throwsFormatException);
    expect((await repo.nursingSession(family.id))!.toJson(), session.toJson());
    expect(await repo.feeds(family.id), isEmpty);
    final wrongFamily = Feeding(
      id: session.id, familyId: 'other-family', at: start,
      method: 'nursing', minutes: 1,
    );
    await expectLater(repo.finishSession(session, wrongFamily), throwsFormatException);
    expect(await repo.feeds('other-family'), isEmpty);
    expect(await repo.nursingSession(family.id), isNotNull);
  });

  test('failed activity finish keeps its timer and all original details', () async {
    final repo = await repository();
    final timer = ActivityTimer(
      id: 'sleep', familyId: family.id, method: 'sleep', startedAt: start,
    );
    final invalid = Feeding(
      id: timer.id, familyId: family.id, method: 'sleep', at: start,
      endedAt: start.add(const Duration(minutes: 30)), minutes: 30,
    );
    validateActivity(invalid, family.id);
    await repo.startTimer(timer);
    await expectLater(repo.finishTimer(timer, invalid), throwsFormatException);
    expect((await repo.activityTimers(family.id)).single.toJson(), timer.toJson());
    expect(await repo.feeds(family.id), isEmpty);
  });

  test('unreadable upload never replaces the shared file', () async {
    final server = FakeDrive()..contents = FamilyCsv(family, [feed('existing')]).encode();
    final before = server.contents;
    final auth = TestAuth();
    addTearDown(auth.dispose);
    final cloud = GoogleDrive(auth, client: MockClient(server.handle));
    addTearDown(cloud.dispose);
    await expectLater(cloud.appendFeeds(family, [unreadable]), throwsFormatException);
    expect(server.writes, 0);
    expect(server.contents, before);
  });

  test('every released activity survives save, restart and older CSV reader', () async {
    final directory = await Directory.systemTemp.createTemp('write-integrity-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/history.db';
    var db = await databaseFactoryIo.openDatabase(path);
    addTearDown(() => db.close());
    var repo = Repository(db);
    final history = FamilyCsv.decode(build54HistoryCsv);
    await repo.merge(history.feeds);
    await db.close();
    db = await databaseFactoryIo.openDatabase(path);
    repo = Repository(db);
    final saved = await repo.feeds(history.family.id, includeDeleted: true);
    final older = released.FamilyCsv.decode(FamilyCsv(history.family, saved).encode());
    final restored = FamilyCsv.decode(older.encode());
    Map<String, List<Object>> rows(Iterable<Feeding> records) => {
      for (final record in records) record.id: record.toRow(),
    };
    expect(rows(saved), rows(history.feeds));
    expect(rows(restored.feeds), rows(history.feeds));
  });
}
