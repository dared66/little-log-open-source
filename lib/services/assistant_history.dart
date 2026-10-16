import 'package:intl/intl.dart';
import '../models.dart';
import '../activity_details.dart';

const assistantHistoryQuestions = {
  'last_diaper': 'When was the last diaper?',
  'last_wet_diaper': 'When was the last wet diaper?',
  'last_dirty_diaper': 'When was the last dirty diaper?',
  'last_feed': 'When was the last feed?',
  'last_bottle': 'When was the last bottle?',
  'last_nursing': 'When was the last nursing session?',
  'last_solids': 'When was the last solids meal?',
  'last_sleep': 'When did the last sleep start?',
  'last_wake': 'When did the baby last wake up?',
  'last_pumping': 'When was the last pumping session?',
  'sleep_status': 'Is the baby asleep?',
};

String historyTime(DateTime at, DateTime now) {
  at = at.toLocal();
  now = now.toLocal();
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final clock = DateFormat.jm('en_US').format(at);
  final when = day == today
      ? 'at $clock'
      : day == DateTime(now.year, now.month, now.day - 1)
      ? 'yesterday at $clock'
      : 'on ${DateFormat(at.year == now.year ? 'MMMM d' : 'MMMM d, yyyy', 'en_US').format(at)} at $clock';
  final elapsed = now.difference(at);
  String unit(int n, String label) => '$n $label${n == 1 ? '' : 's'}';
  final parts = <String>[
    if (elapsed.inDays > 0) unit(elapsed.inDays, 'day'),
    if (elapsed.inHours % 24 > 0) unit(elapsed.inHours % 24, 'hour'),
    if (elapsed.inMinutes % 60 > 0) unit(elapsed.inMinutes % 60, 'minute'),
  ];
  final ago = parts.isEmpty
      ? 'less than a minute ago'
      : '${parts.take(2).join(' and ')} ago';
  return '$when, $ago';
}

/// Reads saved history and durable active timers, without changing either.
/// Feed means bottle, nursing or solids; sleep start and wake-up are distinct.
String answerAssistantHistory({
  required String action,
  required Family baby,
  required List<Feeding> records,
  required List<ActivityTimer> timers,
  required NursingSession? nursing,
  required DateTime now,
}) {
  if (!assistantHistoryQuestions.containsKey(action)) {
    throw const FormatException('That history question is not available.');
  }
  final sleeps =
      timers
          .where(
            (t) =>
                t.familyId == baby.id &&
                t.method == 'sleep' &&
                !t.startedAt.isAfter(now),
          )
          .toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
  final sleep = sleeps.firstOrNull;
  if (action == 'sleep_status') {
    return sleep == null
        ? 'There is no active sleep timer for ${baby.babyName}.'
        : '${baby.babyName} has an active sleep timer, started ${historyTime(sleep.startedAt, now)}.';
  }
  DateTime? latest;
  String? description;
  void consider(DateTime at, String text) {
    if (!at.isAfter(now) && (latest == null || at.isAfter(latest!))) {
      latest = at;
      description = text;
    }
  }

  final methods = switch (action) {
    'last_diaper' || 'last_wet_diaper' || 'last_dirty_diaper' => {'diaper'},
    'last_feed' => {'bottle', 'nursing', 'solids'},
    'last_bottle' => {'bottle'},
    'last_nursing' => {'nursing'},
    'last_solids' => {'solids'},
    'last_sleep' || 'last_wake' => {'sleep'},
    _ => {'pumping'},
  };
  for (final record in records) {
    if (record.deleted ||
        record.familyId != baby.id ||
        !methods.contains(record.method) ||
        record.at.isAfter(now)) {
      continue;
    }
    if (action == 'last_wet_diaper' &&
        !{'wet', 'both'}.contains(record.diaperKind)) {
      continue;
    }
    if (action == 'last_dirty_diaper' &&
        !{'dirty', 'both'}.contains(record.diaperKind)) {
      continue;
    }
    if (action == 'last_wake') {
      // A duration-only entry does not establish a precise wake-up time.
      final end = record.endedAt;
      if (end != null && !end.isBefore(record.at)) {
        consider(end, 'last recorded wake-up was');
      }
      continue;
    }
    final text = switch (record.method) {
      'diaper' =>
        'last ${switch (record.diaperKind) {
          'wet' => 'wet',
          'dirty' => 'dirty',
          'both' => 'wet and dirty',
          'dry' => 'dry',
          _ => '',
        }} diaper was',
      'bottle' => 'last bottle feed was',
      'nursing' => 'last nursing session started',
      'solids' => 'last solids were logged',
      'sleep' => 'last sleep started',
      _ => 'last pumping session started',
    };
    consider(record.at, text.replaceAll('  ', ' '));
  }
  if (methods.contains('nursing') &&
      nursing != null &&
      nursing.familyId == baby.id) {
    consider(
      nursing.startedAt,
      nursing.paused
          ? 'paused nursing session started'
          : 'active nursing session started',
    );
  }
  for (final timer in timers) {
    if (timer.familyId == baby.id &&
        methods.contains(timer.method) &&
        action != 'last_wake') {
      consider(timer.startedAt, 'active ${timer.method} timer started');
    }
  }
  final missing = switch (action) {
    'last_diaper' => 'diaper changes',
    'last_wet_diaper' => 'wet diapers',
    'last_dirty_diaper' => 'dirty diapers',
    'last_feed' => 'feeds',
    'last_bottle' => 'bottle feeds',
    'last_nursing' => 'nursing sessions',
    'last_solids' => 'solids',
    'last_sleep' => 'sleep',
    'last_wake' => 'wake-up times',
    _ => 'pumping sessions',
  };
  final answer = latest == null
      ? 'No $missing ${action == 'last_sleep' ? 'is' : 'are'} logged for ${baby.babyName}.'
      : '${baby.babyName}’s $description ${historyTime(latest!, now)}.';
  return action == 'last_wake' && sleep != null
      ? '$answer An active sleep timer is running for ${baby.babyName}.'
      : answer;
}
