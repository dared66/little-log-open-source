import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';

// Run explicitly with --update-goldens to produce review images from real widgets.
void main() {
  testWidgets('capture bottle, nursing and detailed diaper screens', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    for (final font in ['Roboto', 'MaterialIcons']) {
      final loader = FontLoader(font)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${font == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
              ).readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
    }
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase('care-captures'),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => c.createLocal('Sample family', 'Robin'));
    Future<void> open(Widget child) async {
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      showModalBottomSheet<void>(
        context: t.element(find.byType(HomePage)),
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => child,
      );
      await t.pumpAndSettle();
    }

    Future<void> snap(String name) async {
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../../output/care-review/$name.png'),
      );
    }

    await open(BottleEntryForm(controller: c));
    await snap('bottle');
    await open(NursingEntryForm(controller: c));
    await snap('nursing');
    await open(DiaperEntryForm(controller: c));
    await t.tap(find.text('Dirty'));
    await t.pumpAndSettle();
    await snap('diaper-details');
    await t.ensureVisible(find.widgetWithText(SwitchListTile, 'Blowout'));
    await t.tap(find.widgetWithText(SwitchListTile, 'Blowout'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.widgetWithText(SwitchListTile, 'Diaper rash'));
    expect(
      t
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Diaper rash'),
          )
          .value,
      isFalse,
    );
    await t.pumpAndSettle();
    await snap('diaper-observations');
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: RecordRow(
                volumeUnit: c.volumeUnit,
                record: Feeding(
                  id: 'sample',
                  familyId: 'sample',
                  at: DateTime(2026, 9, 18, 10, 30),
                  method: 'diaper',
                  diaperKind: 'both',
                  details: const {
                    'poopColor': 'mustard',
                    'poopConsistency': 'seedy',
                    'blowout': true,
                    'rash': false,
                  },
                  note: 'Changed outfit',
                  author: 'Sample caregiver',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await snap('saved-diaper');
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });
}
