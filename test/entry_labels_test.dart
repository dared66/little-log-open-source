import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:little_log/widgets/care_entry_form.dart';

void main() {
  testWidgets(
    'All ten activity headings stay tight and consistent when adding or editing',
    (t) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() => c.createLocal('Family', 'Robin'));
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      const labels = {
        'bottle': 'Bottle',
        'nursing': 'Nursing',
        'diaper': 'Diaper',
        'sleep': 'Sleep',
        'pumping': 'Pumping',
        'solids': 'Solids',
        'growth': 'Growth',
        'health': 'Health',
        'routine': 'Routine',
        'milestone': 'Milestone',
      };
      for (final entry in labels.entries) {
        for (final editing in [false, true]) {
          final original = editing
              ? Feeding(
                  id: 'old-${entry.key}',
                  familyId: c.family!.id,
                  at: DateTime.now(),
                  method: entry.key,
                  minutes: 5,
                )
              : null;
          final page = switch (entry.key) {
            'bottle' => BottleEntryForm(controller: c, original: original),
            'nursing' => NursingEntryForm(controller: c, original: original),
            'diaper' => DiaperEntryForm(controller: c, original: original),
            _ => ActivityForm(
              controller: c,
              method: entry.key,
              original: original,
            ),
          };
          await t.pumpWidget(MaterialApp(home: Scaffold(body: page)));
          await t.pumpAndSettle();
          expect(
            t.widget<FormHeading>(find.byType(FormHeading)).title,
            entry.value,
            reason: '${entry.key}, editing=$editing',
          );
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
        }
      }
    },
  );
}
