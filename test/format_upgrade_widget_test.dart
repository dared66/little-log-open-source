import 'support/selection_chip_expectations.dart';
import 'dart:io';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:little_log/main.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/widgets/profile_page.dart';
import 'package:little_log/widgets/import_page.dart';
import 'package:little_log/services/import_file.dart';
import 'support/nara_export_fixture.dart';

void main() {
  testWidgets(
    'new import profile and multi-value forms fit small screens and preserve selections',
    (t) async {
      if (const bool.fromEnvironment('CAPTURE_FORMAT')) {
        for (final name in ['Roboto', 'MaterialIcons']) {
          final loader = FontLoader(name)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File(
                    '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/${name == 'Roboto' ? 'Roboto-Regular.ttf' : 'MaterialIcons-Regular.otf'}',
                  ).readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      }
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() => c.createLocal('Sample', 'Robin'));
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      final theme = t.widget<MaterialApp>(find.byType(MaterialApp)).theme;
      Future<void> show(Widget page) async {
        await t.pumpWidget(
          MaterialApp(
            theme: theme,
            home: RepaintBoundary(key: const ValueKey('capture'), child: page),
          ),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }

      Future<void> shot(String name) async {
        if (!const bool.fromEnvironment('CAPTURE_FORMAT')) return;
        final boundary = t.firstRenderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await t.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ImageByteFormat.png);
          final dir = Directory('../output/format-upgrade-review');
          await dir.create(recursive: true);
          await File(
            '${dir.path}/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await show(Scaffold(body: DiaperEntryForm(controller: c)));
      await t.tap(find.widgetWithText(FilterChip, 'Dirty'));
      await t.pumpAndSettle();
      for (final label in ['Black', 'Green']) {
        final chip = find.widgetWithText(FilterChip, label);
        await t.ensureVisible(chip);
        await t.tap(chip);
        await t.pumpAndSettle();
      }
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Black')).selected,
        true,
      );
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Green')).selected,
        true,
      );
      expectSharedSelectionChips(t);
      await t.tap(find.widgetWithText(FilterChip, 'Black'));
      await t.pumpAndSettle();
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Black')).selected,
        false,
      );
      expect(
        t.widget<FilterChip>(find.widgetWithText(FilterChip, 'Green')).selected,
        true,
      );
      await t.tap(find.widgetWithText(FilterChip, 'Black'));
      await t.pumpAndSettle();
      await shot('mixed-diaper');
      expect(t.takeException(), isNull);
      await show(Scaffold(body: BottleEntryForm(controller: c)));
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Breast milk + formula').last);
      await t.pumpAndSettle();
      await shot('mixed-bottle');
      expect(t.takeException(), isNull);
      await t.runAsync(
        () => c.saveBabyProfile({
          'birthDate': '2026-01-01',
          'nightStart': '19:00',
          'nightEnd': '07:00',
        }, c.family!.id),
      );
      await show(ProfilePage(controller: c));
      await shot('profile');
      await show(
        ImportPage(
          controller: c,
          pickFile: () async => ImportFile('nara.json', naraExportFixture()),
        ),
      );
      await t.runAsync(() async {
        await t.tap(find.text('Choose file'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.text('Review import'), findsOneWidget);
      await t.ensureVisible(find.text('Import these entries'));
      await t.pumpAndSettle();
      await shot('import-preview');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );
}
