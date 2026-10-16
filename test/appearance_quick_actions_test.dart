import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/services/home_quick_actions.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/widgets/appearance_page.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'support/test_fonts.dart';

const channel = MethodChannel('app.littlelog/quick_actions');

class AppearanceTestAuth extends GoogleAuth {
  @override
  Future<void> initialize() async {}
}

Future<AppController> controllerFor(WidgetTester t) async {
  final db = (await t.runAsync(
    () => databaseFactoryMemory.openDatabase(newId.v4()),
  ))!;
  final auth = AppearanceTestAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth))
    ..loading = false;
  await t.runAsync(() => c.createLocal('Test family', 'Robin'));
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

Future<void> deliver(WidgetTester t, String action) async {
  await t.binding.defaultBinaryMessenger.handlePlatformMessage(
    channel.name,
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('received', action),
    ),
    (_) {},
  );
  await t.pump();
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await t.pumpAndSettle();
}

Future<void> capture(WidgetTester t, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_APPEARANCE')) return;
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture-root')),
  );
  await t.runAsync(() async {
    final pixels = await boundary.toImage(pixelRatio: 1);
    final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../output/usability-dark-mode/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    pixels.dispose();
  });
}

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'appearance follows system, persists, and switches live in Settings',
    (t) async {
      final c = await controllerFor(t);
      t.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      expect(
        Theme.of(t.element(find.byType(HomePage))).brightness,
        Brightness.dark,
      );
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('appearance-light')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      expect(c.themeMode, ThemeMode.light);
      expect(await t.runAsync(c.repository.themeMode), 'light');
      expect(
        Theme.of(t.element(find.byType(AppearancePage))).brightness,
        Brightness.light,
      );
      await t.tap(find.byKey(const ValueKey('appearance-dark')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      expect(await t.runAsync(c.repository.themeMode), 'dark');
      // Reload the same database, as on the next app launch.
      await t.runAsync(c.initialize);
      await t.pumpAndSettle();
      expect(c.themeMode, ThemeMode.dark);
      expect(
        Theme.of(t.element(find.byType(AppearancePage))).brightness,
        Brightness.dark,
      );
      await t.tap(find.byKey(const ValueKey('appearance-system')));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await t.pumpAndSettle();
      t.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await t.pumpAndSettle();
      expect(c.themeMode, ThemeMode.system);
      expect(
        Theme.of(t.element(find.byType(AppearancePage))).brightness,
        Brightness.light,
      );
      expect(t.takeException(), isNull);
    },
  );

  for (final action in ['nursing_left', 'nursing_right', 'sleep']) {
    testWidgets(
      '$action cold launch waits for load, starts once, and survives refresh',
      (t) async {
        final c = await controllerFor(t);
        c.loading = true;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => action,
        );
        await t.pumpWidget(LittleLogApp(controller: c));
        await t.pump();
        expect(c.nursing, isNull);
        expect(c.timers, isEmpty);
        c.loading = false;
        await t.runAsync(c.refresh);
        await t.pump();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await t.pumpAndSettle();
        if (action == 'sleep') {
          expect(c.timers.single.method, 'sleep');
          final id = c.timers.single.id;
          final started = c.timers.single.startedAt;
          await deliver(t, action);
          expect(c.timers.single.id, id);
          expect(c.timers.single.startedAt, started);
          await t.runAsync(c.refresh);
          expect(c.timers.single.id, id);
        } else {
          expect(c.nursing!.side, action == 'nursing_left' ? 'left' : 'right');
          final id = c.nursing!.id;
          final started = c.nursing!.startedAt;
          await deliver(
            t,
            action == 'nursing_left' ? 'nursing_right' : 'nursing_left',
          );
          expect(c.nursing!.id, id);
          expect(c.nursing!.startedAt, started);
          expect(c.nursing!.side, action == 'nursing_left' ? 'left' : 'right');
          await t.runAsync(c.refresh);
          expect(c.nursing!.id, id);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'warm diaper shortcut opens form without saving and replaces previous sheet',
    (t) async {
      final c = await controllerFor(t);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      await deliver(t, 'sleep');
      await deliver(t, 'diaper');
      expect(find.byType(DiaperEntryForm), findsOneWidget);
      expect(c.feeds, isEmpty);
      expect(c.timers.single.method, 'sleep');
      await deliver(t, 'unknown');
      expect(find.byType(DiaperEntryForm), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'dark screens fit a small phone with large text and retain contrast',
    (t) async {
      t.view.physicalSize = const Size(320, 720);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      final c = await controllerFor(t);
      await t.runAsync(() async {
        await c.setThemeMode(ThemeMode.dark);
        await c.addDiaper(kind: 'both', at: DateTime.now());
      });
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('capture-root'),
          child: LittleLogApp(controller: c),
        ),
      );
      await t.pumpAndSettle();
      final ctx = t.element(find.byType(HomePage));
      final palette = logPalette(ctx);
      double contrast(Color a, Color b) {
        final aa = a.computeLuminance(), bb = b.computeLuminance();
        return (aa > bb ? aa + .05 : bb + .05) /
            (aa > bb ? bb + .05 : aa + .05);
      }

      expect(contrast(palette.ink, palette.surface), greaterThan(4.5));
      expect(contrast(palette.secondary, palette.surface), greaterThan(4.5));
      expect(contrast(palette.actionInk, palette.actionTint), greaterThan(4.5));
      for (final method in activityColors.keys) {
        expect(
          contrast(
            activityAccent(method, context: ctx),
            activityTint(method, context: ctx),
          ),
          greaterThan(4.5),
        );
      }
      await capture(t, 'small-large-text-home');
      expect(t.takeException(), isNull);
      await deliver(t, 'diaper');
      await capture(t, 'small-large-text-diaper');
      expect(t.takeException(), isNull);
      Navigator.of(t.element(find.byType(DiaperEntryForm))).pop();
      await t.pumpAndSettle();
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Appearance'));
      await t.pumpAndSettle();
      await capture(t, 'small-large-text-appearance');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    },
  );

  testWidgets('dark history and timers use the same appearance', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.runAsync(loadTestFonts);
    final c = await controllerFor(t);
    await t.runAsync(() async {
      await c.setThemeMode(ThemeMode.dark);
      await c.addDiaper(kind: 'both', at: DateTime.now());
      await c.addFeed(
        method: 'bottle',
        amountMl: 90,
        at: DateTime.now(),
        note: '',
      );
    });
    await t.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('capture-root'),
        child: LittleLogApp(controller: c),
      ),
    );
    await t.pumpAndSettle();
    await capture(t, 'dark-home');
    await t.scrollUntilVisible(
      find.byType(RecordRow).first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await capture(t, 'dark-history');
    expect(t.takeException(), isNull);
    await deliver(t, 'nursing_left');
    await capture(t, 'dark-nursing');
    expect(t.takeException(), isNull);
    await deliver(t, 'sleep');
    await capture(t, 'dark-sleep');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  test('launcher catalog exposes the four requested actions', () {
    expect(HomeQuickActions.actions, {
      'diaper',
      'nursing_left',
      'nursing_right',
      'sleep',
    });
  });
}
