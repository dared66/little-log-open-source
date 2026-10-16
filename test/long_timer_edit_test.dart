import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/care_entry_form.dart';

void main() {
  test(
    'new nursing requires sides while legacy note edits preserve unknown sides',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.createLocal('Family', 'Robin');
      final now = DateTime.now();
      for (final sides in [(null, null), (60, null), (null, 60)]) {
        await expectLater(
          c.addFeed(
            at: now,
            method: 'nursing',
            minutes: 1,
            leftSeconds: sides.$1,
            rightSeconds: sides.$2,
            note: '',
          ),
          throwsFormatException,
        );
        expect(c.feeds, isEmpty);
      }
      await c.addFeed(
        at: now,
        method: 'nursing',
        minutes: 2,
        leftSeconds: 75,
        rightSeconds: 0,
        note: 'Left',
      );
      expect(c.feeds.single.leftSeconds, 75);
      final legacy = Feeding(
        id: 'legacy',
        familyId: c.family!.id,
        at: now,
        method: 'nursing',
        minutes: 7,
        note: 'Imported',
      );
      await c.repository.add(legacy);
      await c.addFeed(
        at: now,
        method: 'nursing',
        minutes: 7,
        note: 'Corrected note',
        original: legacy,
      );
      final edited = c.feeds.singleWhere((r) => r.note == 'Corrected note');
      expect(edited.leftSeconds, isNull);
      expect(edited.rightSeconds, isNull);
      expect(edited.minutes, 7);
      await expectLater(
        c.addFeed(
          at: now,
          method: 'nursing',
          minutes: 8,
          note: 'Change duration',
          original: edited,
        ),
        throwsFormatException,
      );
      c.dispose();
      await db.close();
    },
  );

  for (final seconds in [0, 18000]) {
    testWidgets('saved timer of $seconds seconds allows a note-only edit', (
      t,
    ) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() => c.createLocal('QA', 'Timer sample'));
      final end = DateTime.now().subtract(const Duration(minutes: 1));
      final session = NursingSession(
        id: 'session',
        familyId: c.family!.id,
        startedAt: end.subtract(Duration(seconds: seconds)),
        segmentAt: end.subtract(Duration(seconds: seconds)),
        side: 'left',
      ).pause(end);
      await t.runAsync(() async {
        await c.repository.saveSession(session);
        await c.refresh();
      });
      await t.runAsync(
        () => c.saveReviewedNursing(
          session: session,
          endedAt: end,
          note: 'Original',
        ),
      );
      final original = c.feeds.single;
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      showModalBottomSheet<void>(
        context: t.element(find.byType(HomePage)),
        isScrollControlled: true,
        builder: (_) => NursingEntryForm(controller: c, original: original),
      );
      await t.pumpAndSettle();
      final note = find.widgetWithText(TextFormField, 'Notes (optional)');
      await t.ensureVisible(note);
      await t.enterText(note, 'Updated note');
      await t.runAsync(() async {
        await t.tap(find.text('Save changes'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(c.feeds.single.note, 'Updated note');
      expect(c.feeds.single.leftSeconds, seconds);
      expect(c.feeds.single.rightSeconds, 0);
      expect(c.feeds.single.minutes, original.minutes);
      expect(c.feeds.single.endedAt, original.endedAt);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }

  testWidgets('nursing duration edits minutes while retaining seconds', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 700);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => c.createLocal('QA', 'Timer sample'));
    final at = DateTime.now().subtract(const Duration(hours: 1));
    final original = Feeding(
      id: newId.v4(),
      familyId: c.family!.id,
      at: at,
      method: 'nursing',
      minutes: 3,
      leftSeconds: 125,
      rightSeconds: 15,
      endedAt: at.add(const Duration(seconds: 140)),
      author: '',
    );
    await t.runAsync(() async {
      await c.repository.add(original);
      await c.refresh();
    });
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    showModalBottomSheet<void>(
      context: t.element(find.byType(HomePage)),
      isScrollControlled: true,
      builder: (_) => NursingEntryForm(controller: c, original: original),
    );
    await t.pumpAndSettle();
    final minuteFields = find.widgetWithText(TextFormField, 'Minutes');
    final secondFields = find.widgetWithText(TextFormField, 'Seconds');
    expect(t.widget<TextFormField>(minuteFields.first).controller!.text, '2');
    expect(t.widget<TextFormField>(secondFields.first).controller!.text, '5');
    await t.ensureVisible(minuteFields.first);
    await t.enterText(secondFields.first, '60');
    await t.ensureVisible(find.text('Save changes'));
    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();
    expect(find.text('Enter whole minutes and 0–59 seconds.'), findsWidgets);
    expect(c.feeds.single.leftSeconds, 125);
    await t.ensureVisible(secondFields.first);
    await t.enterText(secondFields.first, '5');
    await t.enterText(minuteFields.first, '3');
    FocusManager.instance.primaryFocus?.unfocus();
    // OS keyboard dismissal finishes outside Flutter's animation queue.
    await t.pump(const Duration(milliseconds: 500));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Save changes'));
    await t.pumpAndSettle();
    await t.runAsync(() async {
      await t.tap(find.text('Save changes'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.feeds.single.leftSeconds, 185);
    expect(c.feeds.single.rightSeconds, 15);
    expect(c.feeds.single.minutes, 4);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });
}
