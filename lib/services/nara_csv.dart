import 'package:uuid/enums.dart';
import '../models.dart';
import '../record_validation.dart';
import 'family_csv.dart';
import 'import_issue.dart';
import 'nara_csv_activities.dart';

class NaraCsvResult {
  const NaraCsvResult(this.records, this.unassignedPumps, this.issues);
  final List<Feeding> records;
  final int unassignedPumps;
  final List<ImportIssue> issues;
}

/// Nara's variable-column CSV. Column names and units are grounded in a real
/// export; unsupported fields/types require explicit partial-import consent.
class NaraCsv {
  static const shared = {
    'Type',
    'Profile Name',
    'Start Date/time',
    'Start Date/time (Epoch)',
    'Created By Caregiver',
    'Last Updated By Caregiver',
    'Note',
    'Time Zone',
    '_familyKey',
    '_profileKey',
    '_activityKey',
  };
  static const fields = {
    ...NaraCsvActivities.fields,
    'Diaper': {'Type', 'Detail', 'Dirty Color', 'Dirty Texture'},
    'Bottle Feed': {
      'Type',
      'Breast Milk Volume',
      'Breast Milk Volume Unit',
      'Formula Name',
      'Formula Volume',
      'Formula Volume Unit',
      'Volume',
      'Volume Unit',
    },
    'Breastfeed': {
      'Begin Side',
      'End Side',
      'Left Duration (Seconds)',
      'Right Duration (Seconds)',
    },
    'Pump': {
      'Duration (Seconds)',
      'End Date/time',
      'End Date/time (Epoch)',
      'Left Volume',
      'Left Volume Unit',
      'Right Volume',
      'Right Volume Unit',
      'Total Volume',
      'Total Volume Unit',
    },
    'Profile': {'Birth Date', 'Birth Date (Adjusted)', 'Sex', 'Type'},
  };

  static const requiredColumns = {
    'Type',
    'Profile Name',
    'Start Date/time (Epoch)',
    '_profileKey',
    '_familyKey',
    '_activityKey',
  };

  static bool matches(String text) {
    final first = FamilyCsv.parseRows(text.split('\n').first);
    return first.isNotEmpty && requiredColumns.every(first.first.contains);
  }

  static NaraCsvResult decode(
    String text,
    Family family, {
    bool includeUnassignedPumps = false,
  }) {
    final rows = FamilyCsv.parseRows(text);
    if (rows.length < 2) {
      throw const FormatException('This export has no entries.');
    }
    final header = rows.first;
    if (header.toSet().length != header.length) {
      throw const FormatException('The export has duplicate column names.');
    }
    if (header.any((name) => name.trim().isEmpty)) {
      throw const FormatException('The export has an unnamed column.');
    }
    for (final required in requiredColumns) {
      if (!header.contains(required)) {
        throw FormatException('Nara export is missing $required.');
      }
    }
    final parsed = <Map<String, String>>[];
    final rowNumbers = <int>[];
    for (var i = 1; i < rows.length; i++) {
      final values = rows[i];
      if (values.every((v) => v.isEmpty)) continue;
      if (values.length > header.length) {
        throw FormatException('Row ${i + 1}: too many columns.');
      }
      // Nara omits the final empty _activityKey cell on its Profile row.
      final padded = [
        ...values,
        ...List.filled(header.length - values.length, ''),
      ];
      final row = {
        for (var j = 0; j < header.length; j++) header[j]: padded[j],
      };
      if (values.length != header.length &&
          !(row['Type'] == 'Profile' &&
              values.length == header.length - 1 &&
              header.last == '_activityKey')) {
        throw FormatException('Row ${i + 1}: incomplete row.');
      }
      parsed.add(row);
      rowNumbers.add(i + 1);
    }
    final profileIds = parsed
        .map((r) => r['_profileKey']!)
        .where((s) => s.isNotEmpty)
        .toSet();
    final names = parsed
        .map((r) => r['Profile Name']!.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    final families = parsed
        .map((r) => r['_familyKey']!)
        .where((s) => s.isNotEmpty)
        .toSet();
    if (profileIds.length != 1 || names.length != 1 || families.length != 1) {
      throw const FormatException(
        'Export one baby at a time. This file has missing or mixed profiles.',
      );
    }
    if (parsed.any(
      (r) =>
          r['Type'] == 'Profile' &&
          ['PARENT', 'PREGNANCY'].contains(r['[Profile] Type']),
    )) {
      throw const FormatException(
        'Choose a baby export. Parent and pregnancy logs aren’t supported.',
      );
    }
    if (names.single != family.babyName.trim().toLowerCase()) {
      throw const FormatException('Baby name doesn’t match the selected baby.');
    }
    final result = <Feeding>[];
    final seen = <String>{};
    var unassigned = 0;
    final issues = <ImportIssue>[];
    for (var i = 0; i < parsed.length; i++) {
      final row = parsed[i];
      try {
        final type = row['Type']!;
        if (type.trim().isEmpty) {
          throw const FormatException('Activity type is missing.');
        }
        final id = type == 'Profile'
            ? 'profile:${row['_profileKey']}'
            : row['_activityKey']!;
        if (id.trim().isEmpty || !seen.add(id)) {
          throw const FormatException('Missing or duplicate activity ID.');
        }
        final noProfile =
            row['_profileKey']!.isEmpty && row['Profile Name']!.isEmpty;
        if (noProfile && type != 'Pump' ||
            !noProfile &&
                (row['_profileKey']!.isEmpty || row['Profile Name']!.isEmpty)) {
          throw const FormatException(
            'The entry has no complete baby profile.',
          );
        }
        if (row['_familyKey'] != families.single) {
          throw const FormatException('The entry belongs to another family.');
        }
        ImportIssue issue(String reason, {bool requiresConsent = true}) =>
            ImportIssue(
              row: rowNumbers[i],
              type: type,
              recordId: id,
              time: row['Start Date/time'] ?? '',
              reason: reason,
              requiresConsent: requiresConsent,
            );
        if (!fields.containsKey(type)) {
          issues.add(issue('Activity not supported: $type.'));
          continue;
        }
        final allowed = {...shared, ...fields[type]!.map((f) => '[$type] $f')};
        final unknown = row.entries
            .where((e) => e.value.isNotEmpty && !allowed.contains(e.key))
            .map((e) => e.key)
            .toList();
        if (unknown.isNotEmpty) {
          issues.add(issue('Fields not supported: ${unknown.join(', ')}.'));
          continue;
        }
        // Validate unassigned records as well, even when excluded from saving.
        late List<Feeding> records;
        try {
          records = NaraCsvActivities.fields.containsKey(type)
              ? NaraCsvActivities.decode(row, family, id, basic: _record)
              : [_record(row, family, id)];
        } on NaraCsvDeferred catch (e) {
          issues.add(issue(e.reason));
          continue;
        }
        for (final record in records) {
          validateRecord(record, family.id);
        }
        if (noProfile) {
          unassigned++;
          if (!includeUnassignedPumps) {
            issues.add(
              issue(
                'Pumping record has no baby assigned.',
                requiresConsent: false,
              ),
            );
            continue;
          }
        }
        result.addAll(records);
      } on FormatException catch (e) {
        throw FormatException(
          'Row ${rowNumbers[i]}: ${e.message} No entries were imported.',
        );
      }
    }
    if (parsed.isEmpty) {
      throw const FormatException('This export has no entries.');
    }
    return NaraCsvResult(result, unassigned, issues);
  }

  static Feeding _record(
    Map<String, String> row,
    Family family,
    String sourceId,
  ) {
    final type = row['Type']!;
    String value(String field) => row['[$type] $field'] ?? '';
    double number(String text) {
      final n = double.tryParse(text);
      if (n == null || !n.isFinite || n < 0) {
        throw const FormatException('Invalid amount or duration.');
      }
      return n;
    }

    int seconds(String field) {
      final text = value(field);
      if (text.isEmpty) return 0;
      final n = number(text);
      if (n != n.roundToDouble()) {
        throw const FormatException(
          'Duration must be a whole number of seconds.',
        );
      }
      return n.toInt();
    }

    double? volume(String field) {
      final text = value(field), unit = value('$field Unit');
      if (text.isEmpty && unit.isEmpty) return null;
      final n = number(text);
      if (!['ML', 'FLOZ'].contains(unit)) {
        throw const FormatException('Unknown volume unit.');
      }
      return n * (unit == 'FLOZ' ? 29.5735295625 : 1);
    }

    DateTime timestamp(String text) {
      final n = int.tryParse(text);
      if (n == null || n < 0 || n > 8640000000000000) {
        throw const FormatException('Invalid timestamp.');
      }
      return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
    }

    final at = type == 'Profile'
        ? DateTime.utc(1970)
        : timestamp(row['Start Date/time (Epoch)'] ?? '');
    String method;
    double? amount;
    int? left, right, minutes;
    DateTime? end;
    String? diaper;
    final details = <String, Object?>{};
    switch (type) {
      case 'Diaper':
        method = 'diaper';
        diaper = const {
          'Wet': 'wet',
          'Dirty': 'dirty',
          'Dirty Wet': 'both',
          'Wet Dirty': 'both',
          'Dry': 'dry',
        }[value('Type')];
        if (diaper == null) throw const FormatException('Unknown diaper type.');
        final detail = value('Detail');
        if (![
          '',
          'Blowout',
          'Rash',
          'Blowout Rash',
          'Rash Blowout',
        ].contains(detail)) {
          throw const FormatException('Unknown diaper detail.');
        }
        if (detail.contains('Blowout')) details['blowout'] = true;
        if (detail.contains('Rash')) details['rash'] = true;
        if (value('Dirty Color').isNotEmpty) {
          details['poopColors'] = value('Dirty Color').toLowerCase().split(' ')
            ..sort();
        }
        if (value('Dirty Texture').isNotEmpty) {
          const textures = {
            'MUSH': 'mushy',
            'RUN': 'watery',
            'MUCOUS': 'mucousy',
            'PEBBLE': 'hard',
            'SOLID': 'formed',
          };
          final input = value('Dirty Texture').split(' ');
          if (input.any((s) => !textures.containsKey(s))) {
            throw const FormatException('Unknown diaper texture.');
          }
          details['poopConsistencies'] = input.map((s) => textures[s]!).toList()
            ..sort();
        }
      case 'Bottle Feed':
        method = 'bottle';
        final milk = volume('Breast Milk Volume'),
            formula = volume('Formula Volume'),
            total = volume('Volume');
        final kind = value('Type');
        if (![
          'Breast Milk',
          'Formula',
          'Breast Milk Formula',
          'Breast Milk + Formula',
          '',
        ].contains(kind)) {
          throw const FormatException('Unknown bottle type.');
        }
        if (milk != null || formula != null) {
          amount = (milk ?? 0) + (formula ?? 0);
          if (total != null && (total - amount).abs() > 0.00001) {
            throw const FormatException('Bottle amounts do not add up.');
          }
          details.addAll({
            'breastMilkMl': milk ?? 0.0,
            'formulaMl': formula ?? 0.0,
          });
          if (kind == 'Breast Milk' && (formula ?? 0) > 0 ||
              kind == 'Formula' && (milk ?? 0) > 0) {
            throw const FormatException('Bottle type and amounts disagree.');
          }
        } else {
          amount = total;
          if (total != null && ['Breast Milk', 'Formula'].contains(kind)) {
            details.addAll({
              'breastMilkMl': kind == 'Breast Milk' ? total : 0.0,
              'formulaMl': kind == 'Formula' ? total : 0.0,
            });
          }
        }
        if (value('Formula Name').isNotEmpty) {
          details['formulaName'] = value('Formula Name');
        }
      case 'Breastfeed':
        method = 'nursing';
        if (value('Left Duration (Seconds)').isEmpty &&
            value('Right Duration (Seconds)').isEmpty) {
          throw const FormatException('Nursing duration is missing.');
        }
        left = seconds('Left Duration (Seconds)');
        right = seconds('Right Duration (Seconds)');
        if (left + right <= 0) {
          throw const FormatException('Nursing duration must be positive.');
        }
        minutes = ((left + right) / 60).ceil();
        for (final side in ['Begin Side', 'End Side']) {
          if (![
            '',
            'LEFT',
            'RIGHT',
            'LEFT.nonTimer',
            'RIGHT.nonTimer',
          ].contains(value(side))) {
            throw const FormatException('Unknown nursing side.');
          }
        }
      case 'Pump':
        method = 'pumping';
        final l = volume('Left Volume'),
            r = volume('Right Volume'),
            total = volume('Total Volume');
        amount = total ?? (l != null || r != null ? (l ?? 0) + (r ?? 0) : null);
        if (total != null &&
            (l != null || r != null) &&
            ((l ?? 0) + (r ?? 0) - total).abs() > 0.00001) {
          throw const FormatException('Pumping amounts do not add up.');
        }
        if (value('End Date/time (Epoch)').isNotEmpty) {
          end = timestamp(value('End Date/time (Epoch)'));
        }
        if (value('Duration (Seconds)').isNotEmpty) {
          final duration = seconds('Duration (Seconds)');
          if (end != null && end.difference(at).inSeconds != duration) {
            throw const FormatException(
              'Pumping duration and end time disagree.',
            );
          }
          end ??= at.add(Duration(seconds: duration));
          minutes = (duration / 60).ceil();
        }
      case 'Profile':
        method = 'profile';
        if (value('Type') != 'CHILD') {
          throw const FormatException('Choose a child export.');
        }
        if (value('Birth Date').isNotEmpty) {
          details['birthDate'] = value('Birth Date');
        }
        if (value('Sex').isNotEmpty) details['gender'] = value('Sex');
      default:
        throw FormatException('Unsupported Nara activity: $type.');
    }
    final keys = row.keys.where((k) => row[k]!.isNotEmpty).toList()..sort();
    return Feeding(
      id: newId.v5(
        Namespace.url.value,
        type == 'Profile'
            ? 'nara-csv:${row['_familyKey']}:$sourceId'
            : 'nara-baby:v2:$sourceId',
      ),
      familyId: family.id,
      at: at,
      method: method,
      amountMl: amount,
      minutes: minutes,
      leftSeconds: left,
      rightSeconds: right,
      endedAt: end,
      diaperKind: diaper,
      details: details,
      note: row['Note'] ?? '',
      author: row['Created By Caregiver'] ?? '',
      source: {
        'system': 'Nara Baby',
        'recordId': sourceId,
        'format': 'csv',
        'timezone': row['Time Zone'],
        'original': {for (final key in keys) key: row[key]},
      },
    );
  }
}
