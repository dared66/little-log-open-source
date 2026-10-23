import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';

// Actual device metrics and safe areas throughout; no fake viewport or scale.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('native ${mode.name} layouts use the real phone density', (
      t,
    ) async {
      var surfaceConverted = false;
      final expectedDpr = double.tryParse(
        const String.fromEnvironment('NATIVE_QA_EXPECTED_DPR'),
      );
      if (Platform.isAndroid) {
        expect(
          expectedDpr,
          isNotNull,
          reason:
              'Use scripts/run_native_tests.py to verify the Android display baseline.',
        );
      }
      if (expectedDpr != null) {
        expect(t.view.devicePixelRatio, closeTo(expectedDpr, .001));
      }
      final metrics = {
        'physical_width': t.view.physicalSize.width,
        'physical_height': t.view.physicalSize.height,
        'device_pixel_ratio': t.view.devicePixelRatio,
        'logical_width': t.view.physicalSize.width / t.view.devicePixelRatio,
        'logical_height': t.view.physicalSize.height / t.view.devicePixelRatio,
      };
      // ignore: avoid_print
      print('NATIVE_LAYOUT_METRICS ${jsonEncode(metrics)}');
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = GoogleAuth()..ready = true;
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      addTearDown(() async {
        c.dispose();
        await db.close();
      });
      await t.runAsync(() => c.setThemeMode(mode));
      final folder = Platform.isAndroid
          ? (await getExternalStorageDirectory())!
          : await getApplicationSupportDirectory();
      final shots = Directory('${folder.path}/qa-native-density');
      await shots.create(recursive: true);
      Future<void> capture(String stage) async {
        expect(t.takeException(), isNull, reason: stage);
        if (Platform.isAndroid && !surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          await t.pump();
          surfaceConverted = true;
        }
        final name = '${mode.name}-$stage';
        final bytes = await binding.takeScreenshot(name);
        await File('${shots.path}/$name.png').writeAsBytes(bytes);
        // ignore: avoid_print
        print('NATIVE_DENSITY_SCREENSHOT ${shots.path}/$name.png');
      }

      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      final headline = t.getRect(find.text('Baby logs'));
      final title = t.getRect(find.text('Little Log'));
      final next = t.getRect(find.widgetWithText(FilledButton, 'New baby log'));
      final join = t.getRect(
        find.widgetWithText(OutlinedButton, 'Join an existing baby log'),
      );
      expect(title.left, closeTo(headline.left, .1));
      for (final rect in [join, next]) {
        expect(rect.left, closeTo(headline.left, .1));
        expect(rect.right, closeTo(headline.right, .1));
      }
      await capture('onboarding');
      await t.runAsync(() async {
        await c.createLocal('Synthetic QA', 'Robin');
        await c.addDiaper(kind: 'both', at: DateTime.now());
        await c.addFeed(
          at: DateTime.now(),
          method: 'bottle',
          amountMl: 90,
          note: '',
        );
      });
      await t.pumpAndSettle();
      await capture('home');
      for (final method in activityCatalog.keys) {
        unawaited(openActivity(t.element(find.byType(HomePage)), c, method));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull, reason: method);
        final action = find.byType(FilledButton).last;
        expect(action.hitTestable(), findsOneWidget, reason: method);
        expect(t.getSize(action).height, greaterThanOrEqualTo(44));
        if ([
          'bottle',
          'diaper',
          'nursing',
          'sleep',
          'pumping',
        ].contains(method)) {
          await capture(method);
        }
        await t.binding.handlePopRoute();
        await t.pumpAndSettle();
      }
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await capture('settings');
      await t.ensureVisible(find.text('Units'));
      await t.tap(find.text('Units'));
      await t.pumpAndSettle();
      await capture('units');
      await t.pageBack();
      await t.pumpAndSettle();
      final help = find.byKey(const ValueKey('assistant-help'));
      await t.ensureVisible(help);
      await t.pumpAndSettle();
      await t.tap(help);
      await t.pumpAndSettle();
      await capture('assistant-help');
      // Help now starts with two collapsed sections that fit on the phone.
      // Expand real content before asserting that native scrolling works.
      await t.tap(
        find.text(Platform.isIOS ? 'Use Siri' : 'Use Google Assistant'),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('Diapers'));
      await t.pumpAndSettle();
      final scroll = find.byType(Scrollable).first;
      final state = t.state<ScrollableState>(scroll);
      expect(state.position.maxScrollExtent, greaterThan(0));
      final frame = t.getRect(scroll);
      // Exercise real device gestures away from selectable example text.
      final origin = Offset(frame.left + 8, frame.center.dy);
      await t.dragFrom(origin, const Offset(0, -300));
      await t.pumpAndSettle();
      final offset = state.position.pixels;
      expect(offset, greaterThan(0));
      await t.dragFrom(origin, const Offset(0, 300));
      await t.pumpAndSettle();
      expect(state.position.pixels, lessThan(offset));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
