import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:little_log/design.dart';
import 'package:little_log/models.dart';
import 'package:little_log/widgets/activity_flow.dart';
import 'elapsed_icon_preference_test.dart' show localController;
import 'support/shared_log_builds_52_55/models.dart' as build54;
import 'support/test_fonts.dart';

void main() {
  testWidgets(
    'live switches preserve both sides and legacy session round trips',
    (t) async {
      final c = await localController(t);
      final baby = c.family!;
      final start = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now().millisecondsSinceEpoch - 600000,
        isUtc: true,
      );
      final initial = NursingSession(
        id: 'switch-session',
        familyId: baby.id,
        startedAt: start,
        segmentAt: start,
        side: 'left',
        note: 'Keep note',
        source: const {'qa': 'synthetic'},
      );
      await t.runAsync(() async {
        await c.repository.saveSession(initial);
        // Live actions target their original baby even after the selected baby changes.
        await c.createLocal('Other family', 'Other baby');
        Future<bool> act(
          String action,
          int revision,
          int seconds, {
          String? id,
        }) => c.performLiveTimerAction(
          sessionId: id ?? initial.id,
          familyId: baby.id,
          method: 'nursing',
          action: action,
          expectedRevision: revision,
          at: start.add(Duration(seconds: seconds)),
        );
        expect(await act('switch', 0, 120), isTrue);
        expect(await act('switch', 0, 121), isFalse);
        expect(await act('switch', 1, 180, id: 'old-session'), isFalse);
        var session = (await c.repository.nursingSession(baby.id))!;
        expect(session.side, 'right');
        expect(session.leftSeconds, 120);
        expect(session.startedAt, initial.startedAt);
        // A released reader can reopen, switch, and write the same session.
        final legacy = build54.NursingSession.fromJson(
          jsonDecode(jsonEncode(session.toJson())) as Map<String, dynamic>,
        );
        await c.repository.saveSession(
          NursingSession.fromJson(
            legacy
                .switchTo('left', start.add(const Duration(seconds: 180)))
                .toJson(),
          ),
        );
        expect(await act('pause', 0, 240), isTrue);
        expect(await act('switch', 1, 250), isFalse);
        expect(await act('resume', 1, 300), isTrue);
        expect(await act('switch', 2, 360), isTrue);
        expect(await act('pause', 3, 420), isTrue);
        expect(await act('finish', 4, 480), isTrue);
        expect(await act('switch', 5, 490), isFalse);
        final saved = (await c.repository.feeds(baby.id)).single;
        expect(saved.leftSeconds, 240);
        expect(saved.rightSeconds, 120);
        expect(saved.note, initial.note);
        expect(saved.source, initial.source);
        final oldRecord = build54.Feeding.fromJson(saved.toJson());
        expect(oldRecord.leftSeconds, 240);
        expect(oldRecord.rightSeconds, 120);
        expect(c.feeds, isEmpty);
      });
    },
  );

  testWidgets('queued native switch retries once after failed acknowledgment', (
    t,
  ) async {
    final c = await localController(t);
    final start = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch - 300000,
      isUtc: true,
    );
    final session = NursingSession(
      id: 'native-switch',
      familyId: c.family!.id,
      startedAt: start,
      segmentAt: start,
      side: 'right',
      leftSeconds: 20,
    );
    await t.runAsync(() => c.repository.saveSession(session));
    final pending = <Map<String, Object?>>[
      {
        'id': 'switch-request',
        'sessionId': session.id,
        'familyId': session.familyId,
        'method': 'nursing',
        'action': 'switch',
        'revision': 0,
        'stoppedAt': start
            .add(const Duration(seconds: 60))
            .millisecondsSinceEpoch,
      },
    ];
    var failAck = true;
    const channel = MethodChannel('little_log/live_activity');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'pendingStops') return List.of(pending);
      if (call.method == 'acknowledgeStop') {
        if (failAck) throw PlatformException(code: 'storage-unavailable');
        pending.clear();
      }
      return null;
    });
    addTearDown(() {
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await t.runAsync(c.processLiveTimerStops);
    expect(pending, hasLength(1));
    failAck = false;
    await t.runAsync(c.processLiveTimerStops);
    expect(pending, isEmpty);
    final restored = await t.runAsync(
      () => c.repository.nursingSession(session.familyId),
    );
    expect(restored!.side, 'left');
    expect(restored.revision, 1);
    expect(restored.leftSeconds, 20);
    expect(restored.rightSeconds, 60);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final large in [false, true]) {
    testWidgets('live nursing card switches directly: large=$large', (t) async {
      t.view.physicalSize = Size(large ? 320 : 390, 700);
      t.view.devicePixelRatio = 1;
      t.platformDispatcher.textScaleFactorTestValue = large ? 1.8 : 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await t.runAsync(loadTestFonts);
      final c = await localController(t);
      await t.runAsync(() async {
        await c.nursingAction('left');
      });
      final id = c.nursing!.id;
      await t.pumpWidget(
        MaterialApp(
          theme: littleLogTheme(),
          home: Scaffold(
            body: RepaintBoundary(
              key: const ValueKey('capture'),
              child: ListenableBuilder(
                listenable: c,
                builder: (_, _) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: ActiveSessions(controller: c),
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final button = find.byKey(const ValueKey('switch-live-nursing'));
      expect(button, findsOneWidget);
      expect(find.textContaining('Left side running'), findsOneWidget);
      for (final side in ['right', 'left']) {
        await t.runAsync(() async {
          await t.tap(button);
          for (var i = 0; i < 100 && c.recording; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await t.pumpAndSettle();
        expect(c.nursing!.side, side);
        expect(c.nursing!.id, id);
        expect(c.nursing!.paused, isFalse);
        expect(find.byType(TimedActivityFlow), findsNothing);
      }
      if (Platform.environment['NURSING_REVIEW_OUTPUT']
          case final String folder) {
        final boundary = t.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('capture')),
        );
        await t.runAsync(() async {
          final pixels = await boundary.toImage(pixelRatio: 1);
          final bytes = await pixels.toByteData(format: ui.ImageByteFormat.png);
          await Directory(folder).create(recursive: true);
          await File(
            '$folder/nursing-${large ? 'large-text' : 'regular'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          pixels.dispose();
        });
      }
      await t.runAsync(() async {
        await t.tap(find.byKey(const ValueKey('pause-live-nursing')));
        for (var i = 0; i < 100 && c.recording; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await t.pumpAndSettle();
      expect(button, findsNothing);
      expect(find.byKey(const ValueKey('resume-live-nursing')), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
