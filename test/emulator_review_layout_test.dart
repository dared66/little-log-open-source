import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/widgets/activity_flow.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final size in [const Size(320, 568), const Size(844, 390)]) {
      testWidgets(
        'all activity sheets at $size with 200% text in ${mode.name}',
        (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          t.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
          final db = await databaseFactoryMemory.openDatabase(newId.v4());
          final auth = GoogleAuth();
          final c = AppController(Repository(db), auth, GoogleDrive(auth))
            ..loading = false
            ..family = const Family(
              id: 'qa',
              name: 'Family',
              babyName: 'Alexandria Robin',
            );
          await t.runAsync(() => c.setThemeMode(mode));
          await t.pumpWidget(LittleLogApp(controller: c));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'Today');
          for (final method in activityCatalog.keys) {
            openActivity(t.element(find.byType(HomePage)), c, method);
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: method);
            final action = find.byType(FilledButton).last;
            expect(action.hitTestable(), findsOneWidget, reason: method);
            // Android system back must dismiss without saving an empty record.
            await t.binding.handlePopRoute();
            await t.pumpAndSettle();
            expect(c.feeds, isEmpty);
          }
          await t.tap(find.text('Settings').last);
          await t.pumpAndSettle();
          await t.ensureVisible(find.text('Units'));
          await t.tap(find.text('Units'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'Units');
          await t.pumpWidget(const SizedBox());
          c.dispose();
          await db.close();
        },
      );
    }
  }
}
