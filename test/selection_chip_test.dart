import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/widgets/selection_chip.dart';
import 'support/selection_chip_expectations.dart';

void main() {
  for (final multiple in [false, true]) {
    testWidgets(
      '${multiple ? 'Multi' : 'Single'} selection keeps state and semantics without checkmarks',
      (t) async {
        var selected = false;
        final semantics = t.ensureSemantics();
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => SelectionChip(
                  label: const Text('Option'),
                  multiple: multiple,
                  selected: selected,
                  onSelected: (value) => setState(() => selected = value),
                ),
              ),
            ),
          ),
        );
        expectSharedSelectionChips(t);
        final chip = find.byType(multiple ? FilterChip : ChoiceChip);
        expect(
          t.getSemantics(chip).flagsCollection.isSelected.toBoolOrNull(),
          false,
        );
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(selected, true);
        expectSharedSelectionChips(t);
        expect(
          t.getSemantics(chip).flagsCollection.isSelected.toBoolOrNull(),
          true,
        );
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(selected, false);
        expect(find.byIcon(Icons.check), findsNothing);
        semantics.dispose();
      },
    );
  }
  testWidgets('Disabled selection keeps its state and cannot be activated', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    await t.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SelectionChip(
            label: Text('Disabled'),
            selected: true,
            onSelected: null,
          ),
        ),
      ),
    );
    expectSharedSelectionChips(t);
    final chip = find.byType(ChoiceChip);
    expect(
      t.getSemantics(chip).flagsCollection.isSelected.toBoolOrNull(),
      true,
    );
    expect(
      t.getSemantics(chip).flagsCollection.isEnabled.toBoolOrNull(),
      false,
    );
    await t.tap(chip);
    await t.pumpAndSettle();
    expect(t.widget<ChoiceChip>(chip).selected, true);
    semantics.dispose();
  });
}
