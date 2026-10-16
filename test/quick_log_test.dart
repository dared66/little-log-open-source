import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;

void main() {
  testWidgets('quick log adds two choices, enforces six, and updates Today', (
    t,
  ) async {
    const capture = bool.fromEnvironment('CAPTURE_QUICK_LOG');
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    if (capture) {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      for (final font in [
        'Roboto',
        'MaterialIcons',
        'CupertinoSystemText',
        'CupertinoSystemDisplay',
      ]) {
        await (FontLoader(font)..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    font.startsWith('Cupertino')
                        ? '/System/Library/Fonts/SFNS.ttf'
                        : '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                  ).readAsBytesSync(),
                ),
              ),
            ))
            .load();
      }
    }
    Future<void> shot(String name) async {
      if (!capture) return;
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../output/quick-log-screenshots/$name.png'),
      );
    }

    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final repo = Repository(db);
    final auth = GoogleAuth();
    final controller = AppController(repo, auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => controller.createLocal('Family', 'Robin'));
    addTearDown(() async {
      controller.dispose();
      await db.close();
    });
    await t.pumpWidget(LittleLogApp(controller: controller));
    await t.pumpAndSettle();

    expect(controller.quickLog, defaultQuickLog);
    await shot('01-today-default');
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('quick-log-heading')),
        matching: find.text('Customize'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Max 6'), findsNothing);
    await shot('02-customize-default');
    await t.drag(
      find.byKey(const ValueKey('quick-log-move-pumping')),
      Offset(
        0,
        t
                .getBottomLeft(
                  find.byKey(const ValueKey('quick-log-selected-sleep')),
                )
                .dy -
            4 -
            t
                .getCenter(find.byKey(const ValueKey('quick-log-move-pumping')))
                .dy,
      ),
    );
    await t.pumpAndSettle();
    expect(controller.quickLog, contains('pumping'));
    await t.tap(find.byKey(const ValueKey('quick-log-add-solids')));
    await t.pumpAndSettle();
    expect(controller.quickLog.length, 6);
    expect(find.text('Max 6'), findsOneWidget);
    final statusRow = find
        .ancestor(of: find.text('Max 6'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: statusRow, matching: find.text('In your quick log')),
      findsOneWidget,
    );
    expect(await t.runAsync(repo.quickLog), controller.quickLog);
    expect(
      t
          .widget<ListTile>(find.byKey(const ValueKey('quick-log-add-growth')))
          .enabled,
      isFalse,
    );
    await shot('03-customize-six');

    await t.drag(
      find.byKey(const ValueKey('quick-log-move-solids')),
      Offset(
        0,
        t
                .getCenter(
                  find.byKey(const ValueKey('quick-log-selected-pumping')),
                )
                .dy -
            8 -
            t.getCenter(find.byKey(const ValueKey('quick-log-move-solids'))).dy,
      ),
    );
    await t.pumpAndSettle();
    expect(controller.quickLog[4], 'solids');
    expect(await t.runAsync(repo.quickLog), controller.quickLog);
    await shot('04-customize-reordered');

    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('Pumping'), findsOneWidget);
    expect(find.text('Solids'), findsOneWidget);
    await shot('05-today-six-reordered');
    if (capture) debugDefaultTargetPlatformOverride = null;

    await t.scrollUntilVisible(
      find.widgetWithText(TextButton, 'See all activities'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text('See all activities'));
    await t.pumpAndSettle();
    expect(find.text('Log an activity'), findsOneWidget);
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();

    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    expect(find.text('Quick log'), findsNothing);
    expect(find.textContaining('Default volume:'), findsNothing);
    await t.tap(find.text('Log').last);
    await t.pumpAndSettle();
    // Native ListView drops offscreen children after preserving scroll position.
    await t.scrollUntilVisible(
      find.descendant(
        of: find.byKey(const ValueKey('quick-log-heading')),
        matching: find.text('Customize'),
      ),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(
      find.descendant(
        of: find.byKey(const ValueKey('quick-log-heading')),
        matching: find.text('Customize'),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Customize quick log'), findsOneWidget);
    await t.drag(
      find.byKey(const ValueKey('quick-log-move-bottle')),
      const Offset(0, 560),
    );
    await t.pumpAndSettle();
    expect(controller.quickLog, isNot(contains('bottle')));
    expect(find.text('Max 6'), findsNothing);
    expect(await t.runAsync(repo.quickLog), controller.quickLog);
    expect(find.byKey(const ValueKey('quick-log-add-bottle')), findsOneWidget);
    await t.ensureVisible(find.byKey(const ValueKey('quick-log-add-bottle')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('quick-log-add-bottle')));
    await t.pumpAndSettle();
    expect(controller.quickLog, contains('bottle'));

    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await t.pumpAndSettle();
    await shot('06-customize-small-large-text');
    await t.scrollUntilVisible(
      find.byKey(const ValueKey('quick-log-add-growth')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
