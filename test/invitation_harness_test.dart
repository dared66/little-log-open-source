import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/invite_caregiver.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'package:little_log/services/invitation_link.dart';
import 'package:sembast/sembast_memory.dart';
import 'google_drive_test.dart' show family, feed;
import 'support/invitation_harness.dart';

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settle(t);
  final matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      matches,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  final target = matches.last;
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await settle(t);
}

Future<void> captureInvitation(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_INVITATIONS')) return;
  await t.pumpAndSettle();
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('invite-review')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('/tmp/little-log-invitation-review');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() => runInvitationHarness();

void runInvitationHarness({bool native = false}) {
  setUpAll(() async {
    if (!const bool.fromEnvironment('CAPTURE_INVITATIONS')) return;
    for (final font in ['Roboto', 'MaterialIcons']) {
      final path =
          '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}';
      await (FontLoader(font)..addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          ))
          .load();
    }
  });
  for (final large in [false, true]) {
    testWidgets(
      'Drive account stays beside sync controls and out of headers (${large ? 'large' : 'standard'} text)',
      (t) async {
        if (!native) {
          t.view.physicalSize = large
              ? const Size(320, 568)
              : const Size(390, 844);
          t.view.devicePixelRatio = 1;
        }
        t.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = HarnessAuth('caregiver@example.com');
        final server = InvitationHarness();
        final identified =
            Family.fromJson({
              ...family.toJson(),
              'accountId': auth.user!.id,
            }).withDriveIdentity(
              email: 'long.owner.address@example.com',
              shared: true,
            );
        final c = AppController(Repository(db), auth, server.client(auth))
          ..family = identified
          ..families = [identified]
          ..loading = false;
        // Native lifecycle resumes refresh from disk; keep the fixture there
        // as well as in memory so a resume cannot erase the selected baby.
        await t.runAsync(() => c.repository.saveFamily(identified));
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('invite-review'),
            child: LittleLogApp(controller: c),
          ),
        );
        await settle(t);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.text(
              'Log’s Drive account: long.owner.address@example.com',
            ),
          ),
          findsNothing,
        );
        await t.scrollUntilVisible(
          find.text('Log’s Drive account: long.owner.address@example.com'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text('Log’s Drive account: long.owner.address@example.com'),
          findsOneWidget,
        );
        final owner = find.text(identified.ownerLabel);
        final refresh = find.text('Refresh');
        expect(refresh, findsOneWidget);
        expect(t.getTopLeft(owner).dy, greaterThan(t.getTopLeft(refresh).dy));
        expect(
          t.getTopLeft(owner).dy -
              t
                  .getBottomLeft(
                    find
                        .ancestor(of: refresh, matching: find.byType(Row))
                        .first,
                  )
                  .dy,
          lessThanOrEqualTo(24),
        );
        await captureInvitation(
          t,
          'sync-footer-${large ? 'large' : 'standard'}',
        );
        await t.tap(find.text('Log'));
        await settle(t);
        expect(
          find.descendant(of: find.byType(AppBar), matching: owner),
          findsNothing,
        );
        await t.tap(find.text('Settings'));
        await settle(t);
        await t.scrollUntilVisible(
          owner,
          300,
          scrollable: find.byType(Scrollable).last,
        );
        expect(owner, findsOneWidget);
        expect(
          find.descendant(of: find.byType(AppBar), matching: owner),
          findsNothing,
        );
        expect(find.text('Refresh'), findsOneWidget);
        await captureInvitation(
          t,
          'settings-footer-${large ? 'large' : 'standard'}',
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }

  testWidgets(
    'same baby name keeps owner and separate history visible before joining',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final server = InvitationHarness()
        ..editors.add('caregiver@example.com')
        ..appAuthorized.add('caregiver@example.com');
      server.file.ownerEmail = 'sender@example.com';
      server.file.shared = true;
      final auth = HarnessAuth('caregiver@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final repo = Repository(db);
      const own = Family(
        id: 'own',
        name: 'Baby',
        babyName: 'Baby',
        driveFileId: 'own123456789',
        accountId: 'caregiver@example.com',
        ownerEmail: 'caregiver@example.com',
        driveShared: false,
      );
      await t.runAsync(() async {
        await repo.saveFamily(own);
        await repo.add(
          Feeding(
            id: 'own-entry',
            familyId: 'own',
            at: DateTime.utc(2026),
            method: 'bottle',
            amountMl: 45,
          ),
        );
      });
      final c = AppController(repo, auth, server.client(auth))
        ..family = own
        ..families = [own]
        ..loading = false;
      var pickerCalls = 0;
      const picker = MethodChannel('app.littlelog/picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (_) async {
            pickerCalls++;
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null),
      );
      await t.pumpWidget(
        MaterialApp(
          home: RepaintBoundary(
            key: const ValueKey('invite-review'),
            child: OnboardingPage(
              controller: c,
              initialStage: OnboardingStage.join,
            ),
          ),
        ),
      );
      await settle(t);
      await t.ensureVisible(find.text('Shared with you'));
      await settle(t);
      expect(find.text('Shared with you'), findsOneWidget);
      expect(find.text('Owner: sender@example.com'), findsOneWidget);
      expect(find.text('Shared by: sender@example.com'), findsNothing);
      expect(find.textContaining('Last updated:'), findsOneWidget);
      await captureInvitation(t, 'available-large');
      await tap(t, 'Baby');
      expect(find.text('Owner: sender@example.com'), findsOneWidget);
      expect(
        find.textContaining('You already have a separate log named Baby'),
        findsOneWidget,
      );
      expect(
        find.textContaining('does not combine or delete entries'),
        findsOneWidget,
      );
      await tap(t, 'Join baby log');
      expect(pickerCalls, 0);
      expect(c.family?.ownerEmail, 'sender@example.com');
      expect((await t.runAsync(repo.families))!.length, 2);
      expect(
        (await t.runAsync(() => repo.feeds('own')))!.single.id,
        'own-entry',
      );
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );

  test(
    'shared permission without app authorization stays invisible and unreadable',
    () async {
      final server = InvitationHarness()..editors.add('caregiver@example.com');
      final drive = server.client(HarnessAuth('caregiver@example.com'));
      expect(await drive.listFamilies(), isEmpty);
      await expectLater(
        drive.openFamily('csv123456789', 'caregiver@example.com'),
        throwsException,
      );
      server.appAuthorized.add('caregiver@example.com');
      expect(
        (await drive.listFamilies()).single['ownerEmail'],
        'sender@example.com',
      );
      expect(
        (await drive.openFamily(
          'csv123456789',
          'caregiver@example.com',
        )).driveFileId,
        'csv123456789',
      );
      drive.dispose();
    },
  );

  for (final alreadyJoined in [false, true]) {
    testWidgets(
      'invitation clears older routes after ${alreadyJoined ? 'open' : 'join'}',
      (t) async {
        final server = InvitationHarness()
          ..editors.add('caregiver@example.com')
          ..appAuthorized.add('caregiver@example.com');
        final auth = HarnessAuth('caregiver@example.com');
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final initial = alreadyJoined
            ? Family.fromJson({...family.toJson(), 'accountId': auth.user!.id})
            : const Family(id: 'local', name: 'Local', babyName: 'Local');
        final c = AppController(Repository(db), auth, server.client(auth))
          ..family = initial
          ..families = [initial]
          ..loading = false;
        await t.runAsync(() => c.repository.saveFamily(initial));
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle(t);
        final navigator = t.state<NavigatorState>(find.byType(Navigator).first);
        navigator.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Older join screen')),
          ),
        );
        await settle(t);
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'app.littlelog/invitation',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(
                  'received',
                  InvitationLink.forFamily(family, auth.user!.email),
                ),
              ),
              (_) {},
            );
        await t.pump();
        await settle(t);
        // Cancelling leaves the prior route intact.
        expect(find.byType(OnboardingPage), findsOneWidget);
        navigator.pop();
        await settle(t);
        expect(find.text('Older join screen'), findsOneWidget);
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              'app.littlelog/invitation',
              const StandardMethodCodec().encodeMethodCall(
                MethodCall(
                  'received',
                  InvitationLink.forFamily(family, auth.user!.email),
                ),
              ),
              (_) {},
            );
        await t.pump();
        await settle(t);
        await tap(t, alreadyJoined ? 'Open log' : 'Continue');
        if (!alreadyJoined) await tap(t, 'Join baby log');
        await settle(t);
        expect(c.family?.driveFileId, family.driveFileId);
        expect(find.text('Older join screen'), findsNothing);
        expect(navigator.canPop(), isFalse);
        expect(find.text('Quick log'), findsOneWidget);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }

  for (final scenario in [
    'direct',
    'authorize',
    'cancel',
    'rate limit',
    'server error',
    'view only',
    'trash',
  ]) {
    testWidgets('exact invitation: $scenario', (t) async {
      final server = InvitationHarness()..editors.add('caregiver@example.com');
      final needsAccess = scenario == 'authorize' || scenario == 'cancel';
      if (!needsAccess) server.appAuthorized.add('caregiver@example.com');
      if (scenario == 'rate limit') server.file.error = 403;
      if (scenario == 'server error') server.file.error = 503;
      if (scenario == 'view only') server.file.canModifyContent = false;
      if (scenario == 'trash') server.file.trashed = true;
      final auth = HarnessAuth('caregiver@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final c = AppController(Repository(db), auth, server.client(auth))
        ..loading = false;
      const invitation = InvitationLink(
        fileId: 'csv123456789',
        invitedEmail: 'caregiver@example.com',
        babyName: 'Baby',
      );
      var pickerCalls = 0;
      const picker = MethodChannel('app.littlelog/picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            pickerCalls++;
            expect(call.arguments['fileId'], invitation.fileId);
            expect(call.arguments['email'], invitation.invitedEmail);
            if (scenario == 'cancel') return null;
            server.appAuthorized.add(invitation.invitedEmail);
            return {
              'fileId': invitation.fileId,
              'accessToken': invitation.invitedEmail,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null),
      );
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            controller: c,
            initialStage: OnboardingStage.join,
            invitation: invitation,
          ),
        ),
      );
      await settle(t);
      await tap(t, 'Continue');
      expect(pickerCalls, needsAccess ? 1 : 0);
      expect(
        find.text('Join baby log'),
        scenario == 'direct' || scenario == 'authorize'
            ? findsOneWidget
            : findsNothing,
      );
      expect(c.family, isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }

  testWidgets('app invitation selects only its file with the invited account', (
    t,
  ) async {
    final server = InvitationHarness()..editors.add('caregiver@example.com');
    server.file.ownerEmail = 'sender@example.com';
    server.file.shared = true;
    final auth = HarnessAuth('wrong@example.com');
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final c = AppController(Repository(db), auth, server.client(auth))
      ..loading = false;
    const invitation = InvitationLink(
      fileId: 'csv123456789',
      invitedEmail: 'caregiver@example.com',
      babyName: 'Baby',
    );
    const picker = MethodChannel('app.littlelog/picker');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(picker, (call) async {
          expect(call.arguments['fileId'], invitation.fileId);
          expect(call.arguments['email'], invitation.invitedEmail);
          server.appAuthorized.add(invitation.invitedEmail);
          return {
            'fileId': invitation.fileId,
            'accessToken': invitation.invitedEmail,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, null),
    );
    await t.pumpWidget(
      MaterialApp(
        home: OnboardingPage(
          controller: c,
          initialStage: OnboardingStage.join,
          invitation: invitation,
        ),
      ),
    );
    await settle(t);
    expect(
      find.textContaining('Switch to caregiver@example.com'),
      findsOneWidget,
    );
    expect(find.text('Shared log’s Google Drive link'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(
      t
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Switch account'),
          )
          .onPressed,
      isNotNull,
    );
    auth.use('caregiver@example.com');
    await settle(t);
    await tap(t, 'Continue');
    expect(find.text('Owner: sender@example.com'), findsOneWidget);
    await tap(t, 'Join baby log');
    expect(c.family?.driveFileId, invitation.fileId);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  testWidgets(
    'unavailable shared log explains account and authorization recovery',
    (t) async {
      final server = InvitationHarness()
        ..editors.add('caregiver@example.com')
        ..appAuthorized.add('caregiver@example.com');
      final auth = HarnessAuth('caregiver@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final c = AppController(Repository(db), auth, server.client(auth))
        ..loading = false;
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            controller: c,
            initialStage: OnboardingStage.join,
          ),
        ),
      );
      await settle(t);
      expect(find.text('caregiver@example.com'), findsOneWidget);
      for (final status in [403, 404]) {
        server.file.error = status;
        await tap(t, 'Baby');
        expect(
          find.textContaining(
            'This log could not be opened with caregiver@example.com',
          ),
          findsOneWidget,
        );
        expect(c.family, isNull);
      }
      server.file.error = null;
      await tap(t, 'Baby');
      expect(find.text('Join baby log'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );

  testWidgets(
    'sender email → receiver selection → confirmation → shared history',
    (t) async {
      final server = InvitationHarness();
      server.file.contents = FamilyCsv(family, [
        feed('before-invite', note: 'Existing history'),
      ]).encode();
      final senderAuth = HarnessAuth('sender@example.com');
      final senderDb = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final sender = AppController(
        Repository(senderDb),
        senderAuth,
        server.client(senderAuth),
      )..family = family;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: InviteCaregiverForm(controller: sender, family: family),
            ),
          ),
        ),
      );
      await tap(t, 'Send invitation');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(server.invitations, isEmpty);
      await t.enterText(find.byType(TextFormField), 'caregiver@example.com');
      server.gate = Completer<void>();
      await t.tap(find.text('Send invitation'));
      await t.pump();
      expect(find.text('Sending invitation…'), findsOneWidget);
      expect(
        t.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      server.gate!.complete();
      server.gate = null;
      await settle(t);
      expect(server.invitations.length, 1);
      final message =
          server.invitations.single.url.queryParameters['emailMessage']!;
      expect(message, contains('sender@example.com invited you to Baby'));
      expect(message, contains('Little Log'));
      expect(message, contains('Sign in with caregiver@example.com'));
      expect(message, contains('Join baby log'));
      expect(
        message,
        contains(InvitationLink.forFamily(family, 'caregiver@example.com')),
      );
      expect(message, isNot(contains('Browse shared logs')));
      expect(message, isNot(contains('select this log')));
      expect(message.length, lessThan(1000));
      expect(find.text('Share invitation'), findsOneWidget);
      expect(find.textContaining('Optional —'), findsNothing);
      expect(find.byTooltip('More ways to send'), findsOneWidget);
      expect(find.text('caregiver@example.com'), findsOneWidget);
      expect(
        server.invitations.single.url.queryParameters['sendNotificationEmail'],
        'true',
      );
      const sharing = MethodChannel('app.littlelog/invitation');
      String? sharedMessage;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(sharing, (call) async {
            if (call.method == 'listen') return null;
            expect(call.method, 'share');
            sharedMessage = call.arguments['message'] as String;
            throw PlatformException(code: 'share_unavailable');
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(sharing, null),
      );
      await tap(t, 'Share invitation');
      final appLink = sharedMessage!
          .split('\n')
          .firstWhere((line) => line.startsWith('littlelog://'));
      final parsed = InvitationLink.parse(appLink)!;
      expect(parsed.fileId, family.driveFileId);
      expect(parsed.invitedEmail, 'caregiver@example.com');
      expect(
        sharedMessage,
        contains('https://drive.google.com/file/d/${family.driveFileId}/view'),
      );
      expect(
        find.textContaining('The share sheet could not open'),
        findsOneWidget,
      );
      await t.tap(find.byTooltip('More ways to send'));
      await settle(t);
      expect(find.text('Copy invitation'), findsOneWidget);
      await tap(t, 'Copy invitation');
      expect(find.text('Invitation sent'), findsOneWidget);

      final auth = HarnessAuth('caregiver@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final repo = Repository(db);
      final c = AppController(repo, auth, server.client(auth))..loading = false;
      await t.pumpWidget(LittleLogApp(controller: c));
      await tap(t, 'Join an existing baby log');
      await settle(t);
      expect(
        find.text('Baby'),
        findsNothing,
      ); // Sharing alone grants no app access.
      expect(server.appAuthorized, isNot(contains('caregiver@example.com')));
      const picker = MethodChannel('app.littlelog/picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            expect(call.arguments['email'], 'caregiver@example.com');
            expect(call.arguments['fileId'], 'csv123456789');
            server.appAuthorized.add('caregiver@example.com');
            return {
              'fileId': 'csv123456789',
              'accessToken': 'caregiver@example.com',
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null),
      );
      await t.scrollUntilVisible(
        find.text('Shared log’s Google Drive link'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.enterText(
        find.byType(TextField),
        'https://drive.google.com/file/d/csv123456789/view',
      );
      await tap(t, 'Open log');
      expect(c.family, isNull);
      expect(find.text('Join baby log'), findsOneWidget);
      server.gate = Completer<void>();
      await t.ensureVisible(find.text('Join baby log'));
      await t.tap(find.text('Join baby log'));
      await t.pump();
      expect(find.text('Loading shared history…'), findsOneWidget);
      expect(c.family, isNull);
      server.gate!.complete();
      server.gate = null;
      await settle(t);
      expect(c.family?.id, family.id);
      expect(c.joiningFromOnboarding, isFalse);
      expect(
        (await t.runAsync(() => repo.feeds(family.id)))!.single.note,
        'Existing history',
      );
      expect(find.text('Join baby log'), findsNothing);
      // Receiver writes the same shared file; owner reads it through another client.
      await t.runAsync(() async {
        await repo.add(feed('receiver-entry'));
        await c.sync(manual: true);
        expect(
          (await sender.drive.readFeeds(family)).feeds.map((f) => f.id),
          containsAll(['before-invite', 'receiver-entry']),
        );
      });
      await t.pumpWidget(const SizedBox());
      sender.dispose();
      c.dispose();
      await t.runAsync(() async {
        await senderDb.close();
        await db.close();
      });
    },
  );

  testWidgets(
    'search failure stays visible, retries once, wrong account and switching recover',
    (t) async {
      final server = InvitationHarness()..listError = 503;
      final auth = HarnessAuth('wrong@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final c = AppController(Repository(db), auth, server.client(auth))
        ..loading = false;
      await t.pumpWidget(
        MaterialApp(
          home: OnboardingPage(
            controller: c,
            initialStage: OnboardingStage.join,
          ),
        ),
      );
      await settle(t);
      expect(server.searches, 1);
      await t.scrollUntilVisible(
        find.text('Try again'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Try again'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      expect(server.searches, 1);
      server.listError = null;
      await tap(t, 'Try again');
      await t.scrollUntilVisible(
        find.textContaining('No baby logs available yet'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('No baby logs available yet'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Use a different Google account'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(t, 'Use a different Google account');
      expect(find.text('wrong@example.com'), findsNothing);
      server.editors.add('caregiver@example.com');
      server.appAuthorized.add('caregiver@example.com');
      auth.use('caregiver@example.com');
      await settle(t);
      expect(find.text('caregiver@example.com'), findsOneWidget);
      await tap(t, 'Baby');
      await tap(t, 'Back to shared logs');
      expect(c.family, isNull);
      expect(find.text('Join baby log'), findsNothing);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      '${native ? 'native phone' : 'small phone'} ${large ? 'large text' : 'standard text'} sender and receiver',
      (t) async {
        if (!native) {
          t.view.physicalSize = const Size(320, 568);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
        }
        final server = InvitationHarness();
        final auth = HarnessAuth('sender@example.com');
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final c = AppController(Repository(db), auth, server.client(auth))
          ..loading = false;
        await t.pumpWidget(LittleLogApp(controller: c));
        final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).theme;
        Widget app(Widget child) => RepaintBoundary(
          key: const ValueKey('invite-review'),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(large ? 2 : 1)),
              child: child!,
            ),
            home: child,
          ),
        );
        await t.pumpWidget(
          app(
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: InviteCaregiverForm(controller: c, family: family),
              ),
            ),
          ),
        );
        await captureInvitation(t, 'sender-${large ? 'large' : 'standard'}');
        await t.enterText(find.byType(TextFormField), 'caregiver@example.com');
        await tap(t, 'Send invitation');
        expect(find.text('Invitation sent'), findsOneWidget);
        await captureInvitation(t, 'sent-${large ? 'large' : 'standard'}');
        expect(t.takeException(), isNull);
        await t.pumpWidget(
          app(
            OnboardingPage(controller: c, initialStage: OnboardingStage.join),
          ),
        );
        await settle(t);
        await t.scrollUntilVisible(
          find.text('Baby'),
          180,
          scrollable: find.byType(Scrollable).first,
        );
        await captureInvitation(t, 'available-${large ? 'large' : 'standard'}');
        await tap(t, 'Baby');
        await t.ensureVisible(find.text('Join baby log'));
        await captureInvitation(t, 'join-${large ? 'large' : 'standard'}');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }

  test(
    'failed joins are atomic, retry and duplicate join preserve local history',
    () async {
      final server = InvitationHarness()
        ..file.contents = FamilyCsv(family, [feed('remote')]).encode();
      server.editors.add('caregiver@example.com');
      server.appAuthorized.add('caregiver@example.com');
      final auth = HarnessAuth('caregiver@example.com');
      final repo = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      const local = Family(id: 'local', name: 'Local', babyName: 'Robin');
      await repo.saveFamily(local);
      await repo.add(
        Feeding(
          id: 'local-entry',
          familyId: 'local',
          at: DateTime.utc(2026),
          method: 'bottle',
          amountMl: 80,
        ),
      );
      final c = AppController(repo, auth, server.client(auth));
      await c.initialize();
      server.file.error = 503;
      await expectLater(c.join('csv123456789'), throwsException);
      expect(c.family?.id, 'local');
      expect(await repo.activeFamilyId(), 'local');
      expect((await repo.families()).length, 1);
      expect((await repo.feeds('local')).length, 1);
      server.file.error = null;
      c.onboardingSyncedSetup = true;
      await c.join('csv123456789');
      expect(c.onboardingSyncedSetup, isFalse);
      await repo.add(feed('pending'));
      await c.join('csv123456789');
      expect((await repo.families()).length, 2);
      expect(
        (await repo.families()).firstWhere((f) => f.id == 'local').isLocal,
        isTrue,
      );
      expect(
        (await repo.feeds('family')).map((f) => f.id),
        containsAll(['remote', 'pending']),
      );
      expect(
        (await repo.feeds(
          'family',
        )).firstWhere((f) => f.id == 'pending').synced,
        isFalse,
      );
      expect(server.file.writes, 0);
      c.dispose();
      await repo.db.close();
    },
  );

  test(
    'revoked access, malformed file, changed account and capacity never select partial baby',
    () async {
      final server = InvitationHarness();
      final auth = HarnessAuth('caregiver@example.com');
      final repo = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      final c = AppController(repo, auth, server.client(auth))..loading = false;
      await expectLater(c.join('csv123456789'), throwsException);
      server.editors.add('caregiver@example.com');
      server.appAuthorized.add('caregiver@example.com');
      server.file.contents = 'not a Little Log file';
      await expectLater(c.join('csv123456789'), throwsFormatException);
      server.file.contents = FamilyCsv(family, []).encode();
      server.file.version++;
      server.gate = Completer<void>();
      final pending = c.join('csv123456789');
      await Future<void>.delayed(Duration.zero);
      auth.use('sender@example.com');
      server.gate!.complete();
      server.gate = null;
      await expectLater(pending, throwsStateError);
      expect(await repo.families(), isEmpty);
      expect(c.family, isNull);
      for (var i = 0; i < 3; i++) {
        await repo.saveFamily(
          Family(id: 'baby-$i', name: 'Local', babyName: 'Baby $i'),
        );
      }
      await expectLater(c.join('csv123456789'), throwsStateError);
      expect((await repo.families()).length, 3);
      expect(await repo.activeFamilyId(), 'baby-2');
      c.dispose();
      await repo.db.close();
    },
  );
  testWidgets('sender failure retains address and supports retry', (t) async {
    final server = InvitationHarness()..inviteError = 403;
    final auth = HarnessAuth('sender@example.com');
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final c = AppController(Repository(db), auth, server.client(auth));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: InviteCaregiverForm(controller: c, family: family),
          ),
        ),
      ),
    );
    await t.enterText(find.byType(TextFormField), '  caregiver@example.com  ');
    await tap(t, 'Send invitation');
    expect(find.text('Invitation sent'), findsNothing);
    expect(find.textContaining('Google denied this request'), findsOneWidget);
    expect(
      t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '  caregiver@example.com  ',
    );
    server.inviteError = null;
    await tap(t, 'Send invitation');
    expect(find.text('Invitation sent'), findsOneWidget);
    expect(server.editors, contains('caregiver@example.com'));
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  testWidgets('join failure remains on confirmation and retry completes', (
    t,
  ) async {
    final server = InvitationHarness();
    final auth = HarnessAuth('sender@example.com');
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final repo = Repository(db);
    final c = AppController(repo, auth, server.client(auth))..loading = false;
    await t.pumpWidget(LittleLogApp(controller: c));
    await tap(t, 'Join an existing baby log');
    await tap(t, 'Baby');
    server.file.error = 503;
    await tap(t, 'Join baby log');
    expect(c.family, isNull);
    expect(c.joiningFromOnboarding, isFalse);
    expect((await t.runAsync(repo.families))!, isEmpty);
    expect(find.text('Join baby log', skipOffstage: false), findsOneWidget);
    server.file.error = null;
    await tap(t, 'Join baby log');
    expect(c.family?.id, family.id);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  test('view-only access and changed confirmed baby are rejected', () async {
    final server = InvitationHarness()..file.canModifyContent = false;
    final auth = HarnessAuth('sender@example.com');
    final repo = Repository(
      await databaseFactoryMemory.openDatabase(newId.v4()),
    );
    final c = AppController(repo, auth, server.client(auth))..loading = false;
    await expectLater(
      c.join('csv123456789'),
      throwsA(predicate((e) => e.toString().contains('Editor access'))),
    );
    server.file.canModifyContent = true;
    await expectLater(
      c.join('csv123456789', expectedFamilyId: 'other-baby'),
      throwsStateError,
    );
    expect(await repo.families(), isEmpty);
    c.dispose();
    await repo.db.close();
  });

  test(
    'transaction rolls back earlier rows on conflict and preserves local deletion',
    () async {
      final repo = Repository(
        await databaseFactoryMemory.openDatabase(newId.v4()),
      );
      await repo.saveFamily(family);
      await repo.add(feed('conflict', note: 'local'));
      await expectLater(
        repo.joinFamily(family, [
          feed('new'),
          feed('conflict', note: 'remote'),
        ]),
        throwsFormatException,
      );
      expect((await repo.feeds(family.id)).map((f) => f.id), ['conflict']);
      await repo.add(feed('deleted').asDeleted());
      await repo.joinFamily(family, [feed('deleted')]);
      expect(
        (await repo.feeds(
          family.id,
          includeDeleted: true,
        )).firstWhere((f) => f.id == 'deleted').deleted,
        isTrue,
      );
      await repo.db.close();
    },
  );
}
