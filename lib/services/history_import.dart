import 'dart:convert';
import 'package:uuid/enums.dart';
import 'dart:math';
import '../models.dart';
import '../record_validation.dart';
import 'family_csv.dart';
import 'nara_csv.dart';
import 'import_issue.dart';

String recordFingerprint(Feeding f) => jsonEncode(f.toRow());
String snapshotFingerprint(List<Feeding> records) {
  final sorted = [...records]..sort((a, b) => a.id.compareTo(b.id));
  return jsonEncode(sorted.map((f) => f.toRow()).toList());
}

class ImportPlan {
  ImportPlan({
    required this.familyId,
    required this.before,
    required this.additions,
    required this.removals,
    required this.duplicates,
    required this.label,
    this.unassignedPumps = 0,
    this.issues = const [],
    this.allowPartial = false,
  });
  final String familyId, label;
  final List<Feeding> before, additions, removals;
  final int duplicates;
  final int unassignedPumps;
  final List<ImportIssue> issues;
  final bool allowPartial;
  bool get needsConsent =>
      issues.any((i) => i.requiresConsent) && !allowPartial;
  int get activityCount => additions.where((f) => f.method != 'profile').length;
}

class HistoryImport {
  static Map<String, dynamic> naraExport(String text) {
    final raw = jsonDecode(text);
    if (raw is! Map<String, dynamic> ||
        raw['tracks'] is! Map ||
        raw['profile'] is! Map) {
      throw const FormatException(
        'Choose a Nara export containing profile and tracks.',
      );
    }
    return raw;
  }

  static List<String> caregiverKeys(String text) {
    final raw = naraExport(text);
    final keys = <String>{};
    for (final value in (raw['tracks'] as Map).values) {
      final row = Map<String, dynamic>.from(value as Map);
      final key = row['createUserKey'] ?? row['userKey'];
      if (key is String) keys.add(key);
    }
    return keys.toList()..sort();
  }

  static ImportPlan preview(
    String text,
    Family family,
    List<Feeding> existing, {
    Map<String, String> caregivers = const {},
    bool replacePreviousNara = false,
    bool includeUnassignedPumps = false,
    bool allowPartial = false,
  }) {
    if (utf8.encode(text).length > FamilyCsv.maxBytes) {
      throw const FormatException('Import is too large (maximum 10 MB).');
    }
    text = text.startsWith('\ufeff') ? text.substring(1) : text;
    var unassignedPumps = 0;
    var issues = <ImportIssue>[];
    final parsed = text.trimLeft().startsWith('{') ? jsonDecode(text) : null;
    late List<Feeding> incoming;
    String label;
    if (parsed is Map && parsed['tracks'] is Map) {
      final raw = naraExport(text);
      if ((raw['profile'] as Map)['name']?.toString().toLowerCase() !=
          family.babyName.toLowerCase()) {
        throw const FormatException(
          'Baby name doesn’t match the selected baby.',
        );
      }
      incoming = _nara(raw, family, caregivers);
      label = 'Nara Baby';
    } else if (parsed is Map && parsed['format'] == 'little-log') {
      if ((parsed['family'] as Map?)?['id'] != family.id) {
        throw const FormatException('Backup belongs to another baby.');
      }
      if (![3, 4].contains(parsed['schemaVersion'])) {
        throw const FormatException('Unsupported backup version.');
      }
      incoming = [
        for (final kind in ['feedings', 'diapers', 'activities'])
          for (final row in parsed[kind] as List? ?? [])
            Feeding.fromJson(Map<String, Object?>.from(row as Map)),
      ];
      label = 'Little Log backup';
      if ((parsed['activeTimers'] as List? ?? []).isNotEmpty ||
          parsed['activeNursing'] != null) {
        throw const FormatException(
          'This backup contains running timers. Finish them before exporting for import.',
        );
      }
    } else if (NaraCsv.matches(text)) {
      final csv = NaraCsv.decode(
        text,
        family,
        includeUnassignedPumps: includeUnassignedPumps,
      );
      incoming = csv.records;
      unassignedPumps = csv.unassignedPumps;
      issues = csv.issues;
      label = 'Nara Baby CSV';
    } else {
      final csv = FamilyCsv.decode(text);
      if (csv.family.id != family.id) {
        throw const FormatException('This CSV belongs to another baby.');
      }
      incoming = csv.feeds;
      label = 'Little Log CSV';
    }
    // Split source rows must be treated as one immutable import group. A changed
    // list can have entirely new component IDs; checking IDs alone would leave
    // the old components behind and append a conflicting copy of the source.
    final sourceGroups = <String, Set<String>>{};
    for (final record in existing) {
      if (record.source['system'] == 'Nara Baby' &&
          record.source['format'] == 'csv') {
        sourceGroups
            .putIfAbsent(record.source['recordId'] as String, () => {})
            .add(_csvOriginalFingerprint(record.source['original']));
      }
    }
    for (final record in incoming) {
      if (record.source['system'] == 'Nara Baby' &&
          record.source['format'] == 'csv') {
        final prior = sourceGroups[record.source['recordId']];
        if (prior != null &&
            (prior.length != 1 ||
                !prior.contains(
                  _csvOriginalFingerprint(record.source['original']),
                ))) {
          throw const FormatException(
            'An existing Nara entry has different contents. No entries were changed.',
          );
        }
      }
    }
    final current = {for (final f in existing) f.id: f};
    final additions = <Feeding>[], removals = <Feeding>[];
    final seen = <String>{};
    var duplicates = 0;
    for (final f in incoming) {
      validateRecord(f, family.id);
      if (!seen.add(f.id)) {
        throw const FormatException(
          'The import contains duplicate record IDs.',
        );
      }
      final old = current[f.id];
      if (old != null) {
        if (jsonEncode(old.originalRow) != jsonEncode(f.originalRow)) {
          throw const FormatException(
            'An existing record has different contents. No entries were changed.',
          );
        }
        if (f.deleted && !old.deleted) {
          removals.add(old);
        } else {
          duplicates++;
        }
      } else {
        additions.add(Feeding.fromJson({...f.toJson(), 'synced': false}));
      }
    }
    if (replacePreviousNara && label == 'Nara Baby') {
      final raw = naraExport(text);
      final legacyIds = (raw['tracks'] as Map).keys
          .map((k) => newId.v5(Namespace.url.value, 'nara-baby:lila:$k'))
          .toSet();
      for (final f in existing.where(
        (f) => !f.deleted && legacyIds.contains(f.id),
      )) {
        if (!removals.any((r) => r.id == f.id)) removals.add(f);
      }
    }
    return ImportPlan(
      familyId: family.id,
      before: List.unmodifiable(existing),
      additions: List.unmodifiable(additions),
      removals: List.unmodifiable(removals),
      duplicates: duplicates,
      label: label,
      unassignedPumps: unassignedPumps,
      issues: List.unmodifiable(issues),
      allowPartial: allowPartial,
    );
  }

  static String _csvOriginalFingerprint(Object? original) {
    if (original is! Map) return jsonEncode(original);
    final keys = original.keys.cast<String>().toList()..sort();
    return jsonEncode({for (final key in keys) key: original[key]});
  }

  static List<Feeding> _nara(
    Map<String, dynamic> raw,
    Family family,
    Map<String, String> caregivers,
  ) {
    final rows = Map<String, dynamic>.from(raw['tracks'] as Map);
    final childKeys = rows.values
        .map((v) => (v as Map)['childKey'])
        .whereType<String>()
        .toSet();
    if (childKeys.length > 1) {
      throw const FormatException(
        'Export contains multiple babies. Export one baby at a time.',
      );
    }
    final keys = caregiverKeys(jsonEncode(raw));
    final result = <Feeding>[];
    for (final entry in rows.entries) {
      final t = Map<String, dynamic>.from(entry.value as Map);
      final begin = t['beginDt'];
      if (begin is! int) {
        throw const FormatException('A Nara record is missing its start time.');
      }
      final at = DateTime.fromMillisecondsSinceEpoch(begin, isUtc: true);
      final who = t['createUserKey'] ?? t['userKey'];
      final author = caregivers[who]?.trim();
      final source = <String, Object?>{
        'system': 'Nara Baby',
        'recordId': entry.key,
        'caregiverId': who,
        'timezone': t['tz'],
        'original': t,
      };
      String method;
      double? amount;
      int? left, right, minutes;
      String? diaperKind;
      final details = <String, Object?>{};
      if (t['type'] == 'DIAPER') {
        method = 'diaper';
        final pee = t['diaperTypePee'], poop = t['diaperTypePoop'];
        if (pee is! bool || poop is! bool) {
          throw const FormatException('Unknown diaper contents.');
        }
        diaperKind = pee && poop
            ? 'both'
            : pee
            ? 'wet'
            : poop
            ? 'dirty'
            : 'dry';
        if (!pee && !poop && t['diaperTypeDry'] != true) {
          throw const FormatException('Unrecorded diaper contents.');
        }
        if (t['diaperTypeRash'] != null) details['rash'] = t['diaperTypeRash'];
        if (poop) {
          if (t['diaperPoopBlowout'] != null) {
            details['blowout'] = t['diaperPoopBlowout'];
          }
          if (t['diaperPoopColor'] != null) {
            details['poopColors'] =
                t['diaperPoopColor'].toString().toLowerCase().split(' ')
                  ..sort();
          }
          if (t['diaperPoopTexture'] != null) {
            const textures = {
              'MUSH': 'mushy',
              'RUN': 'watery',
              'MUCOUS': 'mucousy',
              'PEBBLE': 'hard',
              'SOLID': 'formed',
            };
            final values = t['diaperPoopTexture'].toString().split(' ');
            if (values.any((v) => !textures.containsKey(v))) {
              throw const FormatException('Unknown Nara diaper texture.');
            }
            details['poopConsistencies'] =
                values.map((v) => textures[v]!).toList()..sort();
          }
        }
      } else if (t['type'] == 'FEED' && t['feedType'] == 'BREAST') {
        method = 'nursing';
        if (t['breastLeftDuration'] == null &&
            t['breastRightDuration'] == null) {
          throw const FormatException('Nara nursing duration is missing.');
        }
        final l = t['breastLeftDuration'] ?? 0,
            r = t['breastRightDuration'] ?? 0;
        if (l is! int || r is! int || l < 0 || r < 0) {
          throw const FormatException('Invalid nursing duration.');
        }
        left = l ~/ 1000;
        right = r ~/ 1000;
        minutes = ((l + r) / 60000).ceil();
        source['leftDurationMs'] = l;
        source['rightDurationMs'] = r;
        source['endTimeBasis'] = 'notRecorded';
      } else if (t['type'] == 'FEED' && t['feedType'] == 'BOTTLE') {
        method = 'bottle';
        double volume(String prefix) {
          final n = t['${prefix}Num'],
              exp = t['${prefix}Exp'],
              unit = t['${prefix}Unit'];
          if (n is! num || exp is! int || !['FLOZ', 'ML'].contains(unit)) {
            throw const FormatException('Unknown Nara volume encoding.');
          }
          return n / pow(10, exp) * (unit == 'FLOZ' ? 29.5735295625 : 1);
        }

        amount = volume('bottleVolume');
        final milk = t['bottleTypeBreastMilk'],
            formula = t['bottleTypeFormula'];
        if (milk == true || formula == true) {
          final milkMl = milk == true
              ? (formula == true ? volume('bottleBreastMilkVolume') : amount)
              : 0.0;
          details['breastMilkMl'] = milkMl;
          details['formulaMl'] = amount - milkMl;
          if (t['bottleFormulaName'] is String) {
            details['formulaName'] = t['bottleFormulaName'];
          }
        }
      } else {
        throw FormatException(
          'Unsupported Nara activity: ${t['type']}. No entries were changed.',
        );
      }
      final record = Feeding(
        id: newId.v5(Namespace.url.value, 'nara-baby:v2:${entry.key}'),
        familyId: family.id,
        at: at,
        method: method,
        amountMl: amount,
        minutes: minutes,
        leftSeconds: left,
        rightSeconds: right,
        diaperKind: diaperKind,
        details: details,
        source: source,
        note: t['note'] as String? ?? '',
        author: author?.isNotEmpty == true
            ? author!
            : keys.contains(who)
            ? 'Nara caregiver ${keys.indexOf(who as String) + 1}'
            : 'Nara caregiver (unknown)',
      );
      validateRecord(record, family.id);
      result.add(record);
    }
    final profile = Map<String, dynamic>.from(raw['profile'] as Map);
    final night = profile['nightBeginEnd']?.toString().split(',');
    final details = <String, Object?>{
      'birthDate': ?profile['birthDate'],
      'gender': ?profile['gender'],
      if (night?.length == 2) 'nightStart': night![0],
      if (night?.length == 2) 'nightEnd': night![1],
    };
    final profileRecord = Feeding(
      id: newId.v5(
        Namespace.url.value,
        'nara-profile:${family.id}:${jsonEncode(details)}',
      ),
      familyId: family.id,
      at: result.isEmpty
          ? DateTime.utc(1970)
          : result.map((f) => f.at).reduce((a, b) => a.isBefore(b) ? a : b),
      method: 'profile',
      details: details,
      source: {
        'system': 'Nara Baby',
        'recordId': 'profile',
        'original': profile,
      },
    );
    validateRecord(profileRecord, family.id);
    result.add(profileRecord);
    return result;
  }
}
