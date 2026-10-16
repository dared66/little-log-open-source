import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/volume.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:little_log/widgets/measurement_field.dart';
import 'package:little_log/widgets/settings_page.dart';
import 'package:little_log/widgets/toggle_pill.dart';
import 'support/test_fonts.dart';

void main() {
  test(
    'medication temperature survives CSV and rejects partial or invalid data',
    () {
      const family = Family(id: 'f', name: 'Family', babyName: 'Robin');
      Feeding record(Map<String, Object?> extra) => Feeding(
        id: 'm',
        familyId: 'f',
        method: 'health',
        at: DateTime.utc(2026, 10, 8),
        details: {
          'kind': 'Medication',
          'name': 'Recorded medicine',
          'dose': '1 ml',
          ...extra,
        },
      );
      final original = record({'temperature': 100.4, 'temperatureUnit': '°F'});
      final restored = FamilyCsv.decode(
        FamilyCsv(family, [original]).encode(),
      ).feeds.single;
      expect(restored.details, original.details);
      expect(restored.at, original.at);
      expect(
        activityLabel(restored, unit: VolumeUnit.ml),
        contains('Temperature 100.4 °F'),
      );
      validateActivity(record({}), 'f');
      for (final extra in [
        {'temperature': 37},
        {'temperatureUnit': '°C'},
        {'temperature': '37', 'temperatureUnit': '°C'},
        {'temperature': double.nan, 'temperatureUnit': '°C'},
        {'temperature': 37, 'temperatureUnit': 'kg'},
      ]) {
        expect(
          () => validateActivity(record(extra), 'f'),
          throwsFormatException,
        );
      }
    },
  );

  for (final pair in [
    ['kg', 'lb'],
    ['cm', 'in'],
    ['°C', '°F'],
  ]) {
    testWidgets(
      '${pair.first} conversion survives repeated switches and invalid input',
      (t) async {
        double? saved;
        String? savedUnit;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Form(
                child: MeasurementField(
                  label: 'Measurement',
                  units: pair,
                  initialUnit: pair.first,
                  onChanged: (value, unit) {
                    saved = value;
                    savedUnit = unit;
                  },
                ),
              ),
            ),
          ),
        );
        await t.enterText(find.byType(TextFormField), '37.123456');
        for (var i = 0; i < 8; i++) {
          await t.tap(find.byKey(ValueKey('Measurement-unit-${pair.last}')));
          await t.pump();
          expect(
            saved,
            closeTo(measurementFromBase(37.123456, pair.last), 1e-9),
          );
          await t.tap(find.byKey(ValueKey('Measurement-unit-${pair.first}')));
          await t.pump();
          expect(saved, closeTo(37.123456, 1e-9));
          expect(savedUnit, pair.first);
        }
        await t.enterText(find.byType(TextFormField), 'invalid');
        await t.pump();
        expect(find.text('Enter a positive number'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'defaults persist; growth and medication use them; edits preserve recorded units',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('CAPTURE_POLISH')) {
        await t.runAsync(loadTestFonts);
      }
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      var auth = GoogleAuth();
      var c = AppController(Repository(db), auth, GoogleDrive(auth));
      await t.runAsync(() async {
        await c.initialize();
        await c.createLocal('Family', 'Robin');
      });
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      final appTheme = Theme.of(t.element(find.byType(Scaffold).first));
      Future<void> tap(Finder f) async {
        await t.ensureVisible(f);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(f);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }

      Future<void> fill(String label, String text) async {
        final f = find.widgetWithText(TextFormField, label);
        await t.ensureVisible(f);
        await t.enterText(f, text);
        await t.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        if (const bool.fromEnvironment('CAPTURE_POLISH')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('../build/polish-review/$name.png'),
          );
        }
      }

      Future<void> open(
        String method, {
        Feeding? original,
        double scale = 1,
      }) async {
        await t.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: appTheme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: ActivityForm(
                controller: c,
                method: method,
                original: original,
                onSaved: () {},
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await t.pumpWidget(
        MaterialApp(
          theme: appTheme,
          debugShowCheckedModeBanner: false,
          home: SettingsPage(controller: c),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(TogglePill<String>), findsNWidgets(3));
      await tap(find.byKey(const ValueKey('default-weight-lb')));
      await tap(find.byKey(const ValueKey('default-length-in')));
      await tap(find.byKey(const ValueKey('default-temperature-°F')));
      await capture('unit-settings');
      await t.pumpWidget(const SizedBox());
      c.dispose();
      auth = GoogleAuth();
      c = AppController(Repository(db), auth, GoogleDrive(auth));
      await t.runAsync(c.initialize);
      expect(c.weightUnit, 'lb');
      expect(c.lengthUnit, 'in');
      expect(c.temperatureUnit, '°F');

      await open('growth');
      expect(find.text('Measured value (lb)'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      for (final measurement in ['Length', 'Head circumference']) {
        await tap(find.byType(DropdownButtonFormField<String>));
        await tap(find.text(measurement).last);
        expect(find.text('Measured value (in)'), findsOneWidget);
      }
      await fill('Measured value (in)', '14');
      await capture('growth');
      await tap(find.text('Save growth'));
      final growth = c.feeds.single;
      expect(growth.details['measurement'], 'Head circumference');
      expect(growth.details['unit'], 'in');
      await t.runAsync(() => c.setLengthUnit('cm'));
      await open('growth', original: growth);
      expect(find.text('Measured value (in)'), findsOneWidget);

      await open('health');
      await fill('Medicine name', 'Recorded medicine');
      await fill('Dose given (include unit)', '1 ml');
      await fill('Temperature (°F)', '100.4');
      await capture('medication-temperature');
      await tap(find.text('Save health'));
      final medication = c.feeds.firstWhere((f) => f.method == 'health');
      expect(medication.details['temperature'], 100.4);
      expect(medication.details['temperatureUnit'], '°F');
      await t.runAsync(() => c.setTemperatureUnit('°C'));
      await open('health', original: medication);
      expect(find.text('Temperature (°F)'), findsOneWidget);
      await tap(find.byKey(const ValueKey('Temperature-unit-°C')));
      await tap(find.text('Save changes'));
      final changed = c.feeds.firstWhere((f) => f.method == 'health');
      expect(changed.at, medication.at);
      expect(changed.details['temperature'], closeTo(38, 1e-9));
      expect(changed.details['temperatureUnit'], '°C');
      await open('health', original: changed);
      await fill('Temperature (°C)', '');
      await tap(find.text('Save changes'));
      expect(
        c.feeds
            .firstWhere((f) => f.method == 'health')
            .details
            .containsKey('temperature'),
        isFalse,
      );

      await open('health');
      await tap(find.byType(DropdownButtonFormField<String>));
      await tap(find.text('Temperature').last);
      expect(find.text('Temperature (°C)'), findsOneWidget);
      await tap(find.text('Save health'));
      expect(find.text('Enter Temperature (°C)'), findsOneWidget);

      t.view.physicalSize = const Size(320, 844);
      await open('growth', scale: 2);
      await fill('Measured value (lb)', '12');
      await capture('growth-small-large-text');
      expect(t.takeException(), isNull);
      await open('health', scale: 2);
      await fill('Temperature (°C)', '37');
      await capture('medication-small-large-text');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );
}
