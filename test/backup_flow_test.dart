import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/config.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'manual_sync_test.dart' show Account, Auth, Drive, entry;

class BackupAccount extends Account {
  @override
  String get displayName => 'Robin’s parent';
}

class BackupAuth extends Auth {
  int signIns = 0, authorizations = 0;
  bool previousPermission = false, cancelSignIn = false, denyPermission = false;
  Completer<void>? signInGate;
  @override
  Future<void> signIn() async {
    signIns++;
    await signInGate?.future;
    if (cancelSignIn) throw StateError('Google sign-in canceled.');
    user = BackupAccount();
    driveConnected = previousPermission;
    notifyListeners();
  }

  @override
  Future<void> authorize() async {
    authorizations++;
    if (denyPermission) {
      throw StateError('Google Drive permission was not granted.');
    }
    connected();
  }
}

class BackupDrive extends Drive {
  BackupDrive(super.auth);
  @override
  Future<List<Map<String, String>>> listCollaborators(Family family) async => [
    {'email': 'sample@example.com', 'name': 'Robin’s parent', 'role': 'owner'},
  ];
}

Future<AppController> fixture() async {
  final repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
  final auth = BackupAuth()..ready = true;
  final c = AppController(repo, auth, BackupDrive(auth))..loading = false;
  await repo.saveFamily(
    const Family(id: 'other', name: 'Family', babyName: 'Alex'),
  );
  await repo.add(
    Feeding(
      id: 'other-entry',
      familyId: 'other',
      at: DateTime.utc(2026, 9, 19),
      method: 'bottle',
      amountMl: 120,
    ),
  );
  await repo.saveFamily(
    const Family(id: 'family', name: 'Family', babyName: 'Robin'),
  );
  c.family = (await repo.families()).firstWhere((f) => f.id == 'family');
  await repo.add(entry('existing', synced: true));
  await repo.add(entry('recent'));
  await c.refresh();
  return c;
}

Future<void> verifyBackup(AppController c) async {
  final drive = c.drive as BackupDrive;
  expect(c.family!.id, 'family');
  expect(c.family!.isLocal, false);
  expect(drive.creations, 1);
  expect(drive.rows.keys.toSet(), {'existing', 'recent'});
  expect((await c.repository.feeds('family')).every((e) => e.synced), true);
  expect(
    (await c.repository.families()).firstWhere((f) => f.id == 'other').isLocal,
    true,
  );
  expect((await c.repository.feeds('other')).single.id, 'other-entry');
  expect(c.message, isNull);
}

void main() => runBackupFlow();

void runBackupFlow({bool native = false}) {
  testWidgets(
    'unconfigured build keeps local history and hides backup',
    (t) async {
      final c = (await t.runAsync(fixture))!;
      await t.pumpWidget(
        MaterialApp(
          theme: littleLogTheme(),
          home: Scaffold(body: FamilyPanel(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      expect(
        find.text(
          'Google Drive is unavailable in this build. Entries are stored locally.',
        ),
        findsOneWidget,
      );
      expect(find.text('Back up to Google Drive'), findsNothing);
      expect((c.drive as BackupDrive).creations, 0);
      await t.runAsync(() async {
        expect((await c.repository.feeds('family')).length, 2);
        expect((await c.repository.feeds('other')).single.id, 'other-entry');
      });
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(c.repository.db.close);
    },
    skip: AppConfig.configured,
  );

  for (final state in [
    'signed out',
    'returning account',
    'permission needed',
    'connected',
  ]) {
    test('one backup action: $state; only selected history uploads', () async {
      final c = await fixture();
      final auth = c.auth as BackupAuth;
      auth.previousPermission = state == 'returning account';
      if (state == 'connected' || state == 'permission needed') {
        auth.user = BackupAccount();
      }
      auth.driveConnected = state == 'connected';
      await c.run(c.backUpFamily);
      await verifyBackup(c);
      expect(
        auth.signIns,
        state == 'connected' || state == 'permission needed' ? 0 : 1,
      );
      expect(
        auth.authorizations,
        state == 'returning account' || state == 'connected' ? 0 : 1,
      );
      c.dispose();
      await c.repository.db.close();
    });
  }
  for (final failure in ['cancel', 'permission', 'upload']) {
    test(
      'backup $failure failure preserves history and retries without duplicating Drive file',
      () async {
        final c = await fixture();
        final auth = c.auth as BackupAuth;
        final drive = c.drive as BackupDrive;
        auth.cancelSignIn = failure == 'cancel';
        auth.denyPermission = failure == 'permission';
        drive.fail = failure == 'upload';
        await c.run(c.backUpFamily);
        expect(c.message, isNotNull);
        expect((await c.repository.feeds('family')).length, 2);
        expect(drive.creations, failure == 'upload' ? 1 : 0);
        auth.cancelSignIn = auth.denyPermission = drive.fail = false;
        await c.run(c.backUpFamily);
        await verifyBackup(c);
        c.dispose();
        await c.repository.db.close();
      },
    );
  }
  test('invitation sign-in leaves every device-only log private', () async {
    final c = await fixture();
    await c.auth.signIn();
    await c.auth.authorize();
    await c.sync();
    expect((c.drive as BackupDrive).creations, 0);
    expect((await c.repository.families()).every((f) => f.isLocal), true);
    c.dispose();
    await c.repository.db.close();
  });
  test(
    'selection changed during sign-in never uploads a different log',
    () async {
      final c = await fixture();
      final auth = c.auth as BackupAuth;
      auth.signInGate = Completer<void>();
      final task = c.run(c.backUpFamily);
      c.family = (await c.repository.families()).firstWhere(
        (f) => f.id == 'other',
      );
      auth.signInGate!.complete();
      await task;
      expect((c.drive as BackupDrive).creations, 0);
      expect(c.message, contains('selected log changed'));
      c.dispose();
      await c.repository.db.close();
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      'backup button, progress, retry and sharing ${large ? 'large text' : 'phone'}',
      (t) async {
        if (!native) {
          t.view.physicalSize = large
              ? const Size(320, 568)
              : const Size(390, 844);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
        }
        t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        if (!native && const bool.fromEnvironment('CAPTURE_BACKUP')) {
          for (final font in ['Roboto', 'MaterialIcons']) {
            await (FontLoader(font)..addFont(
                  Future.value(
                    ByteData.sublistView(
                      File(
                        '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                      ).readAsBytesSync(),
                    ),
                  ),
                ))
                .load();
          }
        }
        final c = (await t.runAsync(fixture))!;
        final drive = c.drive as BackupDrive;
        Future<void> settle() async {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await t.pumpAndSettle();
        }

        Future<void> capture(String name) async {
          if (!const bool.fromEnvironment('CAPTURE_BACKUP')) return;
          await t.pump();
          final boundary = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('backup-review')),
          );
          await t.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: native ? 1 : 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final dir = Directory(
              '${Directory.systemTemp.path}/little-log-backup-review',
            );
            await dir.create(recursive: true);
            await File(
              '${dir.path}/$name-${large ? 'large' : 'phone'}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }

        await t.pumpWidget(
          MaterialApp(
            theme: littleLogTheme(),
            home: RepaintBoundary(
              key: const ValueKey('backup-review'),
              child: Scaffold(
                body: SafeArea(child: FamilyPanel(controller: c)),
              ),
            ),
          ),
        );
        await settle();
        final backup = find.text('Back up to Google Drive');
        await t.ensureVisible(backup);
        await settle();
        expect(find.text('Sign in with Google'), findsNothing);
        await t.ensureVisible(find.byKey(const ValueKey('log-storage-card')));
        await settle();
        await capture('01-backup');
        drive.fail = true;
        await t.tap(backup);
        await settle();
        expect(find.text('Retry backup'), findsOneWidget);
        expect(find.text('Drive is offline.'), findsOneWidget);
        await t.ensureVisible(find.text('Retry backup'));
        await settle();
        expect(find.text('Invite a caregiver'), findsNothing);
        await t.ensureVisible(find.byKey(const ValueKey('log-storage-card')));
        await settle();
        await capture('02-retry');
        drive.fail = false;
        drive.uploadGate = Completer<void>();
        await t.tap(find.text('Retry backup'));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pump();
        expect(find.text('Backing up…'), findsOneWidget);
        expect(find.text('Backup incomplete'), findsNothing);
        expect(
          t
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Backing up…'),
              )
              .onPressed,
          isNull,
        );
        await capture('03-uploading');
        drive.uploadGate!.complete();
        await settle();
        await t.runAsync(() => verifyBackup(c));
        expect(find.text('Invite a caregiver'), findsOneWidget);
        await t.ensureVisible(find.byKey(const ValueKey('log-storage-card')));
        await settle();
        await capture('04-backed-up');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(c.repository.db.close);
      },
      skip: !AppConfig.configured,
    );
  }
}
