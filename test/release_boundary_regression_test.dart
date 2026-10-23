import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/history_import.dart';
import 'package:little_log/storage/repository.dart';
import 'manual_sync_test.dart' show Auth, Account, Drive;

class GatedRepository extends Repository {
  GatedRepository(super.db);
  Completer<void>? feedGate, familyGate;
  final enteredFeeds = Completer<void>();
  final enteredFamilies = Completer<void>();
  @override
  Future<List<Feeding>> feeds(
    String familyId, {
    bool includeDeleted = false,
  }) async {
    final result = await super.feeds(familyId, includeDeleted: includeDeleted);
    final gate = feedGate;
    if (familyId == 'a' && gate != null) {
      feedGate = null;
      enteredFeeds.complete();
      await gate.future;
    }
    return result;
  }

  @override
  Future<List<Family>> families() async {
    final result = await super.families();
    final gate = familyGate;
    if (gate != null) {
      familyGate = null;
      enteredFamilies.complete();
      await gate.future;
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GatedRepository repo;
  late AppController c;
  const a = Family(id: 'a', name: 'Family A', babyName: 'A');
  const b = Family(id: 'b', name: 'Family B', babyName: 'B');
  Feeding row(String id, String baby) => Feeding(
    id: id,
    familyId: baby,
    at: DateTime.utc(2026),
    method: 'bottle',
    amountMl: 90,
  );
  setUp(() async {
    repo = GatedRepository(
      await databaseFactoryMemory.openDatabase(newId.v4()),
    );
    final auth = Auth()..user = Account();
    c = AppController(repo, auth, Drive(auth))..loading = false;
    await repo.saveFamily(a);
    await repo.saveFamily(b);
    c.family = a;
  });
  tearDown(() async {
    await c.sync();
    c.dispose();
    await repo.db.close();
  });

  test(
    'an older refresh cannot put baby A history under baby B heading',
    () async {
      await repo.add(row('a-entry', 'a'));
      await repo.add(row('b-entry', 'b'));
      final gate = Completer<void>();
      repo.feedGate = gate;
      final previous = c.refresh();
      await repo.enteredFeeds.future;
      await c.select(b);
      gate.complete();
      await previous;
      expect(c.family!.id, 'b');
      expect(c.feeds.map((f) => f.familyId), everyElement('b'));
    },
  );

  test(
    'a baby cannot be removed while a sync batch is discovering its pending work',
    () async {
      final gate = Completer<void>();
      repo.familyGate = gate;
      final sync = c.sync();
      await repo.enteredFamilies.future;
      try {
        await expectLater(c.deleteBaby(a), throwsStateError);
      } finally {
        gate.complete();
        await sync;
      }
      expect((await repo.families()).map((f) => f.id), contains('a'));
    },
  );

  test(
    'removing a baby also removes import recovery copies and reports',
    () async {
      final imported = row('imported', 'a');
      await repo.applyImport(
        ImportPlan(
          familyId: 'a',
          before: [],
          additions: [imported],
          removals: [],
          duplicates: 0,
          label: 'Synthetic import',
        ),
      );
      expect(await repo.canUndoImport('a'), isTrue);
      await repo.deleteBaby('a');
      expect(await repo.feeds('a', includeDeleted: true), isEmpty);
      expect(await repo.canUndoImport('a'), isFalse);
      expect(await repo.importReports('a'), isEmpty);
      expect(
        await stringMapStoreFactory
            .store('importReceipts')
            .record('a')
            .get(repo.db),
        isNull,
      );
    },
  );
}
