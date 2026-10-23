import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'manual_sync_test.dart' show Account, Auth, Drive;

class JoinDrive extends Drive {
  JoinDrive(super.auth);

  @override
  Future<Family> openFamily(String fileId, String accountId) async => Family(
    id: 'invited-family',
    name: 'Shared family',
    babyName: 'Alex',
    driveFileId: fileId,
    accountId: accountId,
  );
}

void main() {
  for (final largeText in [false, true]) {
    testWidgets(
      'creation, storage switching and back navigation (${largeText ? 'small, large text' : 'phone'})',
      (t) async {
        t.view.physicalSize = largeText
            ? const Size(320, 568)
            : const Size(390, 844);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = largeText ? 1.8 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        if (const bool.fromEnvironment('CAPTURE_ONBOARDING')) {
          for (final font in ['Roboto', 'MaterialIcons']) {
            final loader = FontLoader(font)
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File(
                      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                    ).readAsBytesSync(),
                  ),
                ),
              );
            await loader.load();
          }
        }
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = GoogleAuth()..ready = true;
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false;
        Future<void> tap(String label) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
          final target = find.text(label);
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.tap(target);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        Future<void> capture(String name) async {
          if (const bool.fromEnvironment('CAPTURE_ONBOARDING')) {
            await expectLater(
              find.byType(MaterialApp),
              matchesGoldenFile(
                '../build/onboarding-review/$name-${largeText ? 'small' : 'phone'}.png',
              ),
            );
          }
        }

        await t.pumpWidget(LittleLogApp(controller: c));
        await capture('welcome');
        await tap('New baby log');
        await capture('drive');
        expect(find.text('Google Drive'), findsOneWidget);
        expect(find.text('This device'), findsOneWidget);
        expect(c.auth.user, isNull);
        expect(c.family, isNull);
        await t.enterText(find.byType(TextFormField), 'Robin');
        FocusManager.instance.primaryFocus?.unfocus();
        await tap('This device');
        expect(find.text('Robin'), findsOneWidget);
        await capture('device');
        await tap('Google Drive');
        expect(find.text('Robin'), findsOneWidget);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        expect(find.text('Baby logs'), findsOneWidget);
        await tap('New baby log');
        expect(find.text('Robin'), findsOneWidget);
        await tap('This device');
        await t.enterText(find.byType(TextFormField), '  ');
        await tap('Create baby log');
        expect(find.text('Enter your baby’s name.'), findsOneWidget);
        await capture('validation');
        expect(c.family, isNull);
        await t.enterText(find.byType(TextFormField), 'Robin');
        final action = find.text('Create baby log');
        await t.ensureVisible(action);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(action);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(c.family!.babyName, 'Robin');
        expect(c.family!.isLocal, isTrue);
        expect(c.auth.user, isNull);
        expect((await t.runAsync(c.repository.families))!.length, 1);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }

  testWidgets(
    'Drive creation finishes on the log without an invitation prompt',
    (t) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = Auth()
        ..user = Account()
        ..connected();
      final drive = Drive(auth);
      final c = AppController(Repository(db), auth, drive)..loading = false;
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.tap(find.text('New baby log'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextFormField), 'Robin');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Create baby log'));
      await t.runAsync(() async {
        await t.tap(find.text('Create baby log'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(drive.creations, 1);
      expect(c.family?.isLocal, isFalse);
      expect(find.text('Quick log'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );

  for (final step in ['setup', 'create', 'local']) {
    testWidgets('resumes saved $step stage', (t) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final repo = Repository(db);
      await t.runAsync(() => repo.saveOnboardingStep(step));
      final auth = GoogleAuth();
      final c = AppController(repo, auth, GoogleDrive(auth));
      await t.runAsync(c.initialize);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      expect(find.text('New baby log'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }

  testWidgets('pending local setup fallback keeps the same baby', (t) async {
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final repo = Repository(db);
    const pending = Family(
      id: 'pending',
      name: 'Robin’s family',
      babyName: 'Robin',
    );
    await t.runAsync(() => repo.savePendingSyncedFamily(pending));
    final auth = GoogleAuth();
    final c = AppController(repo, auth, GoogleDrive(auth));
    await t.runAsync(c.initialize);
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('New baby log'), findsOneWidget);
    final local = find.text('This device');
    await t.ensureVisible(local);
    await t.tap(local);
    await t.pumpAndSettle();
    expect(
      find.text('No backup or sharing. Removing the app can delete this log.'),
      findsOneWidget,
    );
    await t.tap(find.byTooltip('Back'));
    await t.pumpAndSettle();
    expect(find.text('New baby log'), findsOneWidget);
    await t.ensureVisible(local);
    await t.tap(local);
    await t.pumpAndSettle();
    final save = find.text('Create baby log');
    await t.ensureVisible(save);
    await t.runAsync(() async {
      await t.tap(save);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(c.family!.id, pending.id);
    expect(c.onboardingSyncedSetup, isFalse);
    expect((await t.runAsync(repo.families))!.length, 1);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  for (final shared in [false, true]) {
    testWidgets(
      'existing ${shared ? 'Drive' : 'local'} family skips onboarding',
      (tester) async {
        final db = await tester.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        );
        final repo = Repository(db!);
        final family = Family(
          id: newId.v4(),
          name: 'Existing family',
          babyName: 'Robin',
          driveFileId: shared ? 'existing-file' : null,
          accountId: shared ? 'account' : null,
        );
        await tester.runAsync(() => repo.saveFamily(family));
        final auth = GoogleAuth();
        final controller = AppController(repo, auth, GoogleDrive(auth));
        await tester.runAsync(controller.initialize);
        await tester.pumpWidget(LittleLogApp(controller: controller));
        await tester.pumpAndSettle();
        expect(controller.family?.id, family.id);
        expect(find.text('Robin'), findsOneWidget);
        expect(find.text('Skip introduction'), findsNothing);
        expect(find.text('New baby log'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        await tester.runAsync(db.close);
      },
    );
  }

  testWidgets(
    'interrupted synced setup resumes without creating a second baby',
    (tester) async {
      final db = await tester.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      );
      final repo = Repository(db!);
      const family = Family(
        id: 'pending-family',
        name: 'Robin’s family',
        babyName: 'Robin',
      );
      await tester.runAsync(() async {
        await repo.saveFamily(family);
        await repo.setPendingSyncedSetup(family.id);
      });
      final auth = GoogleAuth();
      final controller = AppController(repo, auth, GoogleDrive(auth));
      await tester.runAsync(controller.initialize);
      await tester.pumpWidget(LittleLogApp(controller: controller));
      await tester.pumpAndSettle();
      expect(find.text('New baby log'), findsOneWidget);
      expect(controller.onboardingSyncedSetup, isTrue);
      expect(controller.family?.id, family.id);
      expect((await tester.runAsync(repo.families))!.length, 1);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(db.close);
    },
  );

  test(
    'synced setup retries the same family and keeps a local fallback',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final repo = Repository(db);
      final auth = Auth()
        ..user = Account()
        ..connected();
      final drive = Drive(auth)..fail = true;
      final controller = AppController(repo, auth, drive);
      await controller.initialize();
      await expectLater(controller.createSynced('Robin'), throwsStateError);
      final pendingId = controller.family!.id;
      expect(await repo.pendingSyncedSetup(), pendingId);
      expect((await repo.families()).length, 1);
      await expectLater(controller.usePendingSetupLocally(), throwsStateError);
      drive.fail = false;
      await controller.createSynced('Robin');
      expect(controller.family!.id, pendingId);
      expect(controller.family!.isLocal, isFalse);
      expect(await repo.pendingSyncedSetup(), isNull);
      expect((await repo.families()).length, 1);
      controller.dispose();
      await db.close();
    },
  );

  test('caregiver join retains an existing local family', () async {
    final db = await databaseFactoryMemory.openDatabase(newId.v4());
    final repo = Repository(db);
    const local = Family(id: 'local-family', name: 'Local', babyName: 'Robin');
    await repo.saveFamily(local);
    final auth = Auth()
      ..user = Account()
      ..connected();
    final controller = AppController(repo, auth, JoinDrive(auth));
    await controller.initialize();
    await controller.join('shared-file');
    expect(controller.family?.id, 'invited-family');
    expect(
      (await repo.families()).map((family) => family.id),
      containsAll(['local-family', 'invited-family']),
    );
    expect(
      (await repo.families())
          .firstWhere((family) => family.id == local.id)
          .isLocal,
      isTrue,
    );
    controller.dispose();
    await db.close();
  });

  testWidgets('invited caregiver has a direct route on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('onboarding-small'),
    ))!;
    final auth = GoogleAuth()..ready = true;
    final controller = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(LittleLogApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Join an existing baby log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Join an existing baby log'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join an existing baby log'));
    await tester.pumpAndSettle();
    expect(find.text('Join a shared log'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(db.close);
  });
}
