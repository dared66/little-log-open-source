import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:little_log/config.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/main.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'backup_flow_test.dart' show fixture, BackupAuth, BackupDrive;
import 'manual_sync_test.dart' show Account;
import 'support/test_fonts.dart';

class AddBabyJoinDrive extends BackupDrive {
  AddBabyJoinDrive(super.auth);
  @override
  Future<List<Map<String, String>>> listFamilies() async => [
    {'id': 'shared-file', 'babyName': 'Sam', 'ownedByMe': 'false'},
  ];
  @override
  Future<Family> openFamily(String fileId, String accountId) async => Family(
    id: 'shared',
    name: 'Shared family',
    babyName: 'Sam',
    driveFileId: fileId,
    accountId: accountId,
  );
}

void main() {
  for (final storage in ['device', 'drive', 'drive retry']) {
    testWidgets(
      'Add baby uses $storage without uploading existing logs',
      (t) async {
        const regular = bool.fromEnvironment('REVIEW_REGULAR');
        t.view.physicalSize = regular
            ? const Size(390, 844)
            : const Size(320, 700);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = regular ? 1 : 1.6;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.runAsync(() async {
          await loadTestFonts();
          if (Platform.isMacOS) {
            for (final family in [
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              final loader = FontLoader(family)
                ..addFont(
                  File(
                    '/System/Library/Fonts/SFNS.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                );
              await loader.load();
            }
          }
        });
        final c = (await t.runAsync(fixture))!;
        final auth = c.auth as BackupAuth;
        final drive = c.drive as BackupDrive;
        auth.user = Account();
        auth.connected();
        final originalIds = c.families.map((f) => f.id).toSet();
        final before = {
          for (final id in originalIds)
            id: (await t.runAsync(
              () => c.repository.feeds(id),
            ))!.map((f) => f.toJson()).toList(),
        };
        await t.pumpWidget(LittleLogApp(controller: c));
        Future<void> tap(String text) async {
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pumpAndSettle();
          final target = find.text(text).last;
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.runAsync(() async {
            await t.tap(target);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }

        await tap('Settings');
        await tap('Manage baby');
        await tap('Add baby');
        expect(find.text('Google Drive'), findsOneWidget);
        expect(find.text('This device'), findsOneWidget);
        expect(find.text('Create a new baby on this device'), findsNothing);
        if (storage == 'device') {
          await tap('This device');
          expect(
            find.text(
              'Stored only on this device. Deleting the app can delete this log.',
            ),
            findsOneWidget,
          );
        }
        if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../output/add-baby62/${defaultTargetPlatform.name}-$storage-${regular ? 'regular' : 'large'}.png',
            ),
          );
        }
        await t.enterText(find.byType(TextFormField), 'Sam');
        drive.fail = storage == 'drive retry';
        await tap('Create baby log');
        if (storage == 'drive retry') {
          expect(find.byType(OnboardingPage), findsOneWidget);
          expect(c.onboardingSyncedSetup, isTrue);
          expect(c.families.length, 3);
          final pendingId = c.family!.id;
          drive.fail = false;
          await tap('Retry saving to Google Drive');
          expect(c.family!.id, pendingId);
        }
        expect(find.byType(OnboardingPage), findsNothing);
        expect(find.text('Manage baby'), findsWidgets);
        expect(c.family!.babyName, 'Sam');
        expect(c.family!.isLocal, storage == 'device');
        expect(c.families.length, 3);
        expect(c.onboardingSyncedSetup, isFalse);
        expect(drive.creations, storage == 'device' ? 0 : 1);
        expect(drive.rows, isEmpty);
        for (final id in originalIds) {
          expect(c.families.firstWhere((f) => f.id == id).isLocal, isTrue);
          expect(
            (await t.runAsync(
              () => c.repository.feeds(id),
            ))!.map((f) => f.toJson()).toList(),
            before[id],
          );
        }
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(c.repository.db.close);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets(
    'Joining from Add baby opens the shared log without creating a Drive log',
    (t) async {
      final initial = (await t.runAsync(fixture))!;
      initial.dispose();
      final auth = BackupAuth()..ready = true;
      auth.user = Account();
      auth.connected();
      final drive = AddBabyJoinDrive(auth);
      final c = AppController(initial.repository, auth, drive)
        ..family = initial.family
        ..loading = false;
      await t.runAsync(c.refresh);
      await t.pumpWidget(LittleLogApp(controller: c));
      Future<void> tap(Finder target) async {
        await t.ensureVisible(target);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(target);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
      }

      await tap(find.byKey(const ValueKey('baby-switcher')));
      await tap(find.text('Add baby'));
      await tap(find.text('Join an existing baby log'));
      await tap(find.byKey(const ValueKey('available-log-shared-file')));
      await tap(find.text('Join baby log'));
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.text('Switch baby'), findsNothing);
      expect(c.family!.id, 'shared');
      expect(c.families.length, 3);
      expect(c.families.where((f) => f.isLocal).length, 2);
      expect((await t.runAsync(() => c.repository.feeds('family')))!.length, 2);
      expect((await t.runAsync(() => c.repository.feeds('other')))!.length, 1);
      expect(drive.creations, 0);
      expect(drive.writes, 0);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(c.repository.db.close);
    },
  );

  for (final exit in ['back', 'finish later', 'restart']) {
    testWidgets(
      'Failed additional Drive setup can $exit without trapping existing logs',
      (t) async {
        var c = (await t.runAsync(fixture))!;
        final repo = c.repository;
        var auth = c.auth as BackupAuth;
        auth.user = Account();
        auth.connected();
        var drive = c.drive as BackupDrive;
        final originalId = c.family!.id;
        final before = {
          for (final baby in c.families)
            baby.id: (await t.runAsync(
              () => repo.feeds(baby.id, includeDeleted: true),
            ))!.map((row) => row.toJson()).toList(),
        };
        await t.pumpWidget(LittleLogApp(controller: c));
        Future<void> tap(Finder target) async {
          await t.ensureVisible(target);
          await t.pumpAndSettle();
          await t.runAsync(() async {
            await t.tap(target);
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await t.pumpAndSettle();
        }

        await tap(find.byKey(const ValueKey('baby-switcher')));
        await tap(find.text('Add baby'));
        await t.enterText(find.byType(TextFormField), 'Sam');
        drive.fail = true;
        await tap(find.text('Create baby log'));
        expect(c.onboardingSyncedSetup, isTrue);
        expect(c.family!.isLocal, isFalse);
        expect(drive.creations, 1);
        final pending = c.family!;
        if (exit == 'restart') {
          await t.pumpWidget(const SizedBox());
          c.dispose();
          auth = BackupAuth()..ready = true;
          auth.user = Account();
          auth.driveConnected = true;
          drive = BackupDrive(auth)..fail = true;
          c = AppController(repo, auth, drive);
          await t.runAsync(c.initialize);
          await t.pumpWidget(LittleLogApp(controller: c));
          await t.pumpAndSettle();
          expect(c.onboardingSyncedSetup, isTrue);
        }
        if (exit == 'back') {
          await t.runAsync(() async {
            await t.binding.handlePopRoute();
            await Future<void>.delayed(const Duration(milliseconds: 50));
          });
          await t.pumpAndSettle();
        } else {
          await tap(find.text('Finish later'));
        }
        expect(find.byType(OnboardingPage), findsNothing);
        expect(c.onboardingSyncedSetup, isFalse);
        expect(before.keys, contains(c.family!.id));
        if (exit != 'restart') expect(c.family!.id, originalId);
        expect(await t.runAsync(repo.pendingSyncedSetup), isNull);
        expect(await t.runAsync(repo.activeFamilyId), c.family!.id);
        expect(
          c.families.singleWhere((f) => f.id == pending.id).driveFileId,
          pending.driveFileId,
        );
        for (final id in before.keys) {
          expect(
            (await t.runAsync(
              () => repo.feeds(id, includeDeleted: true),
            ))!.map((row) => row.toJson()).toList(),
            before[id],
          );
        }
        // Existing babies remain usable while Drive is still unavailable.
        await t.runAsync(() => c.addDiaper(kind: 'wet', at: DateTime.now()));
        expect(c.feeds.any((r) => r.method == 'diaper'), isTrue);
        final creations = drive.creations;
        drive.fail = false;
        await t.runAsync(() async {
          await c.sync();
          await c.select(pending);
          await c.sync(manual: true);
        });
        expect(c.lastSync, isNotNull);
        expect(c.family!.driveFileId, pending.driveFileId);
        expect(c.families.length, 3);
        expect(drive.creations, creations);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(repo.db.close);
      },
    );
  }

  testWidgets('Add baby cancellation and joining keep existing logs intact', (
    t,
  ) async {
    final c = (await t.runAsync(fixture))!;
    final auth = c.auth as BackupAuth;
    final drive = c.drive as BackupDrive;
    final original = c.family!.id;
    final originalStep = c.onboardingStep;
    await t.pumpWidget(LittleLogApp(controller: c));
    Future<void> tap(String text) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pumpAndSettle();
      final target = find.text(text).last;
      await t.ensureVisible(target);
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(target);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
    }

    await t.tap(find.byKey(const ValueKey('baby-switcher')));
    await t.pumpAndSettle();
    await tap('Add baby');
    expect(find.byType(OnboardingPage), findsOneWidget);
    await t.enterText(find.byType(TextFormField), 'Sam');
    await tap('This device');
    await tap('Google Drive');
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Sam',
    );
    if (AppConfig.configured) {
      auth.cancelSignIn = true;
      await tap('Sign in with Google');
      expect(auth.signIns, 1);
      expect(find.textContaining('canceled'), findsOneWidget);
    }
    await tap('Join an existing baby log');
    expect(find.text('Join a shared log'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('New baby log'), findsOneWidget);
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      'Sam',
    );
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(find.text('Switch baby'), findsOneWidget);
    expect(find.byType(OnboardingPage), findsNothing);
    expect(c.family!.id, original);
    expect(c.onboardingStep, originalStep);
    expect(c.families.length, 2);
    expect(drive.creations, 0);
    expect(drive.writes, 0);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(c.repository.db.close);
  });
}
