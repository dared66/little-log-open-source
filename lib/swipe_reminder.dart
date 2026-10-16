import 'dart:math';
import 'storage/repository.dart';

/// One decision per list visit, shared by every row and baby.
class SwipeReminder {
  SwipeReminder(
    this.repository, {
    DateTime Function()? now,
    int Function(int)? roll,
  }) : now = now ?? DateTime.now,
       roll = roll ?? Random().nextInt;
  final Repository repository;
  final DateTime Function() now;
  final int Function(int) roll;
  bool seen = false, learned = false, eligible = true, running = false;
  DateTime? lastShown;

  Future<void> load() async {
    seen = await repository.swipeDemoSeen();
    learned = await repository.swipeActionsLearned();
    lastShown = await repository.swipeDemoLastShown();
    // Older installs recorded only completion, so start their cooldown now.
    if (seen && lastShown == null) {
      lastShown = now();
      await repository.saveSwipeDemoLastShown(lastShown!);
    }
    eligible = !seen && !learned;
  }

  void enterVisit() {
    eligible =
        !learned &&
        (!seen ||
            (lastShown != null &&
                now().difference(lastShown!) >= const Duration(days: 7) &&
                roll(30) == 0));
  }

  bool begin() {
    if (!eligible || learned || running) return false;
    running = true;
    return true;
  }

  Future<void> end(bool completed) async {
    running = false;
    if (!completed || learned) return;
    eligible = false;
    seen = true;
    lastShown = now();
    await repository.saveSwipeDemoSeen();
    await repository.saveSwipeDemoLastShown(lastShown!);
  }

  Future<void> learn() async {
    learned = true;
    eligible = false;
    await repository.saveSwipeActionsLearned();
  }
}
