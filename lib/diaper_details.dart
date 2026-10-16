import 'models.dart';

// Stable values are stored in records; labels can change without rewriting data.
const diaperKinds = {
  'wet': 'Wet',
  'dirty': 'Dirty',
  'both': 'Both',
  'dry': 'Dry',
};
const poopColors = {
  'yellow': 'Yellow',
  'mustard': 'Mustard',
  'orange': 'Orange',
  'green': 'Green',
  'brown': 'Brown',
  'black': 'Black',
  'red': 'Red',
  'white': 'White',
  'gray': 'Gray',
  'other': 'Other',
};
const poopConsistencies = {
  'watery': 'Watery',
  'loose': 'Loose',
  'seedy': 'Seedy',
  'mushy': 'Mushy',
  'pasty': 'Pasty',
  'formed': 'Formed',
  'hard': 'Hard / pellets',
  'mucousy': 'Mucousy',
  'other': 'Other',
};
bool hasPoop(String? kind) => kind == 'dirty' || kind == 'both';

void validateDiaper(Feeding record, String expectedFamily) {
  final d = record.details;
  if (record.id.isEmpty ||
      record.familyId != expectedFamily ||
      record.method != 'diaper' ||
      !diaperKinds.containsKey(record.diaperKind) ||
      record.note.length > 2000 ||
      record.amountMl != null ||
      record.minutes != null ||
      record.endedAt != null ||
      record.leftSeconds != null ||
      record.rightSeconds != null ||
      d.keys.any(
        (k) => ![
          'poopColor',
          'poopConsistency',
          'poopColors',
          'poopConsistencies',
          'blowout',
          'rash',
        ].contains(k),
      ) ||
      (d.containsKey('poopColor') && !poopColors.containsKey(d['poopColor'])) ||
      (d.containsKey('poopConsistency') &&
          !poopConsistencies.containsKey(d['poopConsistency'])) ||
      (!validChoices(d, 'poopColors', poopColors)) ||
      (!validChoices(d, 'poopConsistencies', poopConsistencies)) ||
      (d.containsKey('poopColors') && d.containsKey('poopColor')) ||
      (d.containsKey('poopConsistencies') &&
          d.containsKey('poopConsistency')) ||
      (d.containsKey('blowout') && d['blowout'] is! bool) ||
      (d.containsKey('rash') && d['rash'] is! bool) ||
      (!hasPoop(record.diaperKind) &&
          [
            'poopColor',
            'poopConsistency',
            'poopColors',
            'poopConsistencies',
            'blowout',
          ].any(d.containsKey))) {
    throw const FormatException('Check the diaper type and poop details.');
  }
}

bool validChoices(
  Map<String, Object?> d,
  String key,
  Map<String, String> choices,
) {
  if (!d.containsKey(key)) return true;
  final values = d[key];
  return values is List &&
      values.isNotEmpty &&
      values.toSet().length == values.length &&
      values.every((v) => v is String && choices.containsKey(v));
}

List<String> diaperValues(
  Map<String, Object?> details,
  String singular,
  String plural,
) => details[plural] is List
    ? List<String>.from(details[plural] as List)
    : details[singular] is String
    ? [details[singular] as String]
    : [];

/// Missing fields mean unrecorded, never a negative observation.
String diaperDetailsLabel(Feeding record) {
  final d = record.details;
  return [
    if (d['poopColors'] is List)
      'Color: ${(d['poopColors'] as List).map((v) => poopColors[v]).join(', ')}',
    if (d['poopConsistencies'] is List)
      'Consistency: ${(d['poopConsistencies'] as List).map((v) => poopConsistencies[v]).join(', ')}',
    if (d['poopColor'] != null)
      'Color: ${poopColors[d['poopColor']] ?? d['poopColor']}',
    if (d['poopConsistency'] != null)
      'Consistency: ${poopConsistencies[d['poopConsistency']] ?? d['poopConsistency']}',
    if (d['blowout'] is bool) d['blowout'] == true ? 'Blowout' : 'No blowout',
    if (d['rash'] is bool) d['rash'] == true ? 'Diaper rash' : 'No diaper rash',
  ].join(' · ');
}
