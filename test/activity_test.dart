import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/sync_service.dart';
import 'sync_test.dart' show FakeCloud, family;

void main() {
  final start = DateTime.utc(2026, 9, 18, 8);
  NursingSession session() => NursingSession(
    id: 'n',
    familyId: family.id,
    startedAt: start,
    segmentAt: start,
    side: 'left',
  );
  test(
    'switching sides preserves elapsed time, including after reconstruction',
    () {
      final left = session().switchTo(
        'right',
        start.add(const Duration(seconds: 65)),
      );
      final restored = NursingSession.fromJson(left.toJson());
      final right = restored.switchTo(
        'left',
        start.add(const Duration(seconds: 155)),
      );
      final feed = right.finish(start.add(const Duration(seconds: 180)), '');
      expect(feed.leftSeconds, 90);
      expect(feed.rightSeconds, 90);
      final decoded = Feeding.fromRow(feed.toRow(), family.id);
      expect(decoded.leftSeconds, 90);
      expect(decoded.endedAt, start.add(const Duration(seconds: 180)));
      expect(
        () => session().finish(start.subtract(const Duration(seconds: 1)), ''),
        throwsFormatException,
      );
    },
  );
  test('very short feeds and old nine-column records are supported', () {
    final feed = session().finish(start, '');
    expect(Feeding.fromRow(feed.toRow(), family.id).leftSeconds, 0);
    expect(
      Feeding.fromRow([
        'old',
        family.id,
        start.toIso8601String(),
        'nursing',
        '',
        12,
        '',
        '',
        1,
      ], family.id).minutes,
      12,
    );
    final row = feed.toRow();
    row[10] = -1;
    expect(() => Feeding.fromRow(row, family.id), throwsFormatException);
  });
  test(
    'reopened nursing continues the same feed without counting the break',
    () async {
      final db = await databaseFactoryIo.openDatabase(
        '${(await Directory.systemTemp.createTemp('nursing-reopen-')).path}/records.db',
      );
      addTearDown(db.close);
      final repo = Repository(db);
      final original = session()
          .switchTo('right', start.add(const Duration(seconds: 120)))
          .finish(start.add(const Duration(seconds: 180)), 'owner');
      await repo.add(original);
      final resumedAt = start.add(const Duration(minutes: 10));
      final reopened = NursingSession(
        id: 'continued',
        familyId: family.id,
        startedAt: start,
        segmentAt: resumedAt,
        side: 'right',
        leftSeconds: original.leftSeconds!,
        rightSeconds: original.rightSeconds!,
        note: 'Still eating',
      );
      await repo.reopenNursing(original, reopened);
      expect(await repo.feeds(family.id), isEmpty);
      expect((await repo.nursingSession(family.id))!.note, 'Still eating');
      await expectLater(
        repo.reopenNursing(original, reopened),
        throwsStateError,
      );
      final finished = reopened.finish(
        resumedAt.add(const Duration(seconds: 90)),
        'owner',
      );
      await repo.finishSession(reopened, finished);
      final saved = (await repo.feeds(family.id)).single;
      expect(saved.leftSeconds, 120);
      expect(saved.rightSeconds, 150);
      expect(saved.at, start);
      expect(await repo.nursingSession(family.id), isNull);
    },
  );
  test('daily nursing totals separate left, right and manual time', () {
    final day = DateTime(2026, 9, 18);
    final summary = DaySummary([
      Feeding(
        id: 'timed',
        familyId: family.id,
        at: day.add(const Duration(hours: 9)),
        method: 'nursing',
        leftSeconds: 125,
        rightSeconds: 65,
        minutes: 4,
      ),
      Feeding(
        id: 'manual',
        familyId: family.id,
        at: day.add(const Duration(hours: 10)),
        method: 'nursing',
        minutes: 5,
      ),
      Feeding(
        id: 'other-day',
        familyId: family.id,
        at: day.subtract(const Duration(minutes: 1)),
        method: 'nursing',
        minutes: 20,
      ),
    ], day);
    expect(summary.nursingLeftSeconds, 125);
    expect(summary.nursingRightSeconds, 65);
    expect(summary.nursingUnassignedSeconds, 300);
    expect(summary.nursingSeconds, 490);
  });
  test('all diaper kinds round trip; unknown types fail', () {
    for (final kind in ['wet', 'dirty', 'both']) {
      final entry = Feeding(
        id: kind,
        familyId: family.id,
        at: start,
        method: 'diaper',
        diaperKind: kind,
      );
      expect(Feeding.fromRow(entry.toRow(), family.id).diaperKind, kind);
    }
    final bad = Feeding(
      id: 'bad',
      familyId: family.id,
      at: start,
      method: 'diaper',
      diaperKind: 'unknown',
    );
    expect(
      () => Feeding.fromRow(bad.toRow(), family.id),
      throwsFormatException,
    );
  });
  test(
    'restart retains timer, finish is atomic and idempotent, sync and export retain activities',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'little-log-activity-',
      );
      final path = '${directory.path}/records.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      await repo.saveFamily(family);
      await repo.saveSession(session());
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      final active = (await repo.nursingSession(family.id))!;
      expect(active.side, 'left');
      expect(await repo.nursingSession('other-family'), isNull);
      expect(jsonDecode(await repo.export(family))['activeNursing']['id'], 'n');
      final feed = active.finish(start.add(const Duration(seconds: 120)), '');
      await repo.finishSession(active, feed);
      await repo.finishSession(active, feed);
      expect(await repo.nursingSession(family.id), isNull);
      expect((await repo.feeds(family.id)).length, 1);
      await repo.add(
        Feeding(
          id: 'd',
          familyId: family.id,
          at: start,
          method: 'diaper',
          diaperKind: 'both',
        ),
      );
      final cloud = FakeCloud()..loseResponse = true;
      final sync = SyncService(repo, cloud);
      try {
        await sync.sync(family, accountId: family.accountId!);
      } catch (_) {}
      await sync.sync(family, accountId: family.accountId!);
      expect(cloud.rows.length, 2);
      expect((await repo.feeds(family.id)).every((e) => e.synced), isTrue);
      final exported = jsonDecode(await repo.export(family));
      expect(exported['diapers'].single['diaperKind'], 'both');
      expect(exported['feedings'].single['leftSeconds'], 120);
      await db.close();
      await directory.delete(recursive: true);
    },
  );
}
