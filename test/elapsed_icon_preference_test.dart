import 'package:flutter/material.dart';
import 'support/scroll_to.dart';
import 'support/test_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/quick_log.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/widgets/activity_glyph.dart';
import 'package:little_log/widgets/elapsed_activity_glyph.dart';
import 'package:little_log/widgets/seam_elapsed_glyph.dart';
import 'package:little_log/widgets/activity_launch_icon.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;

Future<AppController> localController(WidgetTester t) async {
  final db = (await t.runAsync(
    () => databaseFactoryMemory.openDatabase(newId.v4()),
  ))!;
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth))
    ..loading = false;
  await t.runAsync(() => c.createLocal('Sample family', 'Robin'));
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

Finder customize() => find.descendant(
  of: find.byKey(const ValueKey('quick-log-heading')),
  matching: find.text('Customize'),
);

void main() {
  test(
    'elapsed labels distinguish missing history, now and the one-day cap',
    () {
      expect(QuickLogElapsedTime.textFor(null), '—');
      expect(QuickLogElapsedTime.textFor(Duration.zero), 'Just now');
      expect(
        QuickLogElapsedTime.textFor(const Duration(minutes: 35)),
        '35m ago',
      );
      expect(
        QuickLogElapsedTime.textFor(const Duration(minutes: 80)),
        '1h 20m ago',
      );
      expect(QuickLogElapsedTime.textFor(const Duration(days: 1)), '1 day ago');
      expect(
        QuickLogElapsedTime.textFor(const Duration(hours: 25)),
        '>1 day ago',
      );
    },
  );

  testWidgets(
    'elapsed buttons keep regular icons and put time beneath the label without growing',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.runAsync(loadTestFonts);
      final c = await localController(t);
      await t.runAsync(
        () => c.setQuickLog([
          'bottle',
          'nursing',
          'diaper',
          'sleep',
          'pumping',
          'solids',
        ]),
      );
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      final ordinary = {
        for (final method in c.quickLog)
          method: t.getSize(find.byKey(ValueKey('quick-log-button-$method'))),
      };
      await t.runAsync(() => c.setShowElapsedInIcons(true));
      await t.pumpAndSettle();
      for (final method in c.quickLog) {
        final size = t.getSize(
          find.byKey(ValueKey('quick-log-button-$method')),
        );
        expect(size.width, ordinary[method]!.width);
        expect(
          size.height,
          lessThanOrEqualTo(ordinary[method]!.height + 4),
          reason: method,
        );
        expect(
          size.height,
          t
              .getSize(find.byKey(const ValueKey('quick-log-button-bottle')))
              .height,
        );
      }
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      expect(find.byType(QuickLogElapsedTime), findsNWidgets(6));
      for (final method in c.quickLog) {
        final button = find.byKey(ValueKey('quick-log-button-$method'));
        final icon = find.descendant(
          of: button,
          matching: find.byType(CareGlyph),
        );
        final title = find.descendant(
          of: button,
          matching: find.text(quickLogActivities[method]!),
        );
        final time = find.byKey(ValueKey('quick-log-elapsed-$method'));
        expect(t.getSize(icon), const Size(26, 26));
        expect(t.getRect(icon).right, lessThan(t.getRect(title).left));
        expect(
          t.getRect(time).top,
          greaterThanOrEqualTo(t.getRect(title).bottom),
        );
        final titleRect = t.getRect(title);
        final timeRect = t.getRect(time);
        final column = find.descendant(
          of: button,
          matching: find.byType(Column),
        );
        expect(titleRect.center.dx, t.getRect(column).center.dx);
        expect(timeRect.center.dx, titleRect.center.dx);
        expect(timeRect.top - titleRect.bottom, closeTo(2, 0.01));
        expect(t.widget<Text>(time).style!.fontSize, 11);
      }
      // A narrow phone keeps two columns when the unscaled icons fit.
      t.view.physicalSize = const Size(320, 844);
      await t.pumpAndSettle();
      final bottle = t.getRect(
        find.byKey(const ValueKey('quick-log-button-bottle')),
      );
      final nursing = t.getRect(
        find.byKey(const ValueKey('quick-log-button-nursing')),
      );
      expect(bottle.top, nursing.top);
      expect(bottle.right, lessThan(nursing.left));
      expect(t.takeException(), isNull);
      await t.runAsync(() => c.setQuickLog(['bottle', 'growth']));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('quick-log-elapsed-growth')),
        findsNothing,
      );
      expect(find.byType(QuickLogElapsedTime), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'regular default, persisted Quick Log opt-in, all ten picker icons stay regular',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final c = await localController(t);
      expect(await t.runAsync(c.repository.showElapsedInIcons), false);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      await t.tap(customize());
      await t.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('show-elapsed-in-icons'));
      expect(t.widget<SwitchListTile>(toggle).value, false);
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(c.showElapsedInIcons, true);
      expect(
        await t.runAsync(
          () => Repository(c.repository.db).showElapsedInIcons(),
        ),
        true,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      expect(find.byType(QuickLogElapsedTime), findsNWidgets(4));
      await t.tap(find.text('See all activities'));
      await t.pumpAndSettle();
      for (final method in activityCatalog.keys) {
        final row = find.byKey(ValueKey('activity-picker-$method'));
        expect(row, findsOneWidget);
        expect(
          find.descendant(of: row, matching: find.byType(SeamElapsedGlyph)),
          findsNothing,
        );
        expect(
          find.descendant(of: row, matching: find.byType(CareGlyph)),
          findsOneWidget,
        );
      }
      final latest = Feeding(
        id: 'latest-bottle',
        familyId: c.family!.id,
        method: 'bottle',
        at: DateTime.now().subtract(const Duration(minutes: 59)),
        amountMl: 60,
      );
      await t.runAsync(() async {
        await c.repository.add(latest);
        await c.refresh();
      });
      await t.pumpAndSettle();
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      final bottle = t
          .widgetList<QuickLogElapsedTime>(find.byType(QuickLogElapsedTime))
          .singleWhere((glyph) => glyph.method == 'bottle');
      expect(bottle.elapsed!.inMinutes, 59);
      await t.tap(customize());
      await t.pumpAndSettle();
      await t.tap(toggle);
      await t.pumpAndSettle();
      expect(c.showElapsedInIcons, false);
      expect(find.byType(QuickLogElapsedTime), findsNothing);
      expect(await t.runAsync(c.repository.showElapsedInIcons), false);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      await t.tap(find.text('See all activities'));
      await t.pumpAndSettle();
      for (final method in activityCatalog.keys) {
        expect(find.byKey(ValueKey('activity-picker-$method')), findsOneWidget);
      }
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'elapsed history uses current child, latest completed log and excludes future/deleted records',
    (t) async {
      final c = await localController(t);
      final now = DateTime(2026, 10, 14, 12);
      Feeding record(
        String id,
        String method,
        DateTime at, {
        DateTime? end,
        String? family,
        bool deleted = false,
      }) => Feeding(
        id: id,
        familyId: family ?? c.family!.id,
        at: at,
        method: method,
        endedAt: end,
        deleted: deleted,
      );
      c.feeds = [
        record('old', 'bottle', now.subtract(const Duration(hours: 5))),
        record('latest', 'bottle', now.subtract(const Duration(minutes: 59))),
        record('future', 'bottle', now.add(const Duration(hours: 1))),
        record('deleted', 'bottle', now, deleted: true),
        record('other-child', 'bottle', now, family: 'another-child'),
        record(
          'sleep',
          'sleep',
          now.subtract(const Duration(hours: 9)),
          end: now.subtract(const Duration(hours: 2)),
        ),
        record('older', 'diaper', now.subtract(const Duration(hours: 25))),
        record('not-supported', 'health', now),
      ];
      expect(
        c.timeSinceLastActivity('bottle', now: now),
        const Duration(minutes: 59),
      );
      expect(
        elapsedIconLabel(
          c.timeSinceLastActivity(
            'bottle',
            now: now.add(const Duration(minutes: 1)),
          ),
        ).primary,
        '1h',
      );
      expect(
        c.timeSinceLastActivity('sleep', now: now),
        const Duration(hours: 2),
      );
      expect(
        elapsedIconLabel(c.timeSinceLastActivity('diaper', now: now)).primary,
        '>1d',
      );
      expect(c.timeSinceLastActivity('pumping', now: now), isNull);
      expect(c.timeSinceLastActivity('health', now: now), isNull);
      c.feeds.add(record('new', 'bottle', now));
      expect(
        elapsedIconLabel(c.timeSinceLastActivity('bottle', now: now)).primary,
        'now',
      );
      c.family = const Family(
        id: 'another-child',
        name: 'Other',
        babyName: 'Other',
      );
      expect(c.timeSinceLastActivity('sleep', now: now), isNull);
    },
  );

  testWidgets(
    'toggle and full picker fit small phone with large text in both themes',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final c = await localController(t);
      c.showElapsedInIcons = true;
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        await t.runAsync(() => c.setThemeMode(theme));
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        for (final element in find.byType(ActivityLaunchIcon).evaluate()) {
          final size = t.getSize(find.byWidget(element.widget));
          expect(
            size.width,
            closeTo(size.height, .01),
            reason: 'Quick Log icons keep the same regular proportions',
          );
        }
        await t.tap(customize());
        await t.pumpAndSettle();
        expect(find.text('Show time since last activity'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.pageBack();
        await t.pumpAndSettle();
        await scrollTo(t, find.text('See all activities'));
        await t.tap(find.text('See all activities'));
        await t.pumpAndSettle();
        final last = find.byKey(const ValueKey('activity-picker-milestone'));
        await t.ensureVisible(last);
        await t.pumpAndSettle();
        expect(last, findsOneWidget);
        expect(t.takeException(), isNull);
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
      }
    },
  );
}
