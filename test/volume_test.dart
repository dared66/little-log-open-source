import 'package:little_log/design.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_io.dart';
import 'package:little_log/volume.dart';
import 'package:little_log/widgets/volume_field.dart';
import 'package:little_log/models.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/services/family_csv.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  test(
    'US fluid ounce conversions and mixed-unit totals survive CSV and reopening',
    () async {
      expect(VolumeUnit.oz.toMl(1), 29.5735295625);
      expect(
        VolumeUnit.oz.fromMl(VolumeUnit.oz.toMl(3.5)),
        closeTo(3.5, 1e-12),
      );
      expect(volumeLabel(0, unit: VolumeUnit.ml), '0 ml');
      expect(volumeLabel(0, unit: VolumeUnit.oz), '0 oz');
      const family = Family(id: 'f', name: 'Family', babyName: 'Baby');
      final records = [
        Feeding(
          id: 'oz',
          familyId: 'f',
          at: DateTime.now(),
          method: 'bottle',
          amountMl: VolumeUnit.oz.toMl(3),
        ),
        Feeding(
          id: 'ml',
          familyId: 'f',
          at: DateTime.now(),
          method: 'bottle',
          amountMl: 90,
        ),
        Feeding(
          id: 'pump',
          familyId: 'f',
          at: DateTime.now(),
          method: 'pumping',
          amountMl: VolumeUnit.oz.toMl(2.5),
        ),
      ];
      final decoded = FamilyCsv.decode(
        FamilyCsv(family, records).encode(),
      ).feeds;
      final totals = DaySummary(decoded, DateTime.now());
      expect(totals.bottleMl, closeTo(178.7205886875, 1e-10));
      expect(totals.pumpedMl, closeTo(73.93382390625, 1e-10));
      expect(volumeLabel(totals.bottleMl, unit: VolumeUnit.ml), '178.72 ml');
      expect(volumeLabel(totals.bottleMl, unit: VolumeUnit.oz), '6.04 oz');
      final dir = await Directory.systemTemp.createTemp('volume-test-');
      final path = '${dir.path}/db';
      var db = await databaseFactoryIo.openDatabase(path);
      var repo = Repository(db);
      expect(await repo.volumeUnit(), VolumeUnit.ml);
      await repo.saveVolumeUnit(VolumeUnit.oz);
      for (final r in decoded) {
        await repo.add(r);
      }
      await db.close();
      db = await databaseFactoryIo.openDatabase(path);
      repo = Repository(db);
      expect(await repo.volumeUnit(), VolumeUnit.oz);
      expect(
        (await repo.feeds('f')).firstWhere((f) => f.id == 'oz').amountMl,
        VolumeUnit.oz.toMl(3),
      );
      await db.close();
      await dir.delete(recursive: true);
    },
  );
  testWidgets(
    'unit switches preserve the exact amount and editing uses the selected unit',
    (t) async {
      double? ml;
      VolumeUnit? chosen;
      final form = GlobalKey<FormState>();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  VolumeField(
                    label: 'Amount',
                    initialUnit: VolumeUnit.oz,
                    onChanged: (v) => ml = v,
                    onUnitChanged: (v) => chosen = v,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      expect(
        t.getTopLeft(find.byKey(const ValueKey('volume-unit-pill'))).dx,
        greaterThan(t.getTopRight(find.byType(TextFormField)).dx),
      );
      final pill = find.byKey(const ValueKey('volume-unit-pill'));
      final amount = find.byType(TextFormField);
      expect(t.getCenter(pill).dy, closeTo(t.getCenter(amount).dy, 1));
      expect(t.getSize(pill).height, lessThanOrEqualTo(40));
      expect(t.getSize(pill).height, lessThan(t.getSize(amount).height));
      final selectedSurface = find
          .ancestor(
            of: find.byKey(const ValueKey('volume-oz')),
            matching: find.byType(Material),
          )
          .first;
      expect(t.widget<Material>(selectedSurface).color, logActionTint);
      expect(
        find.descendant(of: pill, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
      await t.enterText(find.byType(TextFormField), '3.5');
      final original = ml!;
      for (var i = 0; i < 5; i++) {
        await t.tap(find.byKey(const ValueKey('volume-ml')));
        await t.pump();
        expect(find.text('Amount (ml)'), findsOneWidget);
        expect(
          t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
          '103.51',
        );
        await t.tap(find.byKey(const ValueKey('volume-oz')));
        await t.pump();
      }
      expect(ml, original);
      expect(chosen, VolumeUnit.oz);
      expect(
        t.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
        '3.5',
      );
      expect(form.currentState!.validate(), true);
      await t.enterText(find.byType(TextFormField), '2,5');
      await t.pump();
      expect(ml, VolumeUnit.oz.toMl(2.5));
      for (final bad in ['', '-1', '0', 'NaN', 'Infinity', 'abc', '100']) {
        await t.enterText(find.byType(TextFormField), bad);
        await t.pump();
        expect(form.currentState!.validate(), false, reason: bad);
      }
    },
  );
  testWidgets(
    'small-screen large-text oz control retains labels and validation',
    (t) async {
      t.view.physicalSize = const Size(320, 640);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      final form = GlobalKey<FormState>();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: form,
                child: VolumeField(
                  label: 'Milk pumped',
                  initialUnit: VolumeUnit.oz,
                  onChanged: (_) {},
                  onUnitChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.enterText(find.byType(TextFormField), '100');
      form.currentState!.validate();
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Milk pumped (oz)'), findsOneWidget);
    },
  );
}
