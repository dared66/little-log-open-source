import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/appearance_page.dart';
import 'package:little_log/widgets/import_page.dart';
import 'package:little_log/widgets/profile_page.dart';
import 'package:little_log/widgets/quick_log_settings_page.dart';
import 'package:little_log/widgets/settings_page.dart';
import 'package:little_log/widgets/summary_settings_page.dart';

void main() {
  for (final size in [const Size(320, 568), const Size(1024, 600)]) {
    testWidgets(
      'settings pages share content bounds and readable titles at $size',
      (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = size.width == 320
            ? 2
            : 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = GoogleAuth()..ready = true;
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false;
        await t.runAsync(() => c.createLocal('QA', 'Alexandria Robin'));
        addTearDown(() async {
          c.dispose();
          await db.close();
        });
        final pages = <String, Widget>{
          'Units': SettingsPage(controller: c),
          'Appearance': AppearancePage(controller: c),
          'Alexandria Robin’s profile': ProfilePage(controller: c),
          'Import and recovery': ImportPage(controller: c),
          'Customize quick log': QuickLogSettingsPage(controller: c),
          'Customize summary': SummarySettingsPage(controller: c),
        };
        for (final entry in pages.entries) {
          await t.pumpWidget(
            MaterialApp(
              theme: littleLogTheme().copyWith(
                platform: TargetPlatform.android,
              ),
              home: entry.value,
            ),
          );
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: entry.key);
          final title = find.descendant(
            of: find.byType(AppBar),
            matching: find.text(entry.key),
          );
          final paragraph = t.renderObject<RenderParagraph>(title);
          expect(
            paragraph.didExceedMaxLines,
            isFalse,
            reason: '${entry.key} must remain readable',
          );
          final body = find
              .descendant(
                of: find.byType(Scaffold),
                matching: find.byType(Scrollable),
              )
              .first;
          final frame = t.getRect(body);
          expect(
            frame.top,
            closeTo(t.getRect(find.byType(AppBar)).bottom, .1),
            reason: '${entry.key} content stays below the toolbar',
          );
          if (size.width > 680) {
            expect(frame.width, lessThanOrEqualTo(680), reason: entry.key);
          }
          if (entry.key == 'Appearance') {
            final cards = find.byType(Card);
            final left = size.width > 680 ? (size.width - 680) / 2 + 20 : 20.0;
            for (final element in cards.evaluate()) {
              final rect = t.getRect(find.byWidget(element.widget));
              expect(rect.left, closeTo(left, .1));
              expect(rect.right, closeTo(size.width - left, .1));
            }
          }
          await t.pumpWidget(const SizedBox());
        }
      },
    );
  }
}
