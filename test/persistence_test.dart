import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  test(
    'pending entries and active family survive closing and reopening storage',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'little-log-test-',
      );
      final path = '${directory.path}/records.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      await repo.saveFamily(
        const Family(id: 'a', name: 'Family', babyName: 'Demo'),
      );
      await repo.add(
        Feeding(
          id: 'feed',
          familyId: 'a',
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 60,
        ),
      );
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      expect(await repo.activeFamilyId(), 'a');
      expect((await repo.feeds('a')).single.synced, isFalse);
      expect((await repo.feeds('a')).single.amountMl, 60);
      await db.close();
      await directory.delete(recursive: true);
    },
  );
}
