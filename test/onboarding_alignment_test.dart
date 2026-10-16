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
          final headline = t.getRect(
            find.text('Less remembering. More caring.'),
          );
          final title = t.getRect(find.text('Little Log'));
          final card = t.getRect(find.byType(Card));
          final next = t.getRect(find.widgetWithText(FilledButton, 'Next'));
          expect(title.left, closeTo(headline.left, .1));
          expect(card.left, closeTo(headline.left, .1));
          expect(card.right, closeTo(headline.right, .1));
          expect(next.left, closeTo(headline.left, .1));
          expect(next.right, closeTo(headline.right, .1));
          expect(
            t.getTopRight(find.text('Skip introduction')).dx,
            closeTo(headline.right, .1),
          );
          await t.tap(find.text('Skip introduction'));
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Set up my baby'));
          await t.tap(find.text('Set up my baby'));
          await t.pumpAndSettle();
          final choices = find.byType(Card);
          for (final choice in choices.evaluate()) {
            final rect = t.getRect(find.byWidget(choice.widget));
            expect(rect.left, closeTo(headline.left, .1));
            expect(rect.right, closeTo(headline.right, .1));
          }
          expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          debugDefaultTargetPlatformOverride = null;
        },
      );
    }
  }
}
