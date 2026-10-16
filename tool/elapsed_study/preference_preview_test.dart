import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/widgets/seam_elapsed_glyph.dart';
import '../../test/elapsed_icon_preference_test.dart'
    show localController, customize;
import '../elapsed_icon_mockup.dart' show sampleElapsed;
import 'render_test.dart' show saveCapture;

void main() {
  for (final theme in [ThemeMode.dark, ThemeMode.light]) {
    testWidgets('render actual optional elapsed icons ${theme.name}', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await t.runAsync(() async {
        for (final font in [
          'CupertinoSystemText',
          'CupertinoSystemDisplay',
          'MaterialIcons',
        ]) {
          final path = font == 'MaterialIcons'
              ? '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
              : '/System/Library/Fonts/SFNS.ttf';
          await (FontLoader(font)
                ..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
              .load();
        }
      });
      final c = await localController(t);
      c.themeMode = theme;
      c.quickLog = sampleElapsed.keys.toList();
      final now = DateTime.now();
      // Isolated synthetic records, never real logs or connected data.
      c.feeds = [
        for (final entry in sampleElapsed.entries)
          Feeding(
            id: entry.key,
            familyId: c.family!.id,
            method: entry.key,
            at: now.subtract(entry.value!),
          ),
      ];
      await t.pumpWidget(
        RepaintBoundary(
          key: const ValueKey('preference-capture'),
          child: LittleLogApp(controller: c),
        ),
      );
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-regular',
        pixelRatio: 1,
      );
      expect(find.byType(SeamElapsedGlyph), findsNothing);
      await t.tap(customize());
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-customize-off',
        pixelRatio: 1,
      );
      await t.tap(find.byKey(const ValueKey('show-elapsed-in-icons')));
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-customize-on',
        pixelRatio: 1,
      );
      await t.pageBack();
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-elapsed',
        pixelRatio: 1,
      );
      await t.tap(find.text('See all activities'));
      await t.pumpAndSettle();
      for (final method in activityCatalog.keys) {
        expect(find.byKey(ValueKey('activity-picker-$method')), findsOneWidget);
      }
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-picker-top',
        pixelRatio: 1,
      );
      // Expanded test viewport shows the complete scrollable list in one
      // review capture; normal phone-size top/bottom captures remain separate.
      t.view.physicalSize = const Size(390, 1120);
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-picker-full',
        pixelRatio: 1,
      );
      t.view.physicalSize = const Size(390, 844);
      await t.pumpAndSettle();
      await t.ensureVisible(
        find.byKey(const ValueKey('activity-picker-milestone')),
      );
      await t.pumpAndSettle();
      await saveCapture(
        t,
        'preference-capture',
        'optional-${theme.name}-picker-bottom',
        pixelRatio: 1,
      );
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
