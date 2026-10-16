import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/diaper_details.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/services/sync_service.dart';
import 'package:little_log/storage/repository.dart';
import 'google_drive_test.dart' show TestAuth, FakeDrive, family;

void main() {
  final at = DateTime.utc(2026, 9, 18, 8);
  Feeding diaper(
    Map<String, Object?> details, {
    String kind = 'both',
    String id = 'd',
  }) => Feeding(
    id: id,
    familyId: family.id,
    at: at,
    method: 'diaper',
    diaperKind: kind,
    details: details,
    note: 'Changed after feeding, "messy"\nNew outfit',
    author: 'Caregiver',
  );

  test('every color and consistency preserves values through CSV and JSON', () {
    for (final color in poopColors.keys) {
      for (final consistency in poopConsistencies.keys) {
        final original = diaper({
          'poopColor': color,
          'poopConsistency': consistency,
          'blowout': true,
          'rash': false,
        });
        final decoded = FamilyCsv.decode(
          FamilyCsv(family, [original]).encode(),
        ).feeds.single;
        expect(decoded.details, original.details);
        expect(decoded.toRow(), original.toRow());
        expect(decoded.note, original.note);
        expect(Feeding.fromJson(original.toJson()).details, original.details);
        expect(original.acknowledged().details, original.details);
      }
    }
  });
  test('unknown, yes and no remain distinct; older diapers stay unchanged', () {
    for (final flag in [null, true, false]) {
      final details = <String, Object?>{'blowout': ?flag, 'rash': ?flag};
      final original = diaper(details);
      final restored = Feeding.fromRow(original.toRow(), family.id);
      expect(restored.details, details);
      expect(restored.toRow()[8], flag == null ? 2 : 4);
    }
    for (final kind in diaperKinds.keys) {
      final restored = Feeding.fromRow(
        diaper({}, kind: kind).toRow(),
        family.id,
      );
      expect(restored.details, isEmpty);
      expect(diaperDetailsLabel(restored), isEmpty);
      final withRash = diaper({'rash': true}, kind: kind);
      expect(
        Feeding.fromRow(withRash.toRow(), family.id).details['rash'],
        true,
      );
    }
  });
  test(
    'rejects impossible contents, unknown values and corrupt version-four rows',
    () {
      for (final invalid in [
        diaper({'poopColor': 'yellow'}, kind: 'wet'),
        diaper({'poopConsistency': 'mushy'}, kind: 'dry'),
        diaper({'blowout': false}, kind: 'wet'),
        diaper({'poopColor': 'ultraviolet'}),
        diaper({'poopConsistency': 'liquid-metal'}),
        diaper({'blowout': 'true'}),
        diaper({'rash': null}),
        diaper({'unknown': 'data'}),
      ]) {
        // Exercise the decoder with the actual map, including unknown keys.
        final row = diaper({'rash': true}).toRow();
        row[12] = invalid.diaperKind!;
        row[13] = jsonEncode(invalid.details);
        expect(() => Feeding.fromRow(row, family.id), throwsFormatException);
        expect(() => validateDiaper(invalid, family.id), throwsFormatException);
      }
      for (final index in [3, 4, 5, 9, 10, 11]) {
        final row = diaper({'rash': true}).toRow();
        row[index] = index == 3 ? 'bottle' : '123';
        expect(() => Feeding.fromRow(row, family.id), throwsFormatException);
      }
      expect(
        () => Feeding.fromRow(diaper({'rash': true}).toRow(), 'other'),
        throwsFormatException,
      );
    },
  );
  test('detail map order cannot create a false sync conflict', () {
    expect(
      diaper({'rash': false, 'blowout': true, 'poopColor': 'yellow'}).toRow(),
      diaper({'poopColor': 'yellow', 'blowout': true, 'rash': false}).toRow(),
    );
  });
  test(
    'reopen, export, conditional CSV sync and second caregiver retain all details',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'diaper-details-',
      );
      final path = '${directory.path}/db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      await repo.saveFamily(family);
      final original = diaper({
        'poopColor': 'mustard',
        'poopConsistency': 'seedy',
        'blowout': true,
        'rash': false,
      });
      await repo.add(original);
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      expect((await repo.feeds(family.id)).single.details, original.details);
      expect(
        jsonDecode(await repo.export(family))['diapers'].single['details'],
        original.details,
      );
      final server = FakeDrive()..loseResponse = true;
      final auth = TestAuth();
      final drive = GoogleDrive(auth, client: MockClient(server.handle));
      final sync = SyncService(repo, drive);
      try {
        await sync.sync(family, accountId: 'a');
      } catch (_) {}
      await sync.sync(family, accountId: 'a');
      expect(
        FamilyCsv.decode(server.contents).feeds.single.details,
        original.details,
      );
      expect((await repo.feeds(family.id)).single.synced, true);
      expect(server.writes, 1);
      final otherDb = await databaseFactoryIo.openDatabase(
        '${directory.path}/other-db',
      );
      final otherRepo = Repository(otherDb);
      final otherDrive = GoogleDrive(auth, client: MockClient(server.handle));
      await SyncService(otherRepo, otherDrive).sync(family, accountId: 'a');
      expect(
        (await otherRepo.feeds(family.id)).single.details,
        original.details,
      );
      expect(await otherRepo.feeds('different-child'), isEmpty);
      otherDrive.dispose();
      drive.dispose();
      auth.dispose();
      await otherDb.close();
      await db.close();
      await directory.delete(recursive: true);
    },
  );
  test(
    'controller refuses stale-child forms and invalid future entries',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'diaper-controller-',
      );
      final db = await databaseFactoryIo.openDatabase('${directory.path}/db');
      final auth = TestAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..family = family;
      await expectLater(
        c.addDiaper(kind: 'both', at: at, expectedFamilyId: 'wrong-child'),
        throwsStateError,
      );
      await expectLater(
        c.addFeed(
          at: at,
          method: 'bottle',
          amountMl: 90,
          note: '',
          expectedFamilyId: 'wrong-child',
        ),
        throwsStateError,
      );
      await expectLater(
        c.addFeed(
          at: DateTime.now().add(const Duration(days: 1)),
          method: 'bottle',
          amountMl: 90,
          note: '',
        ),
        throwsFormatException,
      );
      await expectLater(
        c.addDiaper(kind: 'wet', at: at, poopColor: 'yellow'),
        throwsFormatException,
      );
      expect(await c.repository.feeds(family.id), isEmpty);
      c.dispose();
      await db.close();
      await directory.delete(recursive: true);
    },
  );
}
