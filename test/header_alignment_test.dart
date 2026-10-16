import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;

void main() {
  for (final size in [const Size(390, 844), const Size(1024, 600)]) {
    testWidgets('header aligns with content at $size', (t) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false
        ..family = const Family(id: 'qa', name: 'QA', babyName: 'Robin');
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      final calendar = find.descendant(
        of: find.byKey(const ValueKey('log-day-picker')),
        matching: find.byWidgetPredicate(
          (w) => w is CustomPaint && w.size.width > 0,
        ),
      );
      final bottle = find.widgetWithText(OutlinedButton, 'Bottle');
      final nursing = find.widgetWithText(OutlinedButton, 'Nursing');
      expect(
        t.getTopLeft(find.text('Robin')).dx,
        closeTo(t.getTopLeft(bottle).dx, .1),
      );
      expect(
        t.getTopRight(calendar).dx,
        closeTo(t.getTopRight(nursing).dx, .1),
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    });
  }
}
