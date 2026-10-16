import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/widgets/toggle_pill.dart';
import 'support/test_fonts.dart';

void main() {
  for (final scale in [1.0, 1.8]) {
    testWidgets(
      'boolean pills are compact, accessible and usable at $scale text',
      (t) async {
        await t.runAsync(loadTestFonts);
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        var value = false;
        var enabled = true;
        late StateSetter update;
        final captureKey = GlobalKey();
        final semantics = t.ensureSemantics();

        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: logBackground,
              colorScheme: ColorScheme.fromSeed(
                seedColor: logActionInk,
                surface: logBackground,
              ),
            ),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return RepaintBoundary(
                    key: captureKey,
                    child: Scaffold(
                      body: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            BooleanSelection(
                              label: 'Diaper rash',
                              value: value,
                              onChanged: enabled
                                  ? (v) => setState(() => value = v)
                                  : null,
                            ),
                            BooleanSelection(
                              label: 'Replace the earlier Nara backfill',
                              value: false,
                              subtitle:
                                  'Only replaces matching entries from the original conversion. Other manual entries remain.',
                              onChanged: (_) {},
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        final yes = find.byKey(const ValueKey('Diaper rash-true'));
        final no = find.byKey(const ValueKey('Diaper rash-false'));
        expect(
          t.getSemantics(no).flagsCollection.isSelected.toBoolOrNull(),
          true,
        );
        await t.tap(yes);
        await t.pumpAndSettle();
        expect(value, true);
        expect(
          t.getSemantics(yes).flagsCollection.isSelected.toBoolOrNull(),
          true,
        );
        expect(
          t.getSemantics(no).flagsCollection.isSelected.toBoolOrNull(),
          false,
        );
        expect(
          t
              .widget<Material>(
                find.ancestor(of: yes, matching: find.byType(Material)).first,
              )
              .color,
          logActionTint,
        );
        expect(find.byIcon(Icons.check), findsNothing);
        expect(
          t.getSize(find.byType(TogglePill<bool>).first).height,
          lessThanOrEqualTo(40),
        );
        expect(
          t.getSize(find.byType(TogglePill<bool>).first).width,
          lessThan(150),
        );
        expect(t.takeException(), isNull);
        if (Platform.environment['CAPTURE_PILLS'] == '1') {
          await t.runAsync(() async {
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final image = await boundary.toImage();
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            final dir = Directory('../output/toggle-pills46');
            await dir.create(recursive: true);
            await File(
              '${dir.path}/boolean-$scale.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        update(() => enabled = false);
        await t.pumpAndSettle();
        expect(
          t.getSemantics(no).flagsCollection.isEnabled.toBoolOrNull(),
          false,
        );
        await t.tap(no);
        await t.pumpAndSettle();
        expect(value, true);
        semantics.dispose();
      },
    );
  }
}
