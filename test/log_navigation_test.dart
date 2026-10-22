import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'support/test_fonts.dart';
import 'support/scroll_to.dart';

void main() {
  for (final large in [false, true]) {
    testWidgets('full app context ${large ? 'large' : 'normal'}', (t) async {
      t.view.physicalSize = Size(large ? 320 : 390, 844);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final repo = Repository(db);
      final c = AppController(repo, auth, GoogleDrive(auth))..loading = false;
      await t.runAsync(() async {
        await c.createLocal('Design review', 'Robin');
        await repo.saveSwipeDemoSeen();
        await c.setSummaryMetrics(['Nursing', 'Diapers']);
        final date = DateTime.now();
        final now = DateTime(date.year, date.month, date.day, 12);
        for (final entry in [
          Feeding(
            id: 'nursing',
            familyId: c.family!.id,
            at: now.subtract(const Duration(minutes: 30)),
            method: 'nursing',
            leftSeconds: 793,
            rightSeconds: 691,
            endedAt: now.subtract(const Duration(minutes: 5)),
          ),
          Feeding(
            id: 'diaper',
            familyId: c.family!.id,
            at: now.subtract(const Duration(minutes: 31)),
            method: 'diaper',
            diaperKind: 'both',
            details: const {
              'poopColor': 'mustard',
              'poopConsistency': 'mushy',
              'blowout': false,
              'rash': false,
            },
            author: 'Caregiver',
          ),
          Feeding(
            id: 'positive',
            familyId: c.family!.id,
            at: now.subtract(const Duration(hours: 2)),
            method: 'diaper',
            diaperKind: 'wet',
            details: const {'rash': true},
            author: 'Caregiver',
          ),
          Feeding(
            id: 'unrecorded',
            familyId: c.family!.id,
            at: now.subtract(const Duration(hours: 3)),
            method: 'diaper',
            diaperKind: 'dirty',
          ),
          Feeding(
            id: 'bottle',
            familyId: c.family!.id,
            at: now.subtract(const Duration(hours: 4)),
            method: 'bottle',
            amountMl: 90,
          ),
        ]) {
          await repo.add(entry);
        }
        await c.refresh();
      });
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      Future<void> capture(String name) async {
        expect(t.takeException(), isNull);
        if (!const bool.fromEnvironment('CAPTURE_LOG_REVIEW')) return;
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            '../build/design-review/$name-${large ? 'large' : 'normal'}.png',
          ),
        );
      }

      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.tap(f);
        await t.pumpAndSettle();
      }

      expect(
        find.descendant(
          of: find.byKey(const ValueKey('log-day-picker')),
          matching: find.text('Today'),
        ),
        findsOneWidget,
      );
      if (!large) {
        final calendar = find.descendant(
          of: find.byKey(const ValueKey('log-day-picker')),
          matching: find.byWidgetPredicate(
            (w) => w is CustomPaint && w.size.width > 0,
          ),
        );
        expect(
          t.getTopRight(calendar).dx,
          closeTo(t.view.physicalSize.width - 20, .1),
        );
        expect(
          t.getTopRight(find.text('Customize').first).dx,
          closeTo(t.getTopRight(calendar).dx, .1),
        );
      }
      await capture('overview');
      await t.scrollUntilVisible(
        find.text('Diaper · Wet & dirty'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(find.text('Diaper · Wet & dirty'));
      await capture('today');
      final observation = find.text('Blowout');
      expect(
        t.widget<Text>(observation).style,
        t.widget<Text>(find.text('Mustard · Mushy')).style,
      );
      if (!large) {
        expect(
          t.getCenter(observation).dy,
          closeTo(t.getCenter(find.text('Rash')).dy, 0.1),
        );
      }

      final semantics = t.ensureSemantics();
      await t.pump();
      expect(find.bySemanticsLabel(RegExp('Blowout: No')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Rash: No')), findsOneWidget);
      semantics.dispose();
      await scrollTo(t, find.text('View all'));
      await tap(find.text('View all'));
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('Diaper · Wet & dirty'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await capture('all-activity');
      await tap(find.text('Diaper · Wet'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('positive')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await capture('positive');
      await tap(find.text('Diaper · Dirty'));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('unrecorded')),
          matching: find.textContaining('×'),
        ),
        findsNothing,
      );
      await tap(find.byKey(const ValueKey('log-day-picker')));
      await capture('day-picker');
      await tap(find.byTooltip('Previous day'));
      final previous = DateTime.now().subtract(const Duration(days: 1));
      expect(find.text(DateFormat.yMMMd().format(previous)), findsOneWidget);
      await tap(find.text('Today').last);
      expect(
        t
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Next day',
              ),
            )
            .onPressed,
        isNull,
      );
      await tap(find.text(DateFormat.yMMMM().format(DateTime.now())));
      expect(find.byType(YearPicker), findsOneWidget);
      final years = find.descendant(
        of: find.byType(YearPicker),
        matching: find.byType(Scrollable),
      );
      final yearScroll = t.state<ScrollableState>(years);
      yearScroll.position.jumpTo(yearScroll.position.maxScrollExtent);
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('${DateTime.now().year - 1}').last,
        -100,
        scrollable: years,
      );
      await tap(find.text('${DateTime.now().year - 1}').last);
      expect(
        find.text(
          DateFormat.yMMMM().format(
            DateTime(DateTime.now().year - 1, DateTime.now().month),
          ),
        ),
        findsOneWidget,
      );
      await tap(find.text('Today').last);

      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      if (yesterday.month != DateTime.now().month) {
        await tap(find.byTooltip('Previous month'));
      }
      await tap(find.text('${yesterday.day}').last);
      await tap(find.text('Show day'));
      final homeScroll = find
          .descendant(
            of: find.byKey(const PageStorageKey('today')),
            matching: find.byType(Scrollable),
          )
          .first;
      t.state<ScrollableState>(homeScroll).position.jumpTo(0);
      await t.pumpAndSettle();
      await capture('past-day');
      await t.scrollUntilVisible(
        find.text('At a glance'),
        180,
        scrollable: homeScroll,
      );
      await t.pumpAndSettle();
      expect(find.text('At a glance'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('No entries'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      expect(find.text('No entries'), findsOneWidget);
      expect(find.text('Diaper · Wet & dirty'), findsNothing);
      await t.scrollUntilVisible(
        find.text('Back to today'),
        -180,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await tap(find.text('Back to today'));
      await t.scrollUntilVisible(
        find.text('Customize').last,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(find.text('Customize').last);
      await capture('customize-summary');
      final quickLogBefore = [...c.quickLog];
      await tap(find.text('Pumped'));
      await t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await t.pumpAndSettle();
      expect(await t.runAsync(repo.summaryMetrics), [
        'Nursing',
        'Diapers',
        'Pumped',
      ]);
      expect(c.quickLog, quickLogBefore);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(find.text('Settings').last);
      await capture('settings');
      await tap(find.text('Units'));
      await capture('units');
      await t.pageBack();
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }
}
