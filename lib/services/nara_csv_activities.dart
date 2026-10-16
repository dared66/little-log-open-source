import 'dart:convert';
import 'package:uuid/enums.dart';
import '../models.dart';

/// A valid source entry that cannot become a completed Little Log activity.
class NaraCsvDeferred implements Exception {
  const NaraCsvDeferred(this.reason);
  final String reason;
}

/// Baby activity mappings grounded in docs/reference/nara/fixtures.
/// Existing bottle/nursing/pump/diaper/profile identities stay in NaraCsv.
class NaraCsvActivities {
  static const fields = {
    'Combo Feed': {
      'Begin Side',
      'End Side',
      'Left Duration (Seconds)',
      'Right Duration (Seconds)',
      'Type',
      'Breast Milk Volume',
      'Breast Milk Volume Unit',
      'Formula Name',
      'Formula Volume',
      'Formula Volume Unit',
      'Volume',
      'Volume Unit',
    },
    'Sleep': {'Duration (Seconds)', 'End Date/time', 'End Date/time (Epoch)'},
    'Solid Feed': {'Food', 'Meal'},
    'Growth': {
      'Weight',
      'Weight Unit',
      'Height',
      'Height Unit',
      'Head Size',
      'Head Size Unit',
    },
    'Medical': {'Medication', 'Temperature', 'Temperature Unit'},
    'Vaccine': {'Vaccine'},
    'Routine': {'Routine'},
    'Baby First': {'Baby First'},
    'Milestone': {'Milestone'},
  };

  static List<Feeding> decode(
    Map<String, String> row,
    Family family,
    String sourceId, {
    required Feeding Function(Map<String, String>, Family, String) basic,
  }) {
    final type = row['Type']!;
    String value(String field) => row['[$type] $field'] ?? '';
    final at = timestamp(row['Start Date/time (Epoch)'] ?? '');
    final keys = row.keys.where((k) => row[k]!.isNotEmpty).toList()..sort();
    final original = {for (final key in keys) key: row[key]};
    Feeding make(
      String method, {
      Map<String, Object?> details = const {},
      String? component,
      DateTime? end,
      String? note,
      Map<String, Object?> extraSource = const {},
    }) => Feeding(
      id: identity(sourceId, component),
      familyId: family.id,
      at: at,
      method: method,
      endedAt: end,
      details: details,
      note: note ?? row['Note'] ?? '',
      author: row['Created By Caregiver'] ?? '',
      source: {
        'system': 'Nara Baby',
        'recordId': sourceId,
        'format': 'csv',
        'timezone': row['Time Zone'],
        'original': original,
        'component': ?component,
        ...extraSource,
      },
    );

    switch (type) {
      case 'Combo Feed':
        final records = <Feeding>[];
        // Each component uses the existing validated mapping but keeps the
        // complete original Combo Feed row in provenance.
        for (final target in ['Breastfeed', 'Bottle Feed']) {
          final translated = <String, String>{...row, 'Type': target};
          for (final entry in row.entries) {
            if (entry.key.startsWith('[Combo Feed] ')) {
              translated['[$target] ${entry.key.substring(13)}'] = entry.value;
            }
          }
          final present = target == 'Breastfeed'
              ? [
                  'Left Duration (Seconds)',
                  'Right Duration (Seconds)',
                ].any((f) => value(f).isNotEmpty)
              : [
                  'Breast Milk Volume',
                  'Breast Milk Volume Unit',
                  'Formula Volume',
                  'Formula Volume Unit',
                  'Volume',
                  'Volume Unit',
                ].any((f) => value(f).isNotEmpty);
          if (!present) continue;
          final mapped = basic(translated, family, sourceId);
          final component = target == 'Breastfeed'
              ? 'combo:nursing'
              : 'combo:bottle';
          records.add(
            Feeding.fromJson({
              ...mapped.toJson(),
              'id': identity(sourceId, component),
              'source': make(mapped.method, component: component).source,
            }),
          );
        }
        if (records.isEmpty) {
          throw const FormatException(
            'Combo feed has no feeding amounts or durations.',
          );
        }
        return records;
      case 'Sleep':
        final duration = value('Duration (Seconds)');
        final endText = value('End Date/time (Epoch)');
        if (duration.isNotEmpty) wholeSeconds(duration);
        if (endText.isEmpty) {
          throw const NaraCsvDeferred(
            'Sleep entry has no end time. Finish it in Nara and export again.',
          );
        }
        final end = timestamp(endText);
        if (!end.isAfter(at)) {
          throw const FormatException('Sleep end must be after its start.');
        }
        if (duration.isNotEmpty &&
            end.difference(at).inMilliseconds !=
                wholeSeconds(duration) * 1000) {
          throw const FormatException('Sleep duration and end time disagree.');
        }
        return [make('sleep', end: end)];
      case 'Growth':
        final records = <Feeding>[];
        const measurements = {
          'Weight': ('Weight', {'KG': 'kg', 'LB': 'lb'}),
          'Height': ('Length', {'CM': 'cm', 'IN': 'in'}),
          'Head Size': ('Head circumference', {'CM': 'cm', 'IN': 'in'}),
        };
        for (final entry in measurements.entries) {
          final amount = value(entry.key), unit = value('${entry.key} Unit');
          if (amount.isEmpty && unit.isEmpty) continue;
          final mappedUnit = entry.value.$2[unit];
          if (mappedUnit == null) {
            throw const FormatException('Unknown growth unit.');
          }
          records.add(
            make(
              'growth',
              component: 'growth:${entry.key}',
              details: {
                'measurement': entry.value.$1,
                'value': positive(amount),
                'unit': mappedUnit,
              },
              extraSource: {
                if ((row['Start Date/time'] ?? '').endsWith(' 00:00:00'))
                  'dateOnly': true,
              },
            ),
          );
        }
        if (records.isEmpty) {
          throw const FormatException('Growth measurements are missing.');
        }
        return records;
      case 'Medical':
        final records = <Feeding>[];
        final names = <String>{};
        for (final line in lines(value('Medication'))) {
          final dose = RegExp(r'^(.+), (.+) \(([^()]+)\)$').firstMatch(line);
          String name, amount;
          if (dose == null) {
            if (RegExp(r',.*\([^()]*\)$').hasMatch(line)) {
              throw const FormatException('Invalid medication dose.');
            }
            name = line;
            amount = 'Not recorded';
          } else {
            name = dose[1]!;
            nonNegative(dose[2]!);
            const units = {
              'ML': 'mL',
              'MG': 'mg',
              'TAB': 'tab',
              'DROP': 'drop',
              'TSP': 'tsp',
            };
            final unit = units[dose[3]!];
            if (unit == null) {
              throw const FormatException('Unknown medication unit.');
            }
            amount = '${dose[2]} $unit';
          }
          if (!names.add(name)) {
            throw const NaraCsvDeferred(
              'Medication names repeat in this entry. Review it in Nara before exporting.',
            );
          }
          records.add(
            make(
              'health',
              component: namedComponent('medical:medication', name),
              details: {'kind': 'Medication', 'name': name, 'dose': amount},
            ),
          );
        }
        final temperature = value('Temperature'),
            unit = value('Temperature Unit');
        if (temperature.isNotEmpty || unit.isNotEmpty) {
          if (!['C', 'F'].contains(unit)) {
            throw const FormatException('Unknown temperature unit.');
          }
          // One temperature observation, regardless of the number of medicines.
          records.add(
            make(
              'health',
              component: 'medical:temperature',
              details: {
                'kind': 'Temperature',
                'value': positive(temperature),
                'unit': '°$unit',
              },
            ),
          );
        }
        if (records.isEmpty) {
          throw const FormatException('Medication or temperature is missing.');
        }
        return records;
      case 'Vaccine':
        final names = lines(value('Vaccine'));
        if (names.isEmpty) throw const FormatException('Vaccine is missing.');
        if (names.toSet().length != names.length) {
          throw const NaraCsvDeferred(
            'Vaccine names repeat in this entry. Review it in Nara before exporting.',
          );
        }
        return [
          for (final name in names)
            make(
              'health',
              component: namedComponent('vaccine', name),
              details: {'kind': 'Vaccine', 'name': name},
            ),
        ];
      case 'Solid Feed':
        final foods = _foods(value('Food'));
        final names = <String>{};
        return [
          for (final food in foods)
            (() {
              final (name, attributes) = food;
              if (!names.add(name)) {
                throw const NaraCsvDeferred(
                  'Food names repeat in this entry. Review it in Nara before exporting.',
                );
              }
              final allergy = attributes['allergy'];
              if (allergy != null && !['true', 'false'].contains(allergy)) {
                throw const FormatException(
                  'Unknown food allergy observation.',
                );
              }
              final note = [
                row['Note'] ?? '',
                attributes['note'] ?? '',
              ].where((s) => s.isNotEmpty).join('\n\n');
              return make(
                'solids',
                component: namedComponent('solids', name),
                details: {
                  'food': name,
                  'reaction': switch (allergy) {
                    'true' => 'Reaction observed',
                    'false' => 'No reaction observed',
                    _ => 'Not recorded',
                  },
                },
                note: note,
                extraSource: {
                  'foodAttributes': attributes,
                  'meal': value('Meal'),
                },
              );
            })(),
        ];
      case 'Routine':
        return [
          make('routine', details: {'name': value('Routine')}),
        ];
      case 'Baby First':
      case 'Milestone':
        return [
          make('milestone', details: {'name': value(type)}),
        ];
      default:
        throw FormatException('Unsupported Nara activity: $type.');
    }
  }

  static String identity(String sourceId, String? component) => newId.v5(
    Namespace.url.value,
    component == null
        ? 'nara-baby:v2:$sourceId'
        : 'nara-csv:component:v1:${jsonEncode([sourceId, component])}',
  );

  static String namedComponent(String kind, String name) =>
      '$kind:${jsonEncode(name)}';

  static double nonNegative(String text) {
    final value = double.tryParse(text);
    if (value == null || !value.isFinite || value < 0) {
      throw const FormatException('Amount must be a nonnegative number.');
    }
    return value;
  }

  static double positive(String text) {
    final value = nonNegative(text);
    if (value == 0) {
      throw const FormatException('Amount must be a positive number.');
    }
    return value;
  }

  static int wholeSeconds(String text) {
    final value = double.tryParse(text);
    if (value == null ||
        !value.isFinite ||
        value < 0 ||
        value > 8640000000000 ||
        value != value.roundToDouble()) {
      throw const FormatException(
        'Duration must be a whole number of seconds.',
      );
    }
    return value.toInt();
  }

  static DateTime timestamp(String text) {
    final value = int.tryParse(text);
    if (value == null || value < 0 || value > 8640000000000000) {
      throw const FormatException('Invalid timestamp.');
    }
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  static List<String> lines(String text) {
    if (text.isEmpty) return [];
    final result = text
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (result.isEmpty) {
      throw const FormatException('Entry names are missing.');
    }
    return result;
  }

  static List<(String, Map<String, String>)> _foods(String text) {
    if (text.isEmpty) throw const FormatException('Food is missing.');
    final result = <(String, Map<String, String>)>[];
    for (final line in lines(text)) {
      final match = RegExp(
        r'^(.+?): ((?:allergy|amountKey|preparationKeyz|reactionKey|note)=.*)$',
      ).firstMatch(line);
      if (match == null) {
        if (RegExp(r'^.+?: [A-Za-z][A-Za-z0-9]*=').hasMatch(line)) {
          throw const NaraCsvDeferred(
            'Food details use an unsupported format.',
          );
        }
        // A continuation after note= cannot safely be distinguished from a
        // second food name in Nara's unescaped inner serialization.
        if (result.isNotEmpty && result.last.$2.containsKey('note')) {
          throw const NaraCsvDeferred(
            'Food notes use an ambiguous format. Review this entry in Nara before exporting.',
          );
        }
        result.add((line, {}));
        continue;
      }
      final attributes = <String, String>{};
      var remaining = match[2]!;
      while (remaining.isNotEmpty) {
        final equals = remaining.indexOf('=');
        if (equals <= 0) {
          throw const NaraCsvDeferred('Food details could not be read.');
        }
        final key = remaining.substring(0, equals);
        if (attributes.containsKey(key)) {
          throw const NaraCsvDeferred('Food details repeat in this entry.');
        }
        final rest = remaining.substring(equals + 1);
        final delimiter = key == 'note' ? -1 : rest.indexOf('; ');
        attributes[key] = delimiter < 0 ? rest : rest.substring(0, delimiter);
        remaining = delimiter < 0 ? '' : rest.substring(delimiter + 2);
      }
      result.add((match[1]!, attributes));
    }
    return result;
  }
}
