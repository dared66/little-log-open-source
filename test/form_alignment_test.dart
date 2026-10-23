import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/volume.dart';
import 'package:little_log/widgets/measurement_field.dart';
import 'package:little_log/widgets/toggle_pill.dart';
import 'package:little_log/widgets/volume_field.dart';

void main() {
  for (final measurement in [false, true]) {
    testWidgets(
      '${measurement ? 'Measurement' : 'Volume'} units stay aligned when validation appears',
      (t) async {
        final form = GlobalKey<FormState>();
        await t.pumpWidget(
          MaterialApp(
            theme: littleLogTheme(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: 350,
                  child: Form(
                    key: form,
                    child: measurement
                        ? MeasurementField(
                            label: 'Temperature',
                            units: const ['°C', '°F'],
                            initialUnit: '°C',
                            onChanged: (_, _) {},
                          )
                        : VolumeField(
                            label: 'Amount',
                            initialUnit: VolumeUnit.ml,
                            onChanged: (_) {},
                          ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final units = measurement
            ? find.byType(TogglePill<String>)
            : find.byType(TogglePill<VolumeUnit>);
        final before = t.getRect(units);
        expect(form.currentState!.validate(), isFalse);
        await t.pumpAndSettle();
        expect(
          t.getRect(units),
          before,
          reason: 'Error copy must not displace the unit control',
        );
        await t.tap(find.text(measurement ? '°F' : 'oz'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(t.getRect(units).center.dy, closeTo(before.center.dy, .1));
      },
    );
  }
}
