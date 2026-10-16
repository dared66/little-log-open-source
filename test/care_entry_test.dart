import 'package:little_log/widgets/toggle_pill.dart';
import 'support/selection_chip_expectations.dart';
import 'support/test_fonts.dart';
import 'package:little_log/design.dart';
import 'package:little_log/volume.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

void main() {
  late AppController c;
  Future<void> setup(
    WidgetTester t, {
    double width = 390,
    double scale = 1,
  }) async {
    if (const bool.fromEnvironment('CAPTURE_ENTRY')) {
      await t.runAsync(loadTestFonts);
    }
    t.view.physicalSize = Size(width, 844);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    c = AppController(Repository(db), auth, GoogleDrive(auth))..loading = false;
    await t.runAsync(() => c.createLocal('Family', 'Robin'));
    addTearDown(() async {
      c.dispose();
      await db.close();
    });
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
  }

  Future<void> capture(WidgetTester t, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_ENTRY')) return;
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../build/entry46-review/$name.png'),
    );
  }

  Future<void> tap(WidgetTester t, Finder finder) async {
    await t.ensureVisible(finder);
    await t.pumpAndSettle();
    await t.tap(finder);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull, reason: 'After tapping $finder');
  }

  Future<void> save(WidgetTester t, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    // The native IME transition can start after Flutter has no pending frame.
    await t.pumpAndSettle(const Duration(milliseconds: 300));
    for (
      var attempt = 0;
      attempt < 10 && find.text(label).hitTestable().evaluate().isEmpty;
      attempt++
    ) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.text(label).hitTestable(), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text(label));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> select(WidgetTester t, String label, String option) async {
    if (label == 'Poop color' || label == 'Consistency') {
      await tap(t, find.widgetWithText(FilterChip, option));
      return;
    }
    await tap(
      t,
      (label == 'Activity'
          ? find.widgetWithText(DropdownButtonFormField<String>, label)
          : find.descendant(
              of: find.byKey(ValueKey('field-$label')),
              matching: find.byType(DropdownButtonFormField<String>),
            )),
    );
    await tap(t, find.text(option).last);
  }

  testWidgets(
    'Settings saves a default and entry overrides leave it unchanged',
    (t) async {
      await setup(t);
      await tap(t, find.text('Settings').last);
      await tap(t, find.text('Units'));
      expect(
        t
            .getTopLeft(
              find.text(
                'Applies on this device. Recorded amounts are unchanged.',
              ),
            )
            .dy,
        lessThan(t.getTopLeft(find.text('Volume')).dy),
      );
      expect(find.byType(TogglePill<VolumeUnit>), findsOneWidget);
      expect(find.byType(TogglePill<String>), findsNWidgets(3));
      await tap(t, find.text('lb'));
      expect(c.weightUnit, 'lb');
      expect(await t.runAsync(c.repository.weightUnit), 'lb');
      await tap(t, find.byKey(const ValueKey('default-volume-oz')));
      expect(c.volumeUnit, VolumeUnit.oz);
      expect(await t.runAsync(c.repository.volumeUnit), VolumeUnit.oz);
      await t.pageBack();
      await t.pumpAndSettle();
      await tap(t, find.text('Log'));
      await tap(t, find.text('Bottle').first);
      expect(find.text('Amount (oz)'), findsOneWidget);
      await capture(t, 'bottle-oz');
      await tap(t, find.byKey(const ValueKey('volume-ml')));
      expect(find.text('Amount (ml)'), findsOneWidget);
      expect(c.volumeUnit, VolumeUnit.oz);
      await tap(t, find.byTooltip('Close'));
      await tap(t, find.text('Bottle').first);
      expect(find.text('Amount (oz)'), findsOneWidget);
      await tap(t, find.byTooltip('Close'));
      await tap(t, find.text('Settings').last);
      await tap(t, find.text('Units'));
      await tap(t, find.byKey(const ValueKey('default-volume-ml')));
      expect(c.volumeUnit, VolumeUnit.ml);
      expect(await t.runAsync(c.repository.volumeUnit), VolumeUnit.ml);
    },
  );

  testWidgets(
    'Bottle and past nursing have separate fixed entry screens and save the right types',
    (t) async {
      await setup(t);
      await tap(t, find.text('Bottle').first);
      expect(
        find.descendant(
          of: find.byType(BottleEntryForm),
          matching: find.text('Bottle'),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>).first,
            )
            .initialValue,
        'milk',
      );
      expect(
        find.descendant(
          of: find.byType(BottleEntryForm),
          matching: find.textContaining('Nursing'),
        ),
        findsNothing,
      );
      await capture(t, 'bottle-default');
      expect(find.byKey(const ValueKey('volume-ml')), findsOneWidget);
      expect(find.byKey(const ValueKey('volume-oz')), findsOneWidget);
      expect(find.text('Duration (minutes)'), findsNothing);
      await tap(t, find.byKey(const ValueKey('volume-oz')));
      await t.enterText(find.widgetWithText(TextFormField, 'Amount (oz)'), '3');
      await save(t, 'Save bottle');
      expect(c.feeds.single.method, 'bottle');
      expect(c.feeds.single.amountMl, VolumeUnit.oz.toMl(3));
      expect(c.volumeUnit, VolumeUnit.ml);
      expect(c.feeds.single.minutes, isNull);
      expect(c.feeds.single.details['breastMilkMl'], c.feeds.single.amountMl);
      expect(c.feeds.single.details['formulaMl'], 0);
      await tap(t, find.text('Nursing').first);
      await tap(t, find.text('Enter manually'));
      expect(find.byType(NursingEntryForm), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(NursingEntryForm),
          matching: find.text('Nursing'),
        ),
        findsOneWidget,
      );
      expect(find.text('Amount (ml)'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NursingEntryForm),
          matching: find.byType(ChoiceChip),
        ),
        findsNothing,
      );
      expect(find.text('Duration (minutes)'), findsNothing);
      expect(find.text('Record each side'), findsNothing);
      await capture(t, 'nursing-required-sides');
      await save(t, 'Save nursing');
      expect(c.feeds.where((f) => f.method == 'nursing'), isEmpty);
      await t.enterText(
        find.widgetWithText(TextFormField, 'Minutes').first,
        '12',
      );
      await save(t, 'Save nursing');
      final nursing = c.feeds.where((f) => f.method == 'nursing').single;
      expect(nursing.minutes, 12);
      expect(nursing.leftSeconds, 720);
      expect(nursing.rightSeconds, 0);
      expect(nursing.amountMl, isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Dirty details save and appear in Today and History with explicit negatives',
    (t) async {
      await setup(t);
      await tap(t, find.text('Diaper').first);
      expect(find.text('Poop details'), findsNothing);
      expect(find.byType(BooleanSelection), findsNothing);
      final wetChip = find.widgetWithText(FilterChip, 'Wet');
      final dirtyChip = find.widgetWithText(FilterChip, 'Dirty');
      expect(t.getTopLeft(wetChip).dy, t.getTopLeft(dirtyChip).dy);
      expect(t.getBottomLeft(wetChip).dy, t.getBottomLeft(dirtyChip).dy);
      expect(t.getTopLeft(dirtyChip).dx - t.getTopRight(wetChip).dx, 8);
      await capture(t, 'diaper-controls-restored');
      await tap(t, dirtyChip);
      expectSharedSelectionChips(t);
      await select(t, 'Poop color', 'Mustard');
      await select(t, 'Consistency', 'Seedy');
      await tap(t, find.widgetWithText(SwitchListTile, 'Blowout'));
      await t.ensureVisible(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
        'Changed outfit',
      );
      expect(find.text('Save diaper').hitTestable(), findsOneWidget);
      await save(t, 'Save diaper');
      expect(c.feeds.single.details, {
        'poopColor': 'mustard',
        'poopConsistency': 'seedy',
        'blowout': true,
        'rash': false,
      });
      expect(c.feeds.single.diaperKind, 'both');
      expect(find.text('Changed outfit'), findsNothing);
      await t.scrollUntilVisible(
        find.byType(RecordRow),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(t, find.byType(RecordRow).first);
      expect(find.text('Mustard · Seedy'), findsOneWidget);
      expect(
        find.textContaining('Blowout', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(RecordRow),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(RecordRow),
          matching: find.byIcon(Icons.close),
        ),
        findsOneWidget,
      );
      final semantics = t.ensureSemantics();
      await t.pump();
      expect(find.bySemanticsLabel(RegExp('Rash: No')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Blowout: Yes')), findsOneWidget);
      semantics.dispose();
      expect(find.text('Changed outfit'), findsOneWidget);
      await capture(t, 'diaper-indicators');
      await t.scrollUntilVisible(
        find.text('View all'),
        -150,
        scrollable: find.byType(Scrollable).first,
      );
      await tap(t, find.text('View all'));
      await t.scrollUntilVisible(
        find.byType(RecordRow),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      if (find.text('Changed outfit').evaluate().isEmpty) {
        await tap(t, find.byType(RecordRow).first);
      }
      expect(find.textContaining('Blowout', findRichText: true), findsWidgets);
      expect(find.text('Changed outfit'), findsWidgets);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'switching to Wet or Dry clears poop details but retains independent rash',
    (t) async {
      await setup(t);
      await tap(t, find.text('Diaper').first);
      await tap(t, find.widgetWithText(FilterChip, 'Dirty'));
      await select(t, 'Poop color', 'Brown');
      await select(t, 'Consistency', 'Hard / pellets');
      await tap(t, find.widgetWithText(SwitchListTile, 'Blowout'));
      await tap(t, find.widgetWithText(SwitchListTile, 'Diaper rash'));
      await tap(t, find.widgetWithText(FilterChip, 'Dirty'));
      expect(find.text('Poop details'), findsNothing);
      await tap(t, find.widgetWithText(FilterChip, 'Dirty'));
      expect(
        t
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Blowout'),
            )
            .value,
        false,
      );
      for (final field
          in find.byType(DropdownButtonFormField<String>).evaluate()) {
        expect((field as StatefulElement).state, isA<FormFieldState<String>>());
        expect((field.state as FormFieldState<String>).value, '');
      }
      await tap(t, find.widgetWithText(FilterChip, 'Wet'));
      await tap(t, find.widgetWithText(FilterChip, 'Dirty'));
      await save(t, 'Save diaper');
      expect(c.feeds.single.diaperKind, 'dry');
      expect(c.feeds.single.details, {'rash': true});
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'small phone large text and keyboard keep detailed diaper save reachable',
    (t) async {
      await setup(t, width: 320, scale: 1.8);
      await t.scrollUntilVisible(find.text('Diaper'), 180);
      await tap(t, find.text('Diaper').first);
      await tap(t, find.widgetWithText(FilterChip, 'Dirty'));
      await select(t, 'Poop color', 'Yellow');
      await select(t, 'Consistency', 'Hard / pellets');
      t.view.viewInsets = const FakeViewPadding(bottom: 260);
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Save diaper').hitTestable(), findsOneWidget);
      t.view.resetViewInsets();
      await t.pumpAndSettle();
      await save(t, 'Save diaper');
      expect(c.feeds.single.details['blowout'], false);
      expect(c.feeds.single.details['rash'], false);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('open forms stay bound to their original child', (t) async {
    await setup(t);
    await tap(t, find.text('Bottle').first);
    final originalFamily = c.family!.id;
    await t.enterText(find.widgetWithText(TextFormField, 'Amount (ml)'), '90');
    await t.runAsync(() => c.createLocal('Another family', 'Sam'));
    await t.pumpAndSettle();
    await save(t, 'Save bottle');
    expect(
      find.text('The selected child has changed. Reopen the form.'),
      findsOneWidget,
    );
    expect(find.byType(BottleEntryForm), findsOneWidget);
    expect(await t.runAsync(() => c.repository.feeds(originalFamily)), isEmpty);
    expect(c.feeds, isEmpty);
    await t.pumpWidget(const SizedBox());
  });
}
