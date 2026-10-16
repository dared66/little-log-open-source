import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'support/test_fonts.dart';

void main() {
  for (final method in ['sleep', 'pumping']) {
    testWidgets(
      '$method confirms discard without saving or removing another timer',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        const capture = bool.fromEnvironment('CAPTURE_DISCARD');
        if (capture) await t.runAsync(loadTestFonts);
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = GoogleAuth();
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false;
        await t.runAsync(() async {
          await c.createLocal('Family', 'Robin');
          await c.startActivityTimer('sleep');
          await c.startActivityTimer('pumping');
        });
        final timer = c.timers.singleWhere((timer) => timer.method == method);
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
        expect(find.text('Discard session'), findsOneWidget);
        if (method == 'pumping') {
          expect(find.text('Finish pumping'), findsNothing);
          await t.runAsync(() async {
            await t.tap(find.text('Pause pumping'));
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await t.pumpAndSettle();
          await t.runAsync(() async {
            await t.tap(find.text('Finish pumping'));
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await t.pumpAndSettle();
          expect(find.text('Save pumping'), findsOneWidget);
        }
        if (capture) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../output/discard-session/$method-review.png',
            ),
          );
        }
        await t.tap(find.text('Discard session'));
        await t.pumpAndSettle();
        expect(find.text('Discard $method session?'), findsOneWidget);
        expect(c.timers.any((current) => current.id == timer.id), isTrue);
        if (capture) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../output/discard-session/$method-confirmation.png',
            ),
          );
        }
        await t.tap(find.text('Keep session'));
        await t.pumpAndSettle();
        expect(
          find.text(method == 'pumping' ? 'Save pumping' : 'Finish sleep'),
          findsOneWidget,
        );
        expect(c.timers.any((current) => current.id == timer.id), isTrue);
        await t.tap(find.text('Discard session'));
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(find.widgetWithText(TextButton, 'Discard session').last);
        });
        await t.pumpAndSettle();
        expect(find.text('Save $method'), findsNothing);
        expect(c.timers.single.method, method == 'sleep' ? 'pumping' : 'sleep');
        expect(c.feeds, isEmpty);
        expect(
          (await t.runAsync(
            () => c.repository.activityTimers(timer.familyId),
          ))!.length,
          1,
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }

  test(
    'stale review and changed child cannot discard a different session',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth));
      await c.createLocal('Family', 'Robin');
      await c.startActivityTimer('sleep');
      final old = c.timers.single;
      await c.discardActivityTimer(old);
      await c.startActivityTimer('sleep');
      final replacement = c.timers.single;
      await expectLater(c.discardActivityTimer(old), throwsStateError);
      expect(
        (await c.repository.activityTimers(old.familyId)).single.id,
        replacement.id,
      );
      await c.createLocal('Second family', 'Alex');
      await expectLater(c.discardActivityTimer(replacement), throwsStateError);
      expect(
        (await c.repository.activityTimers(old.familyId)).single.id,
        replacement.id,
      );
      expect(await c.repository.feeds(old.familyId), isEmpty);
      c.dispose();
      await db.close();
    },
  );
}
