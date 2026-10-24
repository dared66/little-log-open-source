import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/baby_picker.dart';
import 'package:little_log/widgets/activity_flow.dart';
import '../test/entry_time_test.dart' as date_tests;
import '../test/delete_scope_test.dart' as delete_tests;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  delete_tests.deleteScopeTests(
    capture: (tester, name) async {
      if (!const bool.fromEnvironment('CAPTURE_REVIEW')) return;
      if (Platform.isAndroid) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
      }
      await binding.takeScreenshot(name);
    },
  );
  date_tests.main();
  testWidgets('native storage reopen, timer recovery and baby isolation', (
    t,
  ) async {
    final support = await getApplicationSupportDirectory();
    final directory = await support.createTemp('qa-recovery-');
    final path = '${directory.path}/review.db';
    var db = await databaseFactoryIo.openDatabase(path);
    AppController controller() {
      final auth = GoogleAuth();
      return AppController(Repository(db), auth, GoogleDrive(auth));
    }

    var c = controller();
    await c.initialize();
    expect(c.message, isNull);
    await c.createLocal('Test family', 'QA Robin');
    await c.addFeed(
      at: DateTime.now(),
      method: 'bottle',
      amountMl: 90,
      note: 'Before restart',
    );
    await c.startActivityTimer('sleep');
    final baby = c.family!;
    final timer = c.timers.single;
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await t.pumpAndSettle();
    expect(c.timers.single.id, timer.id);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
    db = await databaseFactoryIo.openDatabase(path);
    c = controller();
    await c.initialize();
    expect(c.family!.id, baby.id);
    expect(c.feeds.single.amountMl, 90);
    expect(c.timers.single.id, timer.id);
    expect(c.timers.single.startedAt, timer.startedAt);
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    expect(find.byType(ActiveSessions), findsOneWidget);
    Future<void> tap(Finder finder) async {
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.tap(finder);
      await t.pumpAndSettle();
    }

    await tap(find.text('Settings').last);
    await tap(find.text('Manage baby'));
    await tap(find.text('Add baby'));
    await tap(find.text('This device'));
    await t.enterText(find.byType(TextFormField), 'QA Alex');
    await tap(find.widgetWithText(FilledButton, 'Create baby log'));
    expect(c.family!.babyName, 'QA Alex');
    expect(c.feeds, isEmpty);
    expect(c.timers, isEmpty);
    await tap(find.byTooltip('Close').last);
    await tap(find.text('Log').last);
    await tap(find.byType(BabyPickerButton));
    await tap(find.text('QA Robin').last);
    expect(c.timers.single.id, timer.id);
    expect(c.feeds.single.note, 'Before restart');
    // A system-back cancellation must preserve the durable timer.
    await tap(
      find
          .descendant(
            of: find.byType(ActiveSessions),
            matching: find.byType(ListTile),
          )
          .first,
    );
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    expect(c.timers.single.id, timer.id);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });
}
