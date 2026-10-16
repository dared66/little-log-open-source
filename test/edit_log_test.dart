import "dart:ui" show ImageByteFormat;

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' hide Finder;
import 'package:little_log/controller.dart';
import 'package:little_log/design.dart';
import 'package:little_log/main.dart';
import 'package:little_log/models.dart';
import 'package:little_log/storage/repository.dart';
import 'package:little_log/services/google_auth.dart';
import 'package:little_log/services/google_drive.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'package:little_log/volume.dart';
import 'manual_sync_test.dart' as fake;

void main() {
  final at = DateTime.now().subtract(const Duration(hours: 1));
  Feeding sample(String method, String family) => Feeding(
    id: newId.v4(),
    familyId: family,
    at: at,
    method: method,
    amountMl: ['bottle', 'pumping'].contains(method) ? 73.93382390625 : null,
    minutes: method == 'nursing' ? 1 : null,
    leftSeconds: method == 'nursing' ? 15 : null,
    rightSeconds: method == 'nursing' ? 0 : null,
    endedAt: ['nursing', 'sleep', 'pumping'].contains(method)
        ? at.add(const Duration(seconds: 32, milliseconds: 100))
        : null,
    diaperKind: method == 'diaper' ? 'both' : null,
    note: 'Original note',
    author: 'Original caregiver',
    details: switch (method) {
      'diaper' => {
        'poopColor': 'orange',
        'poopConsistency': 'mushy',
        'blowout': true,
        'rash': false,
      },
      'solids' => {'food': 'Pear', 'reaction': 'No reaction observed'},
      'growth' => {'measurement': 'Weight', 'value': 13.7, 'unit': 'lb'},
      'health' => {'kind': 'Medication', 'name': 'Example', 'dose': '1 ml'},
      'routine' || 'milestone' => {'name': 'Sample activity'},
      _ => {},
    },
  );
  testWidgets('edit nursing can reopen either side as a running timer', (
    t,
  ) async {
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() => c.createLocal('Family', 'Robin'));
    final record = sample('nursing', c.family!.id);
    await t.runAsync(() async {
      await c.repository.add(record);
      await c.refresh();
    });
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();
    final context = t.element(find.byType(Scaffold).first);
    editActivity(context, c, record);
    await t.pumpAndSettle();
    expect(find.text('Resume left timer'), findsOneWidget);
    expect(find.text('Resume right timer'), findsOneWidget);
    await t.runAsync(() async {
      await t.tap(find.text('Resume right timer'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await t.pumpAndSettle();
    expect(c.nursing?.side, 'right');
    expect(c.nursing?.leftSeconds, 15);
    expect(c.nursing?.note, 'Original note');
    expect(c.feeds, isEmpty);
    expect(find.text('Right side running'), findsOneWidget);
  });
  testWidgets('nursing duration edits preserve repeated timer resumption', (
    t,
  ) async {
    final db = (await t.runAsync(
      () => databaseFactoryMemory.openDatabase(newId.v4()),
    ))!;
    final auth = GoogleAuth();
    final c = AppController(Repository(db), auth, GoogleDrive(auth))
      ..loading = false;
    await t.runAsync(() async {
      await c.createLocal('Family', 'Robin');
      await c.repository.add(sample('nursing', c.family!.id));
      await c.refresh();
    });
    await t.pumpWidget(LittleLogApp(controller: c));
    await t.pumpAndSettle();

    Future<void> waitForWrite() async {
      await t.runAsync(() async {
        final elapsed = Stopwatch()..start();
        while (c.recording) {
          if (elapsed.elapsed > const Duration(seconds: 10)) {
            fail('The nursing write did not complete.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
    }

    Future<void> tap(Finder finder) async {
      await waitForWrite();
      await t.ensureVisible(finder);
      await t.pumpAndSettle();
      await t.runAsync(() async {
        await t.tap(finder);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      await waitForWrite();
    }

    for (final side in ['left', 'right', 'left']) {
      final previous = c.feeds.single;
      final previousElapsed = previous.endedAt!.difference(previous.at);
      editActivity(t.element(find.byType(Scaffold).first), c, previous);
      await t.pumpAndSettle();
      final minutes = find.widgetWithText(TextFormField, 'Minutes').first;
      await t.ensureVisible(minutes);
      final currentMinutes = int.parse(
        t.widget<TextFormField>(minutes).controller!.text,
      );
      await t.enterText(minutes, '${currentMinutes + 1}');
      FocusManager.instance.primaryFocus?.unfocus();
      await t.pump(const Duration(milliseconds: 500));
      await tap(find.widgetWithText(FilledButton, 'Save changes'));
      final edited = c.feeds.single;
      expect(edited.leftSeconds, previous.leftSeconds! + 60);
      expect(edited.rightSeconds, previous.rightSeconds);
      final correctedDuration = Duration(
        seconds: edited.leftSeconds! + edited.rightSeconds!,
      );
      if (correctedDuration > previousElapsed) {
        expect(edited.endedAt, isNull);
      } else {
        expect(edited.endedAt!.difference(edited.at), previousElapsed);
      }
      editActivity(t.element(find.byType(Scaffold).first), c, edited);
      await t.pumpAndSettle();
      expect(find.text('Resume left timer'), findsOneWidget);
      expect(find.text('Resume right timer'), findsOneWidget);
      await tap(find.text('Resume $side timer'));
      expect(c.nursing!.side, side);
      expect(c.nursing!.leftSeconds, edited.leftSeconds);
      expect(c.nursing!.rightSeconds, edited.rightSeconds);
      expect(c.feeds, isEmpty);
      await tap(find.widgetWithText(FilledButton, 'Pause nursing'));
      await tap(find.widgetWithText(FilledButton, 'Finish nursing'));
      expect(c.nursing, isNull);
      expect(c.feeds, hasLength(1));
      expect(c.feeds.single.endedAt, isNotNull);
      expect(
        c.feeds.single.leftSeconds! + c.feeds.single.rightSeconds!,
        greaterThanOrEqualTo(edited.leftSeconds! + edited.rightSeconds!),
      );
      expect(t.takeException(), isNull);
    }
    await t.pumpWidget(const SizedBox());
    c.dispose();
    await t.runAsync(db.close);
  });
  testWidgets(
    'nursing affected by missing end time can resume its recorded sides',
    (t) async {
      final db = (await t.runAsync(
        () => databaseFactoryMemory.openDatabase(newId.v4()),
      ))!;
      final auth = GoogleAuth();
      final c = AppController(Repository(db), auth, GoogleDrive(auth))
        ..loading = false;
      await t.runAsync(() async {
        await c.createLocal('Family', 'Robin');
        final affected = Feeding.fromJson({
          ...sample('nursing', c.family!.id).toJson(),
          'endedAt': null,
        });
        await c.repository.add(affected);
        await c.refresh();
      });
      final affected = c.feeds.single;
      expect(affected.endedAt, isNull);
      await t.pumpWidget(LittleLogApp(controller: c));
      await t.pumpAndSettle();
      editActivity(t.element(find.byType(Scaffold).first), c, affected);
      await t.pumpAndSettle();
      expect(find.text('Resume left timer'), findsOneWidget);
      expect(find.text('Resume right timer'), findsOneWidget);
      await t.runAsync(() async {
        await t.tap(find.text('Resume right timer'));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(c.nursing!.rightSeconds, affected.rightSeconds);
      expect(c.nursing!.leftSeconds, affected.leftSeconds);
      expect(c.nursing!.startedAt, affected.at);
      expect(c.nursing!.side, 'right');
      expect(find.text('Right side running'), findsOneWidget);
      expect(c.feeds, isEmpty);
      final unknownSides = Feeding(
        id: newId.v4(),
        familyId: c.family!.id,
        at: affected.at,
        method: 'nursing',
        minutes: 6,
      );
      await t.runAsync(() async {
        await expectLater(
          c.reopenNursing(unknownSides, 'left'),
          throwsFormatException,
        );
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      c.dispose();
      await t.runAsync(db.close);
    },
  );
  for (final method in [
    'bottle',
    'nursing',
    'diaper',
    'sleep',
    'pumping',
    'solids',
    'growth',
    'health',
    'routine',
    'milestone',
  ]) {
    testWidgets(
      'edit $method preserves fields and saves one visible replacement',
      (t) async {
        t.view.physicalSize = const Size(390, 844);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final db = (await t.runAsync(
          () => databaseFactoryMemory.openDatabase(newId.v4()),
        ))!;
        final auth = GoogleAuth();
        final c = AppController(Repository(db), auth, GoogleDrive(auth))
          ..loading = false;
        await t.runAsync(() => c.createLocal('Family', 'Robin'));
        final record = sample(method, c.family!.id);
        await t.runAsync(() async {
          await c.repository.add(record);
          await c.refresh();
        });
        if (const bool.fromEnvironment('CAPTURE_EDIT')) {
          await t.runAsync(() async {
            final loader = FontLoader('Roboto')
              ..addFont(
                Future.value(
                  ByteData.sublistView(
                    File(
                      '/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
                    ).readAsBytesSync(),
                  ),
                ),
              );
            await loader.load();
          });
        }
        await t.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('capture-root'),
            child: LittleLogApp(controller: c),
          ),
        );
        await t.pumpAndSettle();
        final context = t.element(find.byType(Scaffold).first);
        editActivity(context, c, record);
        await t.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(FormHeading),
            matching: find.text(
              '${method[0].toUpperCase()}${method.substring(1)}',
            ),
          ),
          findsOneWidget,
        );
        final note = find.widgetWithText(TextFormField, 'Notes (optional)');
        await t.ensureVisible(note);
        await t.enterText(note, 'Updated note');
        if (method == 'bottle') {
          final amount = find.widgetWithText(TextFormField, 'Amount (ml)');
          await t.ensureVisible(amount);
          await t.enterText(amount, '100');
        }
        if (const bool.fromEnvironment('CAPTURE_EDIT') &&
            ['bottle', 'diaper'].contains(method)) {
          await t.pumpAndSettle();
          final boundary = t.firstRenderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('capture-root')),
          );
          final image = (await t.runAsync(() => boundary.toImage()))!;
          final bytes = await t.runAsync(
            () => image.toByteData(format: ImageByteFormat.png),
          );
          await t.runAsync(() async {
            await Directory('../tmp/edit-review').create(recursive: true);
            await File(
              '../tmp/edit-review/$method.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          });
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await t.pumpAndSettle();
        final saveButton = find.widgetWithText(FilledButton, 'Save changes');
        await t.ensureVisible(saveButton);
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(saveButton);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final records = (await t.runAsync(
          () => c.repository.feeds(record.familyId),
        ))!;
        expect(records, hasLength(1));
        final edited = records.single;
        expect(edited.id, isNot(record.id));
        expect(edited.note, 'Updated note');
        expect(edited.details, record.details);
        expect(edited.author, record.author);
        expect(edited.leftSeconds, record.leftSeconds);
        expect(edited.rightSeconds, record.rightSeconds);
        expect(edited.endedAt?.toUtc(), record.endedAt?.toUtc());
        expect(edited.at.toUtc(), record.at.toUtc());
        expect(edited.amountMl, method == 'bottle' ? 100 : record.amountMl);
        await t.pumpWidget(const SizedBox());
        c.dispose();
        await t.runAsync(db.close);
      },
    );
  }
  testWidgets(
    'swipe right edits, left confirms delete, no duplicate delete button',
    (t) async {
      var edits = 0, deletes = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordRow(
              record: sample('bottle', 'f'),
              volumeUnit: VolumeUnit.ml,
              onEdit: () async {
                edits++;
              },
              onDelete: () async {
                deletes++;
              },
            ),
          ),
        ),
      );
      await t.drag(find.byType(Dismissible), const Offset(600, 0));
      await t.pumpAndSettle();
      expect(edits, 1);
      await t.tap(find.byType(InkWell).first);
      await t.pumpAndSettle();
      expect(find.text('Delete entry'), findsNothing);
      await t.drag(find.byType(Dismissible), const Offset(-600, 0));
      await t.pumpAndSettle();
      expect(find.text('Delete this entry?'), findsOneWidget);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(deletes, 0);
    },
  );
  test(
    'edited record syncs deletion plus replacement and rejects stale second save',
    () async {
      final db = await databaseFactoryMemory.openDatabase(newId.v4());
      final auth = fake.Auth();
      final cloud = fake.Drive(auth);
      final c = AppController(Repository(db), auth, cloud)..loading = false;
      await c.createLocal('Family', 'Robin');
      final original = sample('bottle', c.family!.id);
      await c.repository.add(original);
      auth.user = fake.Account();
      await c.sync(manual: true);
      await c.addFeed(
        at: at,
        method: 'bottle',
        amountMl: 100,
        note: 'Edited',
        original: original,
      );
      await c.sync(manual: true);
      expect(cloud.rows[original.id]!.deleted, true);
      expect(cloud.rows.values.where((r) => !r.deleted).single.amountMl, 100);
      await expectLater(
        c.addFeed(
          at: at,
          method: 'bottle',
          amountMl: 120,
          note: 'Stale',
          original: original,
        ),
        throwsStateError,
      );
      expect(await c.repository.feeds(original.familyId), hasLength(1));
      c.dispose();
      await db.close();
    },
  );
}
