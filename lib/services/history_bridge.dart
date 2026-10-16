import 'dart:convert';
import 'package:uuid/enums.dart';
import '../models.dart';
import 'family_csv.dart';
import 'history_import.dart';

/// Offline interchange. The bridge JSON resembles a Nara history export but
/// its `littleLogRecord` extension is authoritative; it is never an API payload.
class HistoryBridge {
  static const format = 'little-log-nara-bridge-v1';

  static FamilyCsv naraToCsv(
    String text, {
    FamilyCsv? base,
    Map<String, String> caregivers = const {},
  }) {
    final raw = HistoryImport.naraExport(text);
    if (raw['format'] == format) return _fromBridge(raw, base);
    final profile = Map<String, dynamic>.from(raw['profile'] as Map);
    final name = profile['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Nara profile has no baby name.');
    }
    final tracks = Map<String, dynamic>.from(raw['tracks'] as Map);
    final childKeys = tracks.values
        .map((r) => (r as Map)['childKey'])
        .whereType<String>()
        .toSet();
    if (childKeys.length > 1) {
      throw const FormatException('Nara export contains multiple children.');
    }
    final identity = childKeys.isEmpty
        ? name.trim().toLowerCase()
        : childKeys.single;
    final family =
        base?.family ??
        Family(
          id: newId.v5(Namespace.url.value, 'little-log:nara-family:$identity'),
          name: '${name.trim()}’s family',
          babyName: name.trim(),
        );
    final plan = HistoryImport.preview(
      text,
      family,
      base?.feeds ?? const [],
      caregivers: caregivers,
    );
    final removed = plan.removals.map((f) => f.id).toSet();
    final rows = <Feeding>[
      for (final f in base?.feeds ?? const <Feeding>[])
        removed.contains(f.id) ? f.asDeleted() : f,
      ...plan.additions,
    ];
    final result = FamilyCsv(family, rows);
    return FamilyCsv.decode(result.encode());
  }

  static FamilyCsv _fromBridge(Map<String, dynamic> raw, FamilyCsv? base) {
    final meta = raw['family'];
    if (meta is! Map || raw['tracks'] is! Map) {
      throw const FormatException('Invalid bridge export.');
    }
    final family = Family.fromJson(Map<String, Object?>.from(meta));
    if (family.id.isEmpty || family.name.isEmpty || family.babyName.isEmpty) {
      throw const FormatException('Incomplete family metadata.');
    }
    if (base != null && base.family.id != family.id) {
      throw const FormatException('Bridge file belongs to another family.');
    }
    final incoming = <Feeding>[];
    final ids = <String>{};
    for (final value in (raw['tracks'] as Map).values) {
      if (value is! Map || value['littleLogRecord'] is! Map) {
        throw const FormatException('Bridge record is incomplete.');
      }
      final f = Feeding.fromJson(
        Map<String, Object?>.from(value['littleLogRecord'] as Map),
      );
      if (!ids.add(f.id)) {
        throw const FormatException('Duplicate bridge record.');
      }
      incoming.add(f);
    }
    // The native decoder validates every row, including deletion markers.
    final verified = FamilyCsv.decode(FamilyCsv(family, incoming).encode());
    if (base == null) return verified;
    final byId = {for (final f in base.feeds) f.id: f};
    for (final f in verified.feeds) {
      final current = byId[f.id];
      if (current != null &&
          jsonEncode(current.originalRow) != jsonEncode(f.originalRow)) {
        throw const FormatException(
          'An existing record ID has different contents.',
        );
      }
      if (current == null || (f.deleted && !current.deleted)) byId[f.id] = f;
    }
    return FamilyCsv.decode(
      FamilyCsv(base.family, byId.values.toList()).encode(),
    );
  }

  static String csvToNara(FamilyCsv csv) {
    final profileRows =
        csv.feeds.where((f) => !f.deleted && f.method == 'profile').toList()
          ..sort((a, b) {
            final time = b.at.compareTo(a.at);
            return time != 0 ? time : b.id.compareTo(a.id);
          });
    final profile = profileRows.isEmpty
        ? <String, Object?>{'name': csv.family.babyName}
        : <String, Object?>{
            'name': csv.family.babyName,
            'birthDate': ?profileRows.first.details['birthDate'],
            'gender': ?profileRows.first.details['gender'],
            if (profileRows.first.details['nightStart'] != null &&
                profileRows.first.details['nightEnd'] != null)
              'nightBeginEnd':
                  '${profileRows.first.details['nightStart']},${profileRows.first.details['nightEnd']}',
          };
    final tracks = <String, Object?>{};
    for (final f in csv.feeds) {
      final key = 'little-log:${f.id}';
      tracks[key] = {..._naraView(f), 'littleLogRecord': f.toJson()};
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': format,
      'family': csv.family.toJson(),
      'profile': profile,
      'tracks': tracks,
    });
  }

  static Map<String, Object?> _naraView(Feeding f) {
    final base = <String, Object?>{
      'key': f.id,
      'beginDt': f.at.millisecondsSinceEpoch,
      if (f.note.isNotEmpty) 'note': f.note,
    };
    if (f.deleted) return {...base, 'type': 'LITTLE_LOG_DELETION'};
    switch (f.method) {
      case 'profile':
        return {...base, 'type': 'CHILD_PROFILE'};
      case 'diaper':
        return {
          ...base,
          'type': 'DIAPER',
          'diaperTypePee': ['wet', 'both'].contains(f.diaperKind),
          'diaperTypePoop': ['dirty', 'both'].contains(f.diaperKind),
          'diaperTypeDry': f.diaperKind == 'dry',
          if (f.details['rash'] != null) 'diaperTypeRash': f.details['rash'],
          if (f.details['blowout'] != null)
            'diaperPoopBlowout': f.details['blowout'],
        };
      case 'nursing':
        return {
          ...base,
          'type': 'FEED',
          'feedType': 'BREAST',
          if (f.leftSeconds != null)
            'breastLeftDuration': f.leftSeconds! * 1000,
          if (f.rightSeconds != null)
            'breastRightDuration': f.rightSeconds! * 1000,
          if (f.endedAt != null) 'endDt': f.endedAt!.millisecondsSinceEpoch,
        };
      case 'bottle':
        return {
          ...base,
          'type': 'FEED',
          'feedType': 'BOTTLE',
          'bottleVolumeNum': f.amountMl,
          'bottleVolumeExp': 0,
          'bottleVolumeUnit': 'ML',
          if (f.details['breastMilkMl'] != null)
            'bottleBreastMilkVolumeNum': f.details['breastMilkMl'],
          if (f.details['breastMilkMl'] != null) 'bottleBreastMilkVolumeExp': 0,
          if (f.details['breastMilkMl'] != null)
            'bottleBreastMilkVolumeUnit': 'ML',
          'bottleTypeBreastMilk': (f.details['breastMilkMl'] as num? ?? 0) > 0,
          'bottleTypeFormula': (f.details['formulaMl'] as num? ?? 0) > 0,
          if (f.details['formulaName'] != null)
            'bottleFormulaName': f.details['formulaName'],
        };
      case 'sleep':
        return {
          ...base,
          'type': 'SLEEP',
          if (f.endedAt != null) 'endDt': f.endedAt!.millisecondsSinceEpoch,
        };
      case 'pumping':
        return {
          ...base,
          'type': 'PUMP',
          if (f.endedAt != null) 'endDt': f.endedAt!.millisecondsSinceEpoch,
          'volumeMl': f.amountMl,
        };
      case 'solids':
        return {
          ...base,
          'type': 'FEED',
          'feedType': 'SOLID',
          'food': f.details['food'],
        };
      case 'growth':
        return {...base, 'type': 'GROWTH', ...f.details};
      case 'health':
        return {...base, 'type': 'HEALTH', ...f.details};
      case 'routine':
        return {...base, 'type': 'ROUTINE', ...f.details};
      case 'milestone':
        return {...base, 'type': 'MILESTONE', ...f.details};
      default:
        throw FormatException('Unsupported Little Log method: ${f.method}');
    }
  }
}
