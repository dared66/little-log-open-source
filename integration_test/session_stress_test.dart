import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '50 discard/save cycles survive native database restart without orphan timers or duplicate history',
    (t) async {
      final Directory folder = await (await getApplicationSupportDirectory())
          .createTemp('qa-session-stress-');
      final path = '${folder.path}/sessions.db';
      var db = await databaseFactoryIo.openDatabase(path);
      AppController controller() {
        final auth = GoogleAuth();
        return AppController(Repository(db), auth, GoogleDrive(auth));
      }

      var c = controller();
      await c.initialize();
      await c.createLocal('Stress family', 'QA Robin');
      final familyId = c.family!.id;
      var saves = 0;
      for (var cycle = 0; cycle < 50; cycle++) {
        await c.startActivityTimer('sleep');
        await c.startActivityTimer('pumping');
        final discarded = c.timers.singleWhere(
          (timer) => timer.method == 'sleep',
        );
        var saved = c.timers.singleWhere((timer) => timer.method == 'pumping');
        await c.discardActivityTimer(discarded);
        expect(c.timers.single.id, saved.id);
        await expectLater(c.discardActivityTimer(discarded), throwsStateError);
        for (final action in ['pause', 'finish']) {
          await c.performLiveTimerAction(
            sessionId: saved.id,
            familyId: familyId,
            method: 'pumping',
            action: action,
            at: DateTime.now(),
          );
        }
        saved = c.timers.single;
        await c.addActivity(
          method: 'pumping',
          at: saved.startedAt,
          endedAt: saved.stoppedAt,
          amountMl: 60,
          timer: saved,
          expectedFamilyId: familyId,
        );
        saves++;
        expect(c.timers, isEmpty);
        expect(c.feeds.length, saves);
        expect(c.feeds.any((record) => record.id == discarded.id), isFalse);
        c.dispose();
        await db.close();
        db = await databaseFactoryIo.openDatabase(path);
        c = controller();
        await c.initialize();
        expect(c.family!.id, familyId);
        expect(c.timers, isEmpty);
        expect(c.feeds.length, saves);
        expect(c.feeds.map((record) => record.id).toSet().length, saves);
      }
      // A reopened, still-running timer must also be discardable after restart.
      await c.startActivityTimer('sleep');
      final pendingId = c.timers.single.id;
      c.dispose();
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      c = controller();
      await c.initialize();
      expect(c.timers.single.id, pendingId);
      await c.discardActivityTimer(c.timers.single);
      expect(c.timers, isEmpty);
      expect(c.feeds.length, 50);
      c.dispose();
      await db.close();
      await folder.delete(recursive: true);
      expect(t.takeException(), isNull);
    },
  );
  for (final method in ['sleep', 'pumping']) {
    testWidgets('$method native discard persists across reopen at large text', (
      t,
    ) async {
      final support = await getApplicationSupportDirectory();
      final folder = await support.createTemp('qa-discard-ui-');
      final path = '${folder.path}/session.db';
      var db = await databaseFactoryIo.openDatabase(path);
      var auth = GoogleAuth();
      var c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.initialize();
      await c.createLocal('Family', 'QA Robin');
      await c.startActivityTimer(method);
      await t.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: logActionInk,
              primary: logActionInk,
              surface: logBackground,
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openActivity(context, c, method),
                child: const Text('Open session'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Open session'));
      await t.pumpAndSettle();
      if (method == 'pumping') {
        expect(find.text('Finish pumping'), findsNothing);
        await t.tap(find.text('Pause pumping'));
        await t.pumpAndSettle();
        expect(c.timers.single.paused, isTrue);
        await t.tap(find.text('Finish pumping'));
        await t.pumpAndSettle();
        expect(c.timers.single.phase, 'review');
      }
      expect(c.feeds, isEmpty);
      Future<void> capture(String stage) async {
        if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
        if (Platform.isAndroid) {
          await binding.convertFlutterSurfaceToImage();
          await t.pump();
        }
        await binding.takeScreenshot(
          '${Platform.operatingSystem}-$method-$stage',
        );
      }

      await capture('session');
      await t.ensureVisible(find.text('Discard session'));
      await t.tap(find.text('Discard session'));
      await t.pumpAndSettle();
      await capture('confirmation');

      await t.tap(find.text('Keep session'));
      await t.pumpAndSettle();
      expect(c.timers.single.method, method);
      await t.tap(find.text('Discard session'));
      await t.pumpAndSettle();
      await t.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Discard session'),
        ),
      );
      await t.pumpAndSettle();
      expect(c.timers, isEmpty);
      expect(c.feeds, isEmpty);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      auth = GoogleAuth();
      c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.initialize();
      expect(c.timers, isEmpty);
      expect(c.feeds, isEmpty);
      expect(t.takeException(), isNull);
      c.dispose();
      await db.close();
      await folder.delete(recursive: true);
    });
  }
}
