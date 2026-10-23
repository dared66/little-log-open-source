import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/invitation_link.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/invite_caregiver.dart';
import 'package:little_log/widgets/onboarding.dart';
import 'package:sembast/sembast_memory.dart';
import '../test/google_drive_test.dart' show family;
import '../test/support/invitation_harness.dart';
import '../test/invitation_harness_test.dart'
    show tap, settle, captureInvitation;

void main() {
  for (final large in [false, true]) {
    testWidgets('sharing review ${large ? 'large' : 'standard'}', (t) async {
      t.view.physicalSize = Size(large ? 320 : 390, large ? 568 : 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (final font in ['Roboto', 'MaterialIcons']) {
        final path =
            '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}';
        await (FontLoader(font)..addFont(
              Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
            ))
            .load();
      }
      final server = InvitationHarness();
      server.file.ownerEmail = 'sender@example.com';
      server.file.shared = true;
      final auth = HarnessAuth('sender@example.com');
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final c = AppController(Repository(db), auth, server.client(auth))
        ..loading = false;
      await t.pumpWidget(LittleLogApp(controller: c));
      final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).theme;
      Widget wrap(Widget page) => RepaintBoundary(
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
          home: page,
        ),
      );
      Future<void> shot(String name) async {
        await captureInvitation(
          t,
          'redesign-${large ? 'large' : 'standard'}-$name',
        );
        expect(t.takeException(), isNull);
      }

      await t.pumpWidget(
        wrap(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InviteCaregiverPage(controller: c, family: family),
                    ),
                  ),
                  child: const Text('Open invitation'),
                ),
              ),
            ),
          ),
        ),
      );
      await tap(t, 'Open invitation');
      await tap(t, 'Send invitation');
      await shot('validation');
      await t.enterText(find.byType(TextFormField), 'caregiver@example.com');
      FocusManager.instance.primaryFocus?.unfocus();
      await shot('1-invite');
      server.inviteError = 503;
      await tap(t, 'Send invitation');
      await shot('send-error');
      server.inviteError = null;
      await tap(t, 'Send invitation');
      await shot('2-sent');
      await tap(t, 'Done');
      expect(find.text('Open invitation'), findsOneWidget);
      auth.use('wrong@example.com');
      final invitation = InvitationLink.parse(
        InvitationLink.forFamily(family, 'caregiver@example.com'),
      )!;
      await t.pumpWidget(
        wrap(
          OnboardingPage(
            controller: c,
            initialStage: OnboardingStage.join,
            invitation: invitation,
          ),
        ),
      );
      await settle(t);
      await shot('3-account');
      await auth.signOut();
      await settle(t);
      await shot('signed-out');
      auth.use('caregiver@example.com');
      await settle(t);
      await shot('4-continue');
      const picker = MethodChannel('app.littlelog/picker');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(picker, (call) async {
            server.appAuthorized.add('caregiver@example.com');
            return {
              'fileId': family.driveFileId,
              'accessToken': 'caregiver@example.com',
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(picker, null),
      );
      await tap(t, 'Continue');
      await t.ensureVisible(find.text('Join baby log'));
      await shot('5-confirm');
      expect(find.text('Continue'), findsNothing);
      await tap(t, 'Join baby log');
      expect(c.family?.id, family.id);
      await t.pumpWidget(
        wrap(
          OnboardingPage(
            key: const ValueKey('manual-join'),
            controller: c,
            initialStage: OnboardingStage.join,
          ),
        ),
      );
      await settle(t);
      await shot('manual-join');
      await t.ensureVisible(find.text('Baby'));
      await shot('available-logs');
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }
}
