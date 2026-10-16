import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'support/test_fonts.dart';

void main() {
  const capture = bool.fromEnvironment('CAPTURE_ENTRY_TIME');
  Future<void> openPicker(
    WidgetTester t, {
    required ValueChanged<DateTime> onChanged,
    bool allowNow = true,
  }) async {
    if (capture) await t.runAsync(loadTestFonts);
    await t.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: logBackground,
          colorScheme: ColorScheme.fromSeed(
            seedColor: logActionInk,
            primary: logActionInk,
            surface: logBackground,
          ),
        ),
        home: Scaffold(
          body: EntryTime(
            label: 'Ended',
            value: DateTime(2026, 10, 2, 23, 58),
            now: () => DateTime(2026, 10, 3, 0, 1, 37),
            allowNow: allowNow,
            onChanged: onChanged,
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const ValueKey('Ended-time')));
    await t.pumpAndSettle();
  }

  testWidgets('Now updates date across midnight only after OK', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final semantics = t.ensureSemantics();
    DateTime? changed;
    await openPicker(t, onChanged: (value) => changed = value);
    expect(find.bySemanticsLabel('Now'), findsOneWidget);
    if (capture) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../output/entry-time-now/standard.png'),
      );
    }
    await t.tap(find.text('Now'));
    await t.pumpAndSettle();
    expect(changed, isNull);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(changed, DateTime(2026, 10, 3, 0, 1, 37));
    semantics.dispose();
  });

  testWidgets('Now then Cancel leaves the field unchanged', (t) async {
    DateTime? changed;
    await openPicker(t, onChanged: (value) => changed = value);
    await t.tap(find.text('Now'));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(changed, isNull);
  });

  testWidgets('Now preserves keyboard mode and subsequent edits use today', (
    t,
  ) async {
    DateTime? changed;
    await openPicker(t, onChanged: (value) => changed = value);
    await t.tap(find.byIcon(Icons.keyboard_outlined));
    await t.pumpAndSettle();
    await t.tap(find.text('Now'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    await t.enterText(find.byType(TextField).at(1), '5');
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(changed, DateTime(2026, 10, 3, 0, 5));
    // Native keyboard dismissal is not part of Flutter's animation queue.
    await t.pump(const Duration(milliseconds: 500));
  });

  testWidgets('callers can hide Now', (t) async {
    await openPicker(t, onChanged: (_) {}, allowNow: false);
    expect(find.text('Now'), findsNothing);
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
  });

  testWidgets('small phone and large text keep footer actions usable', (
    t,
  ) async {
    // Unit tests simulate 320px; native runs keep the engine's real viewport
    // so pointer coordinates match the simulator's actual render surface.
    if (t.binding is AutomatedTestWidgetsFlutterBinding) {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = FakeViewPadding.zero;
    }
    t.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(t.view.resetViewInsets);
    DateTime? changed;
    await openPicker(t, onChanged: (value) => changed = value);
    expect(t.takeException(), isNull);
    final nowRect = t.getRect(find.byKey(const ValueKey('entry-time-now')));
    if (capture) {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../output/entry-time-now/small-large-text.png'),
      );
    }
    expect(nowRect.width, greaterThanOrEqualTo(44));
    expect(nowRect.height, greaterThanOrEqualTo(44));
    expect(nowRect.overlaps(t.getRect(find.text('Cancel'))), isFalse);
    await t.tap(find.text('Now'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(changed, DateTime(2026, 10, 3, 0, 1, 37));
  });

  for (final value in [
    DateTime(1999, 12, 31),
    DateTime.now().add(const Duration(days: 3)),
  ]) {
    testWidgets('imported out-of-range date opens and cancels: $value', (
      t,
    ) async {
      DateTime? changed;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EntryTime(
              label: 'Started',
              value: value,
              onChanged: (date) => changed = date,
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('Started-date')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(changed, isNull);
    });
  }

  testWidgets(
    'date and time edit independently and cancellation preserves value',
    (t) async {
      var value = DateTime(2026, 1, 12, 14, 35, 42);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => EntryTime(
                label: 'Started',
                value: value,
                onChanged: (chosen) => setState(() => value = chosen),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('Started-time')));
      await t.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await t.tap(find.byIcon(Icons.keyboard_outlined));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).at(0), '3');
      await t.enterText(find.byType(TextField).at(1), '40');
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(value, DateTime(2026, 1, 12, 15, 40));
      await t.tap(find.byKey(const ValueKey('Started-date')));
      await t.pumpAndSettle();
      await t.tap(find.text('11'));
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      expect(value, DateTime(2026, 1, 11, 15, 40));
      expect(find.byType(TimePickerDialog), findsNothing);
      for (final part in ['date', 'time']) {
        await t.tap(find.byKey(ValueKey('Started-$part')));
        await t.pumpAndSettle();
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(value, DateTime(2026, 1, 11, 15, 40));
      }
    },
  );
}
