import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/controller.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/widgets/activity_panel.dart';
import 'package:little_log/widgets/care_entry_form.dart';
import 'package:little_log/widgets/volume_field.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;

const channel = MethodChannel('app.littlelog/assistant');

Future<AppController> setup(WidgetTester t) async {
  final db = (await t.runAsync(
    () => databaseFactoryMemory.openDatabase(newId.v4()),
  ))!;
  final auth = GoogleAuth();
  final c = AppController(Repository(db), auth, GoogleDrive(auth))
    ..loading = false;
  await t.runAsync(() => c.createLocal('Test family', 'Robin'));
  addTearDown(() async {
    c.dispose();
    await db.close();
  });
  return c;
}

Map<String, Object> packet(
  String action, {
  String id = 'android-test',
  String? kind,
}) => {
  'id': id,
  'action': action,
  'kind': ?kind,
  'at': DateTime.now().millisecondsSinceEpoch,
  'deadline': DateTime.now()
      .add(const Duration(seconds: 15))
      .millisecondsSinceEpoch,
};

Future<void> settle(WidgetTester t) async {
  await t.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  await t.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final theme in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets(
      'history query displays the answer at large text in ${theme.name} without writing a log',
      (t) async {
        t.view.physicalSize = const Size(320, 640);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.textScaleFactorTestValue = 1.8;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
        final c = await setup(t);
        c.themeMode = theme;
        final now = DateTime.now();
        await t.runAsync(
          () => c.repository.add(
            Feeding(
              id: 'sleep-history',
              familyId: c.family!.id,
              method: 'sleep',
              at: now.subtract(const Duration(hours: 5)),
              endedAt: now.subtract(const Duration(hours: 3)),
            ),
          ),
        );
        final replies = <Map>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'listen') return [packet('last_wake')];
          if (call.method == 'complete') replies.add(call.arguments as Map);
          return true;
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle(t);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('When did the baby last wake up?'), findsOneWidget);
        expect(
          replies.single['message'],
          contains('Robin’s last recorded wake-up was'),
        );
        expect(replies.single['query'], true);
        expect(
          (await t.runAsync(() => c.repository.feeds(c.family!.id)))!.length,
          1,
        );
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('Done'));
        await t.tap(find.text('Done'));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  for (final action in ['open_diaper', 'open_nursing', 'review_pumping']) {
    testWidgets(
      '$action opens the matching form without making a premature entry',
      (t) async {
        final c = await setup(t);
        if (action == 'review_pumping') {
          await t.runAsync(() async {
            await c.startActivityTimer('pumping');
            await c.performLiveTimerAction(
              sessionId: c.timers.single.id,
              familyId: c.family!.id,
              method: 'pumping',
              action: 'pause',
              at: DateTime.now(),
            );
          });
        }
        final timerId = c.timers.firstOrNull?.id;
        final replies = <Map>[];
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          if (call.method == 'listen') return [packet(action)];
          if (call.method == 'complete') replies.add(call.arguments as Map);
          return true;
        });
        await t.pumpWidget(LittleLogApp(controller: c));
        await settle(t);
        expect(replies.single['error'], isNull);
        expect(c.feeds, isEmpty);
        if (action == 'open_diaper') {
          expect(find.byType(DiaperEntryForm), findsOneWidget);
        }
        if (action == 'open_nursing') {
          expect(find.byType(TimedActivityFlow), findsOneWidget);
          expect(c.nursing, isNull);
        }
        if (action == 'review_pumping') {
          expect(find.byType(ActivityForm), findsOneWidget);
          expect(c.timers.single.id, timerId);
          await t.tap(find.text('Save pumping'));
          await t.pumpAndSettle();
          expect(c.timers.single.id, timerId);
          expect(c.feeds, isEmpty);
          await t.enterText(
            find.descendant(
              of: find.byType(VolumeField),
              matching: find.byType(TextFormField),
            ),
            '90',
          );
          await t.tap(find.text('Save pumping'));
          await settle(t);
          expect(c.timers, isEmpty);
          expect(c.feeds.single.id, timerId);
          expect(c.feeds.single.amountMl, 90);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'Android direct diaper callback acknowledges the real save and does not duplicate replay',
    (t) async {
      final c = await setup(t);
      final request = packet('add_diaper', kind: 'wet');
      final replies = <Map>[];
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'listen') return [request];
        if (call.method == 'complete') {
          expectSync(c.feeds.single.diaperKind, 'wet');
          replies.add(call.arguments as Map);
        }
        return true;
      });
      await t.pumpWidget(LittleLogApp(controller: c));
      await settle(t);
      expect(replies.single['message'], 'Added a wet diaper for Robin.');
      final received = Completer<void>();
      await t.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('received', request),
        ),
        (_) => received.complete(),
      );
      await settle(t);
      await received.future;
      expect(c.feeds.length, 1);
      expect(replies.length, 2);
      await t.pumpWidget(const SizedBox());
    },
  );
}
