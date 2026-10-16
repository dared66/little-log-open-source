import 'volume.dart';
import 'models.dart';

const activityNames = {
  'sleep': 'Sleep',
  'pumping': 'Pumping',
  'solids': 'Solids',
  'growth': 'Growth',
  'health': 'Health',
  'routine': 'Routine',
  'milestone': 'Milestone',
};
const growthUnits = {
  'Weight': ['kg', 'lb'],
  'Length': ['cm', 'in'],
  'Head circumference': ['cm', 'in'],
};
const healthKinds = [
  'Medication',
  'Vaccine',
  'Temperature',
  'Symptom',
  'Doctor visit',
];

void validateActivity(Feeding record, String familyId) {
  final d = record.details;
  bool text(String key) =>
      d[key] is String &&
      (d[key] as String).trim().isNotEmpty &&
      (d[key] as String).length <= 500;
  bool positive(Object? n) => n is num && n.isFinite && n > 0;
  final allowed = switch (record.method) {
    'sleep' => <String>[],
    'pumping' => <String>[],
    'solids' => ['food', 'reaction'],
    'growth' => ['measurement', 'value', 'unit'],
    'health' => [
      'kind',
      'name',
      'dose',
      'value',
      'unit',
      'temperature',
      'temperatureUnit',
    ],
    'routine' || 'milestone' => ['name'],
    _ => <String>[],
  };
  if (record.id.isEmpty ||
      record.familyId != familyId ||
      !activityNames.containsKey(record.method) ||
      record.note.length > 2000 ||
      d.keys.any((k) => !allowed.contains(k)) ||
      (record.endedAt != null && record.endedAt!.isBefore(record.at)) ||
      (record.method != 'pumping' && record.amountMl != null)) {
    throw const FormatException('Please check the activity details.');
  }
  final valid = switch (record.method) {
    'sleep' => record.endedAt != null && record.endedAt!.isAfter(record.at),
    'pumping' => positive(record.amountMl) && record.amountMl! <= 2000,
    'solids' =>
      text('food') &&
          [
            'Not recorded',
            'No reaction observed',
            'Reaction observed',
          ].contains(d['reaction']),
    'growth' =>
      growthUnits[d['measurement']]?.contains(d['unit']) == true &&
          positive(d['value']),
    'health' =>
      healthKinds.contains(d['kind']) &&
          (d['kind'] == 'Temperature'
              ? positive(d['value']) && ['°C', '°F'].contains(d['unit'])
              : text('name') && (d['kind'] != 'Medication' || text('dose'))) &&
          ((!d.containsKey('temperature') &&
                  !d.containsKey('temperatureUnit')) ||
              (d['kind'] == 'Medication' &&
                  positive(d['temperature']) &&
                  ['°C', '°F'].contains(d['temperatureUnit']))),
    'routine' || 'milestone' => text('name'),
    _ => false,
  };
  if (!valid) {
    throw const FormatException(
      'Fill in the required activity details and units.',
    );
  }
}

String activityLabel(Feeding f, {required VolumeUnit unit}) {
  final d = f.details;
  return switch (f.method) {
    'sleep' => 'Sleep · ${f.endedAt!.difference(f.at).inMinutes} min',
    'pumping' => 'Pumping · ${volumeLabel(f.amountMl ?? 0, unit: unit)}',
    'solids' => 'Solids · ${d['food']} · ${d['reaction']}',
    'growth' => '${d['measurement']} · ${d['value']} ${d['unit']}',
    'health' =>
      d['kind'] == 'Temperature'
          ? 'Temperature · ${d['value']} ${d['unit']}'
          : '${d['kind']} · ${d['name']}${d['dose'] == null ? '' : ' · ${d['dose']}'}${d['temperature'] == null ? '' : ' · Temperature ${d['temperature']} ${d['temperatureUnit']}'}',
    _ => '${activityNames[f.method]} · ${d['name']}',
  };
}

/// Timers are local until completion; elapsed time is derived from timestamps.
class ActivityTimer {
  const ActivityTimer({
    required this.id,
    required this.familyId,
    required this.method,
    required this.startedAt,
  });
  final String id, familyId, method;
  final DateTime startedAt;
  Map<String, Object?> toJson() => {
    'id': id,
    'familyId': familyId,
    'method': method,
    'startedAt': startedAt.toUtc().toIso8601String(),
  };
  factory ActivityTimer.fromJson(Map<String, Object?> j) => ActivityTimer(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    method: j['method'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
  );
}

class DaySummary {
  DaySummary(Iterable<Feeding> records, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = DateTime(day.year, day.month, day.day + 1);
    for (final f in records) {
      if (f.method == 'sleep' && f.endedAt != null) {
        final a = f.at.isBefore(start) ? start : f.at;
        final b = f.endedAt!.isAfter(end) ? end : f.endedAt!;
        if (b.isAfter(a)) sleepSeconds += b.difference(a).inSeconds;
      }
      if (f.at.isBefore(start) || !f.at.isBefore(end)) continue;
      if (f.isFeeding) feeds++;
      if (f.method == 'bottle') bottleMl += f.amountMl ?? 0;
      if (f.method == 'nursing') {
        nursingCount++;
        if (f.leftSeconds != null && f.rightSeconds != null) {
          nursingLeftSeconds += f.leftSeconds!;
          nursingRightSeconds += f.rightSeconds!;
        } else {
          nursingUnassignedSeconds += (f.minutes ?? 0) * 60;
        }
      }
      if (f.method == 'pumping') pumpedMl += f.amountMl ?? 0;
      if (f.isDiaper) diapers++;
    }
  }
  int feeds = 0, nursingCount = 0, diapers = 0, sleepSeconds = 0;
  int nursingLeftSeconds = 0,
      nursingRightSeconds = 0,
      nursingUnassignedSeconds = 0;
  int get nursingSeconds =>
      nursingLeftSeconds + nursingRightSeconds + nursingUnassignedSeconds;
  double bottleMl = 0, pumpedMl = 0;
}
