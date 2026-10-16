import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/widgets/selection_chip.dart';

/// Checks rendered controls as well as adoption of the shared component.
void expectSharedSelectionChips(WidgetTester tester) {
  final choices = find.byType(ChoiceChip);
  final filters = find.byType(FilterChip);
  expect(choices.evaluate().length + filters.evaluate().length, greaterThan(0));
  for (final finder in [choices, filters]) {
    for (final element in finder.evaluate()) {
      final chip = find.byWidget(element.widget);
      expect(
        find.ancestor(of: chip, matching: find.byType(SelectionChip)),
        findsOneWidget,
      );
      final dynamic widget = element.widget;
      expect(widget.showCheckmark, false);
      expect(widget.selectedColor, logActionTint);
      expect(widget.backgroundColor, Colors.white);
      expect(widget.labelStyle.color, widget.selected ? logActionInk : logInk);
      expect(widget.labelStyle.fontSize, 14);
      expect(widget.shape, isA<RoundedRectangleBorder>());
    }
  }
}
