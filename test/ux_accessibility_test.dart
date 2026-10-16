import 'package:little_log/widgets/care_entry_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:little_log/main.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/widgets/activity_panel.dart';

void main() {
  testWidgets('missing Drive log warning stays readable on a small phone', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase('missing-drive-warning'),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false
      ..family = const Family(
        id: 'family',
        name: 'Family',
        babyName: 'Alexandria Robin',
        driveFileId: 'missing-log',
        accountId: 'account',
      )
      ..unavailableDriveFileId = 'missing-log';
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    expect(
      find.text('Alexandria Robin’s Drive log is unavailable'),
      findsOneWidget,
    );
    await t.ensureVisible(find.text('Retry sync'));
    await t.pumpAndSettle();
    expect(find.text('Retry sync').hitTestable(), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  testWidgets('small phone and large text keep navigation and save reachable', (
    t,
  ) async {
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1;
    t.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase('large-text'),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false
      ..family = const Family(
        id: 'test',
        name: 'Family',
        babyName: 'Alexandria Robin',
      );
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.byKey(const ValueKey('log-day-picker')));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Settings').last);
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Log').last);
    await t.pumpAndSettle();
    Future<void> open(Widget w) async {
      showModalBottomSheet<void>(
        context: t.element(find.byType(HomePage)),
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => w,
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    }

    for (final method in ['bottle', 'nursing', 'diaper']) {
      await open(switch (method) {
        'bottle' => BottleEntryForm(controller: c),
        'nursing' => NursingEntryForm(controller: c),
        _ => DiaperEntryForm(controller: c),
      });
      final save = find.widgetWithText(FilledButton, 'Save $method');
      expect(save.hitTestable(), findsOneWidget);
      if (method == 'bottle') {
        t.view.viewInsets = const FakeViewPadding(bottom: 260);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(save.hitTestable(), findsOneWidget);
        t.view.resetViewInsets();
      }
      Navigator.of(t.element(save)).pop();
      await t.pumpAndSettle();
    }
    for (final method in [
      'sleep',
      'pumping',
      'solids',
      'growth',
      'health',
      'routine',
      'milestone',
    ]) {
      await open(ActivityForm(controller: c, method: method));
      expect(
        find.widgetWithText(FilledButton, 'Save $method').hitTestable(),
        findsOneWidget,
      );
      if (method == 'growth') {
        await t.ensureVisible(
          find.byType(DropdownButtonFormField<String>).first,
        );
        await t.tap(find.byType(DropdownButtonFormField<String>).first);
        await t.pumpAndSettle();
        await t.tap(find.text('Head circumference').last);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      }
      Navigator.of(t.element(find.byType(ActivityForm))).pop();
      await t.pumpAndSettle();
    }
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });

  testWidgets(
    'history keeps its day and filter across tabs; all logging categories stay reachable',
    (t) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase('navigation-state'),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false
        ..family = const Family(
          id: 'family',
          name: 'Family',
          babyName: 'Robin',
        );
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('log-day-picker')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('log-day-picker')));
      await t.pumpAndSettle();
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      if (yesterday.month != DateTime.now().month) {
        await t.tap(find.byTooltip('Previous month'));
        await t.pumpAndSettle();
      }
      await t.tap(find.text('${yesterday.day}').last);
      await t.tap(find.text('Show day'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(find.text('View all'), 150);
      await t.pumpAndSettle();
      await t.tap(find.text('View all'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.byType(DropdownButtonFormField<String>),
        150,
      );
      await t.pumpAndSettle();
      await t.tap(find.byType(DropdownButtonFormField<String>));
      await t.pumpAndSettle();
      await t.tap(find.text('Bottle').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Settings').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Log').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('log-day-picker')));
      await t.pumpAndSettle();
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(
        t
            .state<FormFieldState<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .value,
        'bottle',
      );
      await t.scrollUntilVisible(find.text('Back to today'), -200);
      expect(find.text('Back to today'), findsOneWidget);
      await t.tap(find.text('Log').last);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('See all activities'));
      await t.pumpAndSettle();
      await t.tap(find.text('See all activities'));
      await t.pumpAndSettle();
      for (final label in [
        'Bottle',
        'Nursing',
        'Diaper',
        'Sleep',
        'Pumping',
        'Solids',
        'Growth',
        'Health',
        'Routine',
        'Milestone',
      ]) {
        final row = find.widgetWithText(ListTile, label);
        await t.ensureVisible(row);
        await t.pumpAndSettle();
        expect(row.hitTestable(), findsOneWidget);
      }
      await t.tap(find.widgetWithText(ListTile, 'Milestone'));
      await t.pumpAndSettle();
      expect(find.byType(ActivityForm), findsOneWidget);
      expect(find.text('Save milestone').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );
}
