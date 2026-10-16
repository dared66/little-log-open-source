import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:little_log/design.dart';
import 'package:little_log/activity_details.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';

void main() {
  testWidgets('phone forms save each activity and show field validation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = (await tester.runAsync(
      () => databaseFactoryMemory.openDatabase('extended-ui'),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth));
    await tester.runAsync(() async {
      // Gesture hints have separate coverage; keep form/history assertions
      // independent of their background persistence during teardown.
      await c.repository.saveSwipeDemoSeen();
      await c.initialize();
      await c.createLocal('Family', 'Robin');
    });
    Future<void> open(String method) async {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(method),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => ActivityForm(controller: c, method: method),
                ),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FormHeading>(find.byType(FormHeading)).title,
        activityNames[method],
      );
    }

    Future<void> fill(String label, String text) async {
      final field = find.widgetWithText(TextFormField, label);
      await tester.ensureVisible(field);
      await tester.enterText(field, text);
    }

    Future<void> save(String method) async {
      final button = find.text('Save $method');
      await tester.ensureVisible(button);
      await tester.runAsync(() async {
        await tester.tap(button);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await open('sleep');
    final endTime = find.byKey(const ValueKey('Ended-time'));
    await tester.ensureVisible(endTime);
    await tester.tap(endTime);
    await tester.pumpAndSettle();
    final beforeNow = DateTime.now();
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(c.feeds, isEmpty);
    final selectedEnd = tester
        .widgetList<EntryTime>(find.byType(EntryTime))
        .singleWhere((field) => field.label == 'Ended')
        .value;
    expect(selectedEnd.isBefore(beforeNow), isFalse);
    await save('sleep');
    expect(c.feeds.single.endedAt, selectedEnd.toUtc());
    await open('pumping');
    await save('pumping');
    expect(find.text('Enter Milk pumped (ml)'), findsOneWidget);
    await fill('Milk pumped (ml)', '80');
    await save('pumping');
    await open('solids');
    await fill('Food / foods', 'Banana');
    await save('solids');
    await open('growth');
    await fill('Measured value (kg)', '4.5');
    await save('growth');
    await open('health');
    await fill('Medicine name', 'As recorded');
    await fill('Dose given (include unit)', '1 ml');
    await save('health');
    await open('routine');
    await fill('Routine (e.g. tummy time, bath)', 'Bath');
    await save('routine');
    await open('milestone');
    await fill('Milestone (e.g. first smile)', 'First smile');
    await save('milestone');
    expect(c.feeds.length, 7);
    expect(c.feeds.where((f) => f.method == 'pumping').single.amountMl, 80);
    await tester.pumpWidget(MaterialApp(home: ActivityHistory(controller: c)));
    await tester.pumpAndSettle();
    // The default pumping interval starts one hour ago. Early-morning runs
    // must view yesterday to check its row and daily pumping total.
    final pumped = c.feeds.singleWhere((f) => f.method == 'pumping');
    if (!DateUtils.isSameDay(pumped.at.toLocal(), DateTime.now())) {
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Previous day'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }
    expect(find.text('Pumped'), findsOneWidget);
    expect(find.text('80 ml'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(db.close);
  });
}
