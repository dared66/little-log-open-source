import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'elapsed_icon_preference_test.dart' show localController;
import 'support/test_fonts.dart';
import 'support/scroll_to.dart';

void main() {
  for (final method in [
    'bottle',
    'nursing',
    'diaper',
    'sleep',
    'pumping',
    'solids',
    'growth',
    'health',
    'routine',
    'milestone',
  ]) {
    testWidgets(
      '$method edit has confirmed deletion and Cancel preserves the entry',
      (t) async {
        await t.runAsync(loadTestFonts);
        final c = await localController(t);
        final start = DateTime.now().subtract(const Duration(hours: 1));
        final details = switch (method) {
          'solids' => <String, Object?>{
            'food': 'Pear',
            'reaction': 'Not recorded',
          },
          'growth' => <String, Object?>{
            'measurement': 'Weight',
            'value': 5,
            'unit': 'kg',
          },
          'health' => <String, Object?>{
            'kind': 'Temperature',
            'value': 37,
            'unit': '°C',
          },
          'routine' ||
          'milestone' => <String, Object?>{'name': 'Synthetic example'},
          _ => <String, Object?>{},
        };
        final record = Feeding(
          id: 'saved-$method',
          familyId: c.family!.id,
          method: method,
          at: start,
          endedAt: ['nursing', 'sleep', 'pumping'].contains(method)
              ? start.add(const Duration(minutes: 10))
              : null,
          amountMl: ['bottle', 'pumping'].contains(method) ? 90 : null,
          leftSeconds: method == 'nursing' ? 600 : null,
          rightSeconds: method == 'nursing' ? 0 : null,
          diaperKind: method == 'diaper' ? 'wet' : null,
          details: details,
        );
        await t.runAsync(() async {
          await c.repository.add(record);
          await c.refresh();
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        editActivity(t.element(find.byType(HomePage)), c, record);
        await t.pumpAndSettle();
        final remove = find.byKey(const ValueKey('delete-saved-entry'));
        await scrollTo(t, remove);
        await t.tap(remove);
        await t.pumpAndSettle();
        expect(find.text('Delete this entry?'), findsOneWidget);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(c.feeds, hasLength(1));
        await t.tap(remove);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(find.widgetWithText(TextButton, 'Delete entry').last);
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await t.pumpAndSettle();
        expect(c.feeds, isEmpty);
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }
}
