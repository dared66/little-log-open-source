import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart';
import 'manual_sync_test.dart' show Drive;
import 'support/invitation_harness.dart' show HarnessAuth;

class SharingDrive extends Drive {
  SharingDrive(super.auth);
  Future<List<Map<String, String>>> Function(Family) lookup = (_) async => [
    {'email': 'owner@example.com', 'name': 'Owner', 'role': 'owner'},
    {'email': 'caregiver@example.com', 'name': 'Caregiver', 'role': 'writer'},
  ];
  @override
  Future<List<Map<String, String>>> listCollaborators(Family family) =>
      lookup(family);
}

Family log(String id, String account) => Family(
  id: id,
  name: 'Family',
  babyName: id,
  driveFileId: 'file-$id',
  accountId: account,
  // Deliberately stale cached identity must never enable invitations.
  ownerEmail: account,
);

Future<AppController> controller(String account) async {
  final repo = Repository(await databaseFactoryMemory.openDatabase(newId.v4()));
  final auth = HarnessAuth(account);
  final c = AppController(repo, auth, SharingDrive(auth))..loading = false;
  await repo.saveFamily(log('Robin', account));
  await repo.setLastSync('Robin', DateTime.utc(2026, 10, 20));
  c.family = (await repo.families()).single;
  await c.refresh();
  return c;
}

Future<void> showPanel(WidgetTester t, AppController c) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: FamilyPanel(controller: c)),
    ),
  );
  await settle(t);
}

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 30)),
  );
  await t.pumpAndSettle();
}

Future<void> close(WidgetTester t, AppController c) async {
  await t.pumpWidget(const SizedBox());
  c.dispose();
  await t.runAsync(c.repository.db.close);
}

void main() {
  for (final account in ['owner@example.com', 'caregiver@example.com']) {
    testWidgets('$account gets only its actual sharing permissions', (t) async {
      final c = (await t.runAsync(() => controller(account)))!;
      await showPanel(t, c);
      final expected = account.startsWith('owner')
          ? findsOneWidget
          : findsNothing;
      expect(find.text('Invite a caregiver'), expected);
      expect(find.text('Manage access in Google Drive'), expected);
      expect(find.text('People with access to Robin'), findsOneWidget);
      await close(t, c);
    });
  }

  testWidgets('failed ownership refresh removes invitation controls', (
    t,
  ) async {
    final c = (await t.runAsync(() => controller('owner@example.com')))!;
    await showPanel(t, c);
    expect(find.text('Invite a caregiver'), findsOneWidget);
    (c.drive as SharingDrive).lookup = (_) async => throw StateError('Offline');
    await t.ensureVisible(find.byTooltip('Refresh sharing list'));
    await t.tap(find.byTooltip('Refresh sharing list'));
    await settle(t);
    expect(find.text('Invite a caregiver'), findsNothing);
    expect(find.text('Manage access in Google Drive'), findsNothing);
    await close(t, c);
  });

  testWidgets('late owner response cannot enable invitations on another log', (
    t,
  ) async {
    final c = (await t.runAsync(() => controller('owner@example.com')))!;
    final pending = Completer<List<Map<String, String>>>();
    final drive = c.drive as SharingDrive;
    drive.lookup = (f) => f.id == 'Robin'
        ? pending.future
        : Future.value([
            {
              'email': 'another@example.com',
              'name': 'Another owner',
              'role': 'owner',
            },
          ]);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FamilyPanel(controller: c)),
      ),
    );
    await t.pump();
    expect(find.text('Invite a caregiver'), findsNothing);
    await t.runAsync(() async {
      final second = log('Alex', 'owner@example.com');
      await c.repository.saveFamily(second);
      await c.repository.setLastSync(second.id, DateTime.utc(2026, 10, 20));
      c.family = second;
      await c.refresh();
    });
    await t.pump();
    await settle(t);
    pending.complete([
      {'email': 'owner@example.com', 'name': 'Owner', 'role': 'owner'},
    ]);
    await settle(t);
    expect(find.text('People with access to Alex'), findsOneWidget);
    expect(find.text('Invite a caregiver'), findsNothing);
    await close(t, c);
  });

  testWidgets('switching accounts clears the previous owner permission', (
    t,
  ) async {
    final c = (await t.runAsync(() => controller('owner@example.com')))!;
    await showPanel(t, c);
    expect(find.text('Invite a caregiver'), findsOneWidget);
    await t.runAsync(() async {
      (c.auth as HarnessAuth).use('caregiver@example.com');
      c.family = log('Robin', 'caregiver@example.com');
      await c.repository.saveFamily(c.family!);
      await c.refresh();
    });
    await t.pump();
    await settle(t);
    expect(find.text('Invite a caregiver'), findsNothing);
    expect(find.text('Manage access in Google Drive'), findsNothing);
    await close(t, c);
  });
}
