import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'support/test_fonts.dart';
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
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final scale in [1.0, 1.6, 2.0]) {
      testWidgets('visible baby switcher on $platform at scale $scale', (
        t,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        t.view.physicalSize = const Size(320, 700);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        await t.runAsync(() async {
          await loadTestFonts();
          if (Platform.isMacOS) {
            for (final family in [
              'CupertinoSystemText',
              'CupertinoSystemDisplay',
            ]) {
              final loader = FontLoader(family)
                ..addFont(
                  File(
                    '/System/Library/Fonts/SFNS.ttf',
                  ).readAsBytes().then(ByteData.sublistView),
                );
              await loader.load();
            }
          }
        });
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = GoogleAuth();
        const baby = Family(id: 'qa', name: 'QA', babyName: 'Alexandra Rose');
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false
          ..family = baby
          ..families = [
            baby,
            const Family(id: 'other', name: 'QA', babyName: 'Robin'),
          ];
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pumpAndSettle();
        final switcher = find.byKey(const ValueKey('baby-switcher'));
        final arrow = find.descendant(
          of: switcher,
          matching: find.byIcon(Icons.expand_more),
        );
        expect(arrow, findsOneWidget);
        expect(t.getSize(switcher).height, greaterThanOrEqualTo(48));
        expect(t.getTopLeft(find.text(baby.babyName)).dx, 20);
        expect(t.getRect(switcher).contains(t.getCenter(arrow)), isTrue);
        expect(
          t
              .getRect(switcher)
              .overlaps(
                t.getRect(find.byKey(const ValueKey('log-day-picker'))),
              ),
          isFalse,
        );
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE')) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../output/baby-switcher61/${platform.name}-$scale.png',
            ),
          );
        }
        await t.tap(arrow);
        await t.pumpAndSettle();
        expect(find.text('Switch baby'), findsOneWidget);
        expect(find.text('Robin'), findsOneWidget);
        expect(find.byIcon(Icons.check), findsOneWidget);
        expect(t.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE') && scale == 1.0) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../output/baby-switcher61/${platform.name}-picker.png',
            ),
          );
        }
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
