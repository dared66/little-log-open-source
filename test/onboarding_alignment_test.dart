import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final size in [
      const Size(390, 844),
      const Size(1024, 600),
      const Size(320, 568),
    ]) {
      testWidgets(
        'onboarding shares one content edge on ${platform.name} at $size',
        (t) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          t.platformDispatcher.textScaleFactorTestValue = size.width == 320
              ? 1.8
              : 1;
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final db = (await t.runAsync(
            () => databaseFactoryMemory.openDatabase(newId.v4()),
          ))!;
          final auth = GoogleAuth()..ready = true;
          final c = AppController(Repository(db), auth, GoogleDrive(auth))
            ..loading = false;
          addTearDown(() async {
            c.dispose();
            await db.close();
          });
          await t.pumpWidget(LittleLogApp(controller: c));
          await t.pumpAndSettle();
          final headline = t.getRect(find.text('Baby logs'));
          final title = t.getRect(find.text('Little Log'));
          final next = t.getRect(
            find.widgetWithText(FilledButton, 'New baby log'),
          );
          final join = t.getRect(
            find.widgetWithText(OutlinedButton, 'Join an existing baby log'),
          );
          expect(title.left, closeTo(headline.left, .1));
          for (final rect in [next, join]) {
            expect(rect.left, closeTo(headline.left, .1));
            expect(rect.right, closeTo(headline.right, .1));
          }
          await t.tap(find.text('New baby log'));
          await t.pumpAndSettle();
          final field = t.getRect(find.byType(TextFormField));
          expect(field.left, closeTo(headline.left, .1));
          expect(field.right, closeTo(headline.right, .1));
          await t.ensureVisible(find.text('This device'));
          await t.tap(find.text('This device'));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Create baby log'));
          final save = t.getRect(
            find.widgetWithText(FilledButton, 'Create baby log'),
          );
          expect(save.left, closeTo(headline.left, .1));
          expect(save.right, closeTo(headline.right, .1));
          expect(find.byTooltip('Back'), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
