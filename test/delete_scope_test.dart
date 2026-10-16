import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/volume.dart';

void main() => deleteScopeTests();

void deleteScopeTests({Future<void> Function(WidgetTester, String)? capture}) {
  for (final local in [true, false]) {
    testWidgets(
      'delete confirmation explains ${local ? 'local' : 'shared'} scope',
      (t) async {
        var deletes = 0;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordRow(
                record: Feeding(
                  id: 'qa',
                  familyId: 'qa',
                  at: DateTime.now(),
                  method: 'bottle',
                  amountMl: 60,
                ),
                volumeUnit: VolumeUnit.ml,
                local: local,
                onDelete: () async {
                  deletes++;
                },
              ),
            ),
          ),
        );
        // This test checks the confirmation copy. The native journey checks
        // the swipe itself; use the row's delete action here so the dialog is
        // reached consistently across emulator viewport sizes.
        final action = t
            .widget<Semantics>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is Semantics &&
                    widget.properties.customSemanticsActions?.keys.any(
                          (action) => action.label == 'Delete entry',
                        ) ==
                        true,
              ),
            )
            .properties
            .customSemanticsActions!
            .entries
            .firstWhere((entry) => entry.key.label == 'Delete entry')
            .value;
        action();
        await t.pumpAndSettle();
        expect(
          find.text(
            local
                ? 'Deletes this entry from this device.'
                : 'Deletes this entry from this device and the shared log when it syncs.',
          ),
          findsOneWidget,
        );
        if (capture != null) {
          await capture(
            t,
            local ? 'local-delete-fixed' : 'shared-delete-fixed',
          );
        }
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(deletes, 0);
        expect(t.takeException(), isNull);
      },
    );
  }
}
