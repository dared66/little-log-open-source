import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds lazy list children without depending on platform fling physics or
/// selectable text intercepting a drag. Gesture behavior has native coverage.
Future<void> scrollTo(WidgetTester tester, Finder target) async {
  final state = tester.state<ScrollableState>(find.byType(Scrollable).first);
  state.position.jumpTo(0);
  await tester.pumpAndSettle();
  for (var step = 0; step < 150 && target.evaluate().isEmpty; step++) {
    final position = state.position;
    final next = (position.pixels + 160).clamp(0.0, position.maxScrollExtent);
    if (next == position.pixels) break;
    position.jumpTo(next);
    await tester.pumpAndSettle();
  }
  expect(target, findsOneWidget);
  await Scrollable.ensureVisible(tester.element(target), alignment: .5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}
