import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models.dart';
import '../activity_details.dart';

class LiveActivity {
  static const _channel = MethodChannel('little_log/live_activity');
  static bool get supported =>
      !kIsWeb &&
      [
        TargetPlatform.iOS,
        TargetPlatform.android,
      ].contains(defaultTargetPlatform);

  static void listenForStops(Future<void> Function() receive) {
    if (!supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopped') await receive();
    });
  }

  static Future<List<Map<String, Object?>>> pendingStops() async {
    if (!supported) return [];
    try {
      final values = await _channel.invokeListMethod<Object?>('pendingStops');
      return [
        for (final value in values ?? [])
          Map<String, Object?>.from(value as Map),
      ];
    } on MissingPluginException {
      return [];
    }
  }

  static Future<void> acknowledgeStop(String id) =>
      _channel.invokeMethod<void>('acknowledgeStop', id);

  static List<Map<String, Object?>> snapshots(
    String baby,
    NursingSession? nursing,
    List<ActivityTimer> timers,
  ) {
    final now = DateTime.now();
    final nursingSeconds = nursing == null
        ? 0
        : nursing.secondsFor('left', now) + nursing.secondsFor('right', now);
    return [
      if (nursing != null)
        {
          'id': nursing.id,
          'familyId': nursing.familyId,
          'method': 'nursing',
          'title': '$baby · Nursing',
          'startedAt': now.millisecondsSinceEpoch / 1000 - nursingSeconds,
          'elapsedSeconds': nursingSeconds.toDouble(),
          'revision': nursing.revision,
          'phase': nursing.paused ? 'paused' : 'running',
          'detail': nursing.paused
              ? 'Paused'
              : '${nursing.side == 'left' ? 'Left' : 'Right'} side running',
        },
      for (final timer in timers)
        {
          'id': timer.id,
          'familyId': timer.familyId,
          'method': timer.method,
          'title': '$baby · ${activityNames[timer.method]}',
          'startedAt':
              now.millisecondsSinceEpoch / 1000 -
              timer.elapsedAt(now).inMilliseconds / 1000,
          'elapsedSeconds': timer.elapsedAt(now).inMilliseconds / 1000,
          'revision': timer.revision,
          'phase': timer.phase,
          'detail': switch (timer.phase) {
            'paused' => 'Paused',
            'review' => 'Add pumped amount',
            _ => 'Timer running',
          },
        },
    ];
  }

  static Future<void> update(
    String baby,
    NursingSession? nursing,
    List<ActivityTimer> timers,
  ) => updateAll(snapshots(baby, nursing, timers));

  static Future<void> updateAll(List<Map<String, Object?>> sessions) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('update', sessions);
    } on MissingPluginException {
      /* Host widget tests have no native integration. */
    } on PlatformException {
      /* Durable sessions stay available in the app. */
    }
  }
}
