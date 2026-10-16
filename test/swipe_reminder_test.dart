import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/swipe_reminder.dart';

void main() {
  test('first use, cancellation, weekly cap and one roll per visit', () async {
    final db = await databaseFactoryMemory.openDatabase('reminder');
    addTearDown(db.close);
    final repo = Repository(db);
    var now = DateTime.utc(2026, 10, 9);
    var draws = 0, result = 0;
    SwipeReminder policy() => SwipeReminder(
      repo,
      now: () => now,
      roll: (n) {
        expect(n, 30);
        draws++;
        return result;
      },
    );
    final reminder = policy();
    await reminder.load();
    reminder.enterVisit();
    expect(reminder.begin(), true);
    expect(reminder.begin(), false); // Never two demos together.
    await reminder.end(false);
    expect(await repo.swipeDemoSeen(), false);
    expect(reminder.begin(), true);
    await reminder.end(true);
    expect(draws, 0); // First demonstration is guaranteed.
    now = now.add(const Duration(days: 6, hours: 23));
    final restarted = policy();
    await restarted.load();
    restarted.enterVisit();
    expect(restarted.eligible, false);
    expect(draws, 0);
    now = now.add(const Duration(hours: 1));
    result = 29;
    restarted.enterVisit();
    expect(restarted.eligible, false);
    expect(restarted.begin(), false);
    expect(draws, 1); // Row checks/rebuilds do not draw again.
    result = 0;
    restarted.enterVisit();
    expect(draws, 2);
    expect(restarted.begin(), true);
    await restarted.end(true);
    restarted.enterVisit();
    expect(restarted.eligible, false);
    expect(draws, 2);
    expect(await repo.swipeDemoLastShown(), now);
  });

  test('using a swipe permanently stops reminders across restarts', () async {
    final db = await databaseFactoryMemory.openDatabase('learned');
    addTearDown(db.close);
    final repo = Repository(db);
    final reminder = SwipeReminder(repo);
    await reminder.load();
    await reminder.learn();
    final restarted = SwipeReminder(
      repo,
      now: () => DateTime.utc(2040),
      roll: (_) => throw StateError('Learned users must never roll'),
    );
    await restarted.load();
    restarted.enterVisit();
    expect(restarted.begin(), false);
  });

  test(
    'older completed demos get a cooldown instead of an immediate repeat',
    () async {
      final db = await databaseFactoryMemory.openDatabase('legacy');
      addTearDown(db.close);
      final repo = Repository(db);
      await repo.saveSwipeDemoSeen();
      final now = DateTime.utc(2026, 10, 9);
      final reminder = SwipeReminder(repo, now: () => now, roll: (_) => 0);
      await reminder.load();
      reminder.enterVisit();
      expect(reminder.eligible, false);
      expect(await repo.swipeDemoLastShown(), now);
    },
  );
}
