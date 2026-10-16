import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

void main() {
  test(
    'review saves the captured end time and notes once, preserving both sides',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.createLocal('Family', 'Robin');
      final now = DateTime.now();
      final s = NursingSession(
        id: 'session',
        familyId: c.family!.id,
        startedAt: now.subtract(const Duration(minutes: 10)),
        segmentAt: now.subtract(const Duration(minutes: 4)),
        side: 'right',
        leftSeconds: 360,
      ).pause(now);
      await c.repository.saveSession(s);
      await c.refresh();
      await c.saveReviewedNursing(
        session: s,
        endedAt: now,
        note: ' Both sides ',
      );
      final saved = (await c.repository.feeds(c.family!.id)).single;
      expect(saved.leftSeconds, 360);
      expect(saved.rightSeconds, 240);
      expect(saved.endedAt!.isAtSameMomentAs(now), isTrue);
      expect(saved.note, 'Both sides');
      expect(await c.repository.nursingSession(c.family!.id), isNull);
      await expectLater(
        c.saveReviewedNursing(session: s, endedAt: now, note: 'duplicate'),
        throwsStateError,
      );
      expect((await c.repository.feeds(c.family!.id)).length, 1);
      c.dispose();
      await db.close();
    },
  );
  test(
    'a stale review cannot finish a switched timer or write to a different child',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.createLocal('Family', 'Robin');
      final family = c.family!;
      final now = DateTime.now();
      final s = NursingSession(
        id: 'session',
        familyId: family.id,
        startedAt: now.subtract(const Duration(minutes: 10)),
        segmentAt: now.subtract(const Duration(minutes: 10)),
        side: 'left',
      );
      await c.repository.saveSession(
        s.switchTo('right', now.subtract(const Duration(minutes: 1))),
      );
      await expectLater(
        c.saveReviewedNursing(session: s, endedAt: now, note: ''),
        throwsStateError,
      );
      expect((await c.repository.nursingSession(family.id))!.side, 'right');
      c.family = const Family(
        id: 'second',
        name: 'Second family',
        babyName: 'Alex',
      );
      await expectLater(
        c.saveReviewedNursing(session: s, endedAt: now, note: ''),
        throwsStateError,
      );
      expect(await c.repository.feeds(family.id), isEmpty);
      c.dispose();
      await db.close();
    },
  );
}
