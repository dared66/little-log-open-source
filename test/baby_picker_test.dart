import 'support/selection_chip_expectations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'support/test_fonts.dart';

void main() {
  test(
    'three baby limit, independent records and timers, persisted selection',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final repo = Repository(db);
      final auth = GoogleAuth();
      final c = AppController(repo, auth, GoogleDrive(auth));
      await expectLater(c.createLocal('Empty', '  '), throwsStateError);
      await c.createLocal('Family', 'Robin');
      final robin = c.family!;
      await repo.add(
        Feeding(
          id: 'bottle',
          familyId: robin.id,
          at: DateTime.now(),
          method: 'bottle',
          amountMl: 60,
        ),
      );
      await repo.saveSession(
        NursingSession(
          id: 'nursing',
          familyId: robin.id,
          startedAt: DateTime.now(),
          segmentAt: DateTime.now(),
          side: 'left',
        ),
      );
      await c.createLocal('Family', 'Alex');
      final alex = c.family!;
      expect(c.feeds, isEmpty);
      expect(c.nursing, isNull);
      await c.createLocal('Family', 'Sam');
      expect(c.backgroundChoice(robin.id), 'linen');
      expect(c.backgroundChoice(alex.id), 'sky');
      expect(c.backgroundChoice(c.family!.id), 'lilac');
      await c.setBabyBackground(robin.id, 'sage');
      expect(await repo.babyBackground(robin.id), 'sage');
      await expectLater(c.createLocal('Family', 'Fourth'), throwsStateError);
      expect(c.family!.babyName, 'Sam');
      await c.select(robin);
      expect(c.feeds.single.amountMl, 60);
      expect(c.nursing!.id, 'nursing');
      expect(await repo.activeFamilyId(), robin.id);
      // Reopening/updating an existing shared log still works at capacity.
      await repo.saveFamily(robin);
      expect((await repo.families()).length, 3);
      c.dispose();
      await db.close();
    },
  );

  test(
    'rename and delete preserve other babies and clear the last baby',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final repo = Repository(db);
      final auth = GoogleAuth();
      final c = AppController(repo, auth, GoogleDrive(auth));
      await c.createLocal('Family', 'Robin');
      final robin = c.family!;
      await repo.add(
        Feeding(
          id: 'feed',
          familyId: robin.id,
          at: DateTime.now(),
          method: 'bottle',
          amountMl: 60,
        ),
      );
      await repo.saveSession(
        NursingSession(
          id: 'session',
          familyId: robin.id,
          startedAt: DateTime.now(),
          segmentAt: DateTime.now(),
          side: 'left',
        ),
      );
      await c.createLocal('Family', 'Alex');
      final alex = c.family!;
      await repo.startTimer(
        ActivityTimer(
          id: 'sleep',
          familyId: robin.id,
          method: 'sleep',
          startedAt: DateTime.now(),
        ),
      );
      await repo.setLastSync(robin.id, DateTime.now());
      const shared = Family(
        id: 'shared',
        name: 'Family',
        babyName: 'Shared',
        driveFileId: 'file',
        accountId: 'account',
      );
      await repo.saveFamily(shared);
      final renamed = await repo.renameBaby(shared.id, 'New name');
      expect(renamed.driveFileId, shared.driveFileId);
      expect(renamed.accountId, shared.accountId);
      await repo.selectFamily(alex.id);
      await c.deleteBaby(shared);
      expect(c.family!.id, alex.id);
      await c.renameBaby(robin, 'Robyn');
      expect(c.family!.id, alex.id);
      expect(await repo.activeFamilyId(), alex.id);
      expect(
        (await repo.families()).firstWhere((f) => f.id == robin.id).babyName,
        'Robyn',
      );
      expect((await repo.feeds(robin.id)).single.amountMl, 60);
      await c.deleteBaby(alex);
      expect(c.family!.id, robin.id);
      expect(c.family!.babyName, 'Robyn');
      expect(c.nursing, isNotNull);
      expect(c.feeds.length, 1);
      await c.deleteBaby(c.family!);
      expect(c.family, isNull);
      expect(c.feeds, isEmpty);
      expect(c.timers, isEmpty);
      expect(c.nursing, isNull);
      expect(c.pendingCount, 0);
      expect(await repo.activeFamilyId(), isNull);
      expect(await repo.feeds(robin.id, includeDeleted: true), isEmpty);
      expect(await repo.nursingSession(robin.id), isNull);
      expect(await repo.activityTimers(robin.id), isEmpty);
      expect(await repo.lastSync(robin.id), isNull);
      await c.createLocal('New family', 'New baby');
      expect(c.family!.babyName, 'New baby');
      c.dispose();
      await db.close();
    },
  );

  for (final scale in [1.0, 1.6]) {
    testWidgets('add and switch on all tabs at text scale $scale', (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() => c.createLocal('Family', 'Robin'));
      await t.pumpWidget(LittleLogApp(controller: c));
      Future<void> tap(Finder finder) async {
        await t.ensureVisible(finder);
        await t.runAsync(() async {
          await t.tap(finder);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
      }

      Future<void> snap(String name) async {
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../../output/baby-manager19/$name-$scale.png'),
          );
        }
      }

      expect(find.text('Robin'), findsOneWidget);
      expect(find.byKey(const ValueKey('baby-switcher')), findsNothing);
      expect(t.getTopLeft(find.text('Robin')).dx, 20);
      await tap(find.text('Settings').last);
      await snap('settings');
      await tap(find.text('Manage baby'));
      final robin = c.family!;
      await tap(find.byKey(ValueKey('baby-background-${robin.id}-sky')));
      expect(c.backgroundChoice(robin.id), 'sky');
      expectSharedSelectionChips(t);
      expect(
        t
            .widget<ChoiceChip>(
              find.descendant(
                of: find.byKey(ValueKey('baby-background-${robin.id}-sky')),
                matching: find.byType(ChoiceChip),
              ),
            )
            .avatar,
        isNotNull,
      );
      expect(
        await t.runAsync(() => c.repository.babyBackground(robin.id)),
        'sky',
      );
      expect(
        t
            .widget<MaterialApp>(find.byType(MaterialApp))
            .theme!
            .scaffoldBackgroundColor,
        babyBackgrounds['sky']!.color,
      );
      await snap('manage');
      await tap(find.text('Edit name'));
      await t.enterText(find.byType(TextFormField), '');
      await tap(find.text('Save name'));
      expect(find.text('Enter your baby’s name.'), findsOneWidget);
      await t.enterText(find.byType(TextFormField), 'Robyn');
      await tap(find.text('Save name'));
      expect(c.family!.babyName, 'Robyn');
      await tap(find.text('Add baby'));
      await tap(find.text('This device'));
      await tap(find.widgetWithText(FilledButton, 'Create baby log'));
      expect(find.text('Enter your baby’s name.'), findsOneWidget);
      await snap('validation');
      await t.enterText(find.byType(TextFormField), 'Alex');
      await tap(find.widgetWithText(FilledButton, 'Create baby log'));
      expect(c.family!.babyName, 'Alex');
      await tap(find.text('Add baby'));
      await tap(find.text('This device'));
      await t.enterText(find.byType(TextFormField), 'Sam');
      await tap(find.widgetWithText(FilledButton, 'Create baby log'));
      expect(find.text('Add baby'), findsNothing);
      expect(find.text('3 of 3 babies added'), findsOneWidget);
      await snap('full');
      final sam = c.family!;
      await tap(find.byKey(ValueKey('delete-${sam.id}')));
      await snap('delete-confirmation');
      await tap(find.text('Cancel'));
      expect(c.families.length, 3);
      await tap(find.byKey(ValueKey('delete-${sam.id}')));
      await tap(find.widgetWithText(TextButton, 'Delete baby').last);
      expect(c.families.length, 2);
      expect(find.text('Add baby'), findsOneWidget);
      await tap(find.byTooltip('Close').last);
      for (final tab in ['Log', 'Settings', 'Log']) {
        await tap(find.text(tab).last);
        final switcher = find.byKey(const ValueKey('baby-switcher'));
        expect(
          find.descendant(
            of: switcher,
            matching: find.byIcon(Icons.expand_more),
          ),
          findsOneWidget,
        );
        expect(t.getSize(switcher).height, greaterThanOrEqualTo(48));
        await tap(switcher);
        expect(find.text('Switch baby'), findsOneWidget);
        expect(find.text('Robyn'), findsWidgets);
        await tap(find.text('Alex').last);
        expect(c.family!.babyName, 'Alex');
        expect(find.text('Alex'), findsOneWidget);
        expect(t.getTopLeft(find.text('Alex')).dx, 20);
        await snap(tab.toLowerCase());
      }
      await tap(find.text('Settings').last);
      await tap(find.text('Manage baby'));
      while (c.families.isNotEmpty) {
        await tap(find.byKey(ValueKey('delete-${c.families.first.id}')));
        await tap(find.widgetWithText(TextButton, 'Delete baby').last);
      }
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }
}
