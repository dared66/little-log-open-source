import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'activity_details.dart';
import 'diaper_details.dart';
import 'record_validation.dart';

const newId = Uuid();

class Family {
  const Family({
    required this.id,
    required this.name,
    required this.babyName,
    this.driveFileId,
    this.accountId,
    this.legacySheetId,
    this.ownerEmail,
    this.ownerName,
    this.driveShared,
  });
  final String id;
  final String name;
  final String babyName;
  final String? driveFileId;
  final String? accountId;
  final String? legacySheetId;
  final String? ownerEmail;
  final String? ownerName;
  final bool? driveShared;
  String get storageLabel => isLocal
      ? 'On this device'
      : driveShared == true
      ? 'Shared Google Drive log'
      : driveShared == false
      ? 'Private Google Drive log'
      : 'Google Drive log';
  String get ownerLabel => isLocal
      ? 'On this device'
      : ownerEmail?.isNotEmpty == true
      ? 'Log’s Drive account: $ownerEmail'
      : 'Log’s Drive account not yet verified';
  String get logReference => driveFileId ?? id;
  Family withDriveIdentity({String? email, String? name, bool? shared}) =>
      Family(
        id: id,
        name: this.name,
        babyName: babyName,
        driveFileId: driveFileId,
        accountId: accountId,
        legacySheetId: legacySheetId,
        ownerEmail: email,
        ownerName: name,
        driveShared: shared,
      );
  // Legacy Sheet connections are deliberately not interpreted as CSV files.
  bool get isLocal => driveFileId == null;
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'babyName': babyName,
    'driveFileId': driveFileId,
    'accountId': accountId,
    'legacySheetId': legacySheetId,
    'ownerEmail': ownerEmail,
    'ownerName': ownerName,
    'driveShared': driveShared,
  };
  factory Family.fromJson(Map<String, Object?> json) => Family(
    id: json['id'] as String,
    name: json['name'] as String,
    babyName: json['babyName'] as String,
    driveFileId: json['driveFileId'] as String?,
    accountId: json['accountId'] as String?,
    ownerEmail: json['ownerEmail'] as String?,
    ownerName: json['ownerName'] as String?,
    driveShared: json['driveShared'] as bool?,
    legacySheetId: (json['legacySheetId'] ?? json['sheetId']) as String?,
  );
}

class Feeding {
  const Feeding({
    required this.id,
    required this.familyId,
    required this.at,
    required this.method,
    this.endedAt,
    this.leftSeconds,
    this.rightSeconds,
    this.diaperKind,
    this.details = const {},
    this.source = const {},
    this.amountMl,
    this.minutes,
    this.note = '',
    this.author = '',
    this.synced = false,
    this.deleted = false,
  });
  final String id;
  final String familyId;
  final DateTime at;
  final String method;
  final DateTime? endedAt;
  final int? leftSeconds;
  final int? rightSeconds;
  final String? diaperKind;
  final Map<String, Object?> details;
  final Map<String, Object?> source;
  bool get usesV6 =>
      source.isNotEmpty ||
      method == 'profile' ||
      (method == 'bottle' && details.isNotEmpty) ||
      (method == 'nursing' && leftSeconds != null && endedAt == null) ||
      details.containsKey('poopColors') ||
      details.containsKey('poopConsistencies');
  bool get isFeeding => ['bottle', 'nursing', 'solids'].contains(method);
  bool get isExtended => activityNames.containsKey(method);
  bool get isDiaper => method == 'diaper';
  bool get hasDetailRow =>
      deleted || usesV6 || isExtended || (isDiaper && details.isNotEmpty);
  final double? amountMl;
  final int? minutes;
  final String note;
  final String author;
  final bool synced;
  final bool deleted;
  Feeding asDeleted() =>
      Feeding.fromJson({...toJson(), 'deleted': true, 'synced': false});
  List<Object> get originalRow =>
      Feeding.fromJson({...toJson(), 'deleted': false}).toRow();
  Map<String, Object?> toJson() => {
    'id': id,
    'familyId': familyId,
    'at': at.toUtc().toIso8601String(),
    'method': method,
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'leftSeconds': leftSeconds,
    'rightSeconds': rightSeconds,
    'diaperKind': diaperKind,
    'details': details,
    'source': source,
    'amountMl': amountMl,
    'minutes': minutes,
    'note': note,
    'author': author,
    'synced': synced,
    'deleted': deleted,
  };
  factory Feeding.fromJson(Map<String, Object?> j) => Feeding(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    at: DateTime.parse(j['at'] as String),
    method: j['method'] as String,
    endedAt: j['endedAt'] == null
        ? null
        : DateTime.parse(j['endedAt'] as String),
    leftSeconds: j['leftSeconds'] as int?,
    rightSeconds: j['rightSeconds'] as int?,
    diaperKind: j['diaperKind'] as String?,
    details: Map<String, Object?>.from(j['details'] as Map? ?? {}),
    source: Map<String, Object?>.from(j['source'] as Map? ?? {}),
    amountMl: (j['amountMl'] as num?)?.toDouble(),
    minutes: j['minutes'] as int?,
    note: j['note'] as String? ?? '',
    author: j['author'] as String? ?? '',
    synced: j['synced'] as bool? ?? false,
    deleted: j['deleted'] as bool? ?? false,
  );
  Feeding acknowledged() => Feeding.fromJson({...toJson(), 'synced': true});
  // Builds 52–55 reject pumping details but preserve extensions in the v6
  // source envelope. Keep active time there on the wire, without changing the
  // real start/end, visible note or existing import provenance.
  Feeding _portablePumping() {
    if (method != 'pumping' || !details.containsKey('activeSeconds')) {
      return this;
    }
    validateActivity(this, familyId);
    return Feeding.fromJson({
      ...toJson(),
      'details': {...details}..remove('activeSeconds'),
      'source': {
        if (source.isEmpty) ...{
          'system': 'Little Log',
          'recordId': id,
          'original': <String, Object?>{},
        },
        ...source,
        'littleLogTimer': {
          'version': 1,
          'startedAt': at.toUtc().toIso8601String(),
          'endedAt': endedAt!.toUtc().toIso8601String(),
          'activeSeconds': details['activeSeconds'],
        },
      },
    });
  }

  Feeding _restorePumpingDuration() {
    final timer = source['littleLogTimer'];
    if (method != 'pumping' ||
        details.containsKey('activeSeconds') ||
        timer is! Map ||
        timer['version'] != 1 ||
        timer['startedAt'] is! String ||
        timer['endedAt'] is! String ||
        DateTime.tryParse(timer['startedAt'] as String) != at ||
        DateTime.tryParse(timer['endedAt'] as String) != endedAt ||
        timer['activeSeconds'] is! int ||
        (timer['activeSeconds'] as int) < 0 ||
        endedAt == null ||
        (timer['activeSeconds'] as int) > endedAt!.difference(at).inSeconds) {
      // An older client can edit start/end without understanding timer metadata.
      // Honor those edits instead of applying a now-stale active duration.
      return this;
    }
    return Feeding.fromJson({
      ...toJson(),
      'details': {...details, 'activeSeconds': timer['activeSeconds']},
    });
  }

  List<Object> toRow() => _portablePumping()._toRow();
  List<Object> _toRow() => deleted
      ? [
          id,
          familyId,
          at.toUtc().toIso8601String(),
          method,
          '',
          '',
          '',
          '',
          5,
          '',
          '',
          '',
          '',
          jsonEncode(originalRow),
        ]
      : [
          id,
          familyId,
          at.toUtc().toIso8601String(),
          method,
          amountMl ?? '',
          minutes ?? '',
          note,
          author,
          usesV6
              ? 6
              : isDiaper && details.isNotEmpty
              ? 4
              : isExtended
              ? 3
              : endedAt != null || diaperKind != null || leftSeconds != null
              ? 2
              : 1,
          endedAt?.toUtc().toIso8601String() ?? '',
          leftSeconds ?? '',
          rightSeconds ?? '',
          diaperKind ?? '',
          if (hasDetailRow)
            jsonEncode(
              usesV6
                  ? {'details': details, 'source': source}
                  : isDiaper
                  ? Map<String, Object?>.fromEntries(
                      details.entries.toList()
                        ..sort((a, b) => a.key.compareTo(b.key)),
                    )
                  : details,
            ),
        ];
  static Feeding fromRow(List<dynamic> row, String expectedFamily) {
    String cell(int index) => index < row.length ? row[index].toString() : '';
    final method = cell(3);
    if (cell(8) == '5') {
      final original = jsonDecode(cell(13));
      if (original is! List ||
          original.length < 9 ||
          original[8].toString() == '5') {
        throw const FormatException('Invalid deleted record.');
      }
      final record = Feeding.fromRow(original, expectedFamily);
      if (record.id != cell(0) ||
          record.familyId != cell(1) ||
          record.method != method ||
          record.at != DateTime.parse(cell(2))) {
        throw const FormatException('Deleted record does not match original.');
      }
      return Feeding.fromJson({...record.toJson(), 'deleted': true});
    }
    if (cell(8) == '6') {
      final payload = jsonDecode(cell(13));
      if (payload is! Map<String, dynamic> ||
          payload.keys.any((k) => !['details', 'source'].contains(k)) ||
          payload['details'] is! Map ||
          payload['source'] is! Map) {
        throw const FormatException('Invalid extended record.');
      }
      final record = Feeding(
        id: cell(0),
        familyId: cell(1),
        at: DateTime.parse(cell(2)),
        method: method,
        amountMl: cell(4).isEmpty ? null : double.parse(cell(4)),
        minutes: cell(5).isEmpty ? null : int.parse(cell(5)),
        note: cell(6),
        author: cell(7),
        endedAt: cell(9).isEmpty ? null : DateTime.parse(cell(9)),
        leftSeconds: cell(10).isEmpty ? null : int.parse(cell(10)),
        rightSeconds: cell(11).isEmpty ? null : int.parse(cell(11)),
        diaperKind: cell(12).isEmpty ? null : cell(12),
        details: Map<String, Object?>.from(payload['details']),
        source: Map<String, Object?>.from(payload['source']),
        synced: true,
      )._restorePumpingDuration();
      validateRecord(record, expectedFamily);
      if (!record.usesV6) {
        throw const FormatException('Noncanonical extended record.');
      }
      return record;
    }
    if (cell(8) == '4') {
      final parsed = jsonDecode(cell(13));
      if (parsed is! Map<String, dynamic> ||
          [4, 5, 9, 10, 11].any((i) => cell(i).isNotEmpty)) {
        throw const FormatException('Invalid diaper record.');
      }
      final record = Feeding(
        id: cell(0),
        familyId: cell(1),
        at: DateTime.parse(cell(2)),
        method: method,
        diaperKind: cell(12),
        details: parsed,
        note: cell(6),
        author: cell(7),
        synced: true,
      );
      validateDiaper(record, expectedFamily);
      return record;
    }
    if (cell(8) == '3') {
      final parsed = jsonDecode(cell(13));
      if (parsed is! Map<String, dynamic>) {
        throw const FormatException('Invalid activity details.');
      }
      final record = Feeding(
        id: cell(0),
        familyId: cell(1),
        at: DateTime.parse(cell(2)),
        method: method,
        endedAt: cell(9).isEmpty ? null : DateTime.parse(cell(9)),
        amountMl: cell(4).isEmpty ? null : double.parse(cell(4)),
        note: cell(6),
        author: cell(7),
        details: parsed,
        synced: true,
      );
      validateActivity(record, expectedFamily);
      if (cell(5).isNotEmpty ||
          cell(10).isNotEmpty ||
          cell(11).isNotEmpty ||
          cell(12).isNotEmpty) {
        throw const FormatException('Unexpected activity fields.');
      }
      return record;
    }
    if (cell(13).isNotEmpty) {
      throw const FormatException('Unsupported activity details.');
    }
    final amount = cell(4).isEmpty ? null : double.tryParse(cell(4));
    final minutes = cell(5).isEmpty ? null : int.tryParse(cell(5));
    if (cell(0).isEmpty ||
        cell(1) != expectedFamily ||
        !['1', '2'].contains(cell(8)) ||
        !['bottle', 'nursing', 'diaper'].contains(method) ||
        (method == 'bottle' &&
            (amount == null ||
                !amount.isFinite ||
                amount <= 0 ||
                amount > 2000)) ||
        (method == 'nursing' &&
            cell(8) == '1' &&
            (minutes == null || minutes <= 0 || minutes > 240)) ||
        cell(6).length > 2000) {
      throw const FormatException('Unrecognized feeding record');
    }
    final endedAt = cell(9).isEmpty ? null : DateTime.tryParse(cell(9));
    final left = int.tryParse(cell(10));
    final right = int.tryParse(cell(11));
    final at = DateTime.parse(cell(2));
    if ((method == 'diaper' &&
            (cell(8) != '2' ||
                !['wet', 'dirty', 'both', 'dry'].contains(cell(12)))) ||
        (method == 'nursing' &&
            cell(8) == '2' &&
            (endedAt == null ||
                endedAt.isBefore(at) ||
                left == null ||
                right == null ||
                left < 0 ||
                right < 0 ||
                left + right > endedAt.difference(at).inSeconds))) {
      throw const FormatException('Invalid activity details');
    }
    return Feeding(
      endedAt: endedAt,
      leftSeconds: left,
      rightSeconds: right,
      diaperKind: method == 'diaper' ? cell(12) : null,
      id: cell(0),
      familyId: expectedFamily,
      at: DateTime.parse(cell(2)),
      method: method,
      amountMl: amount,
      minutes: minutes,
      note: cell(6),
      author: cell(7),
      synced: true,
    );
  }
}

/// A local, durable session. Completed sessions use the shared event log.
class NursingSession {
  const NursingSession({
    required this.id,
    required this.familyId,
    required this.startedAt,
    required this.segmentAt,
    required this.side,
    this.leftSeconds = 0,
    this.rightSeconds = 0,
    this.paused = false,
    this.note = '',
    this.source = const {},
    this.revision = 0,
  });
  final String id, familyId, side;
  final DateTime startedAt, segmentAt;
  final int leftSeconds, rightSeconds;
  final bool paused;
  final int revision;
  final String note;
  final Map<String, Object?> source;
  int secondsFor(String target, DateTime now) =>
      (target == 'left' ? leftSeconds : rightSeconds) +
      (!paused && side == target
          ? now.difference(segmentAt).inSeconds.clamp(0, 2147483647)
          : 0);
  NursingSession switchTo(String next, DateTime now) {
    if (!['left', 'right'].contains(next) || now.isBefore(segmentAt)) {
      throw const FormatException('Check the side and device clock.');
    }
    return NursingSession(
      id: id,
      familyId: familyId,
      startedAt: startedAt,
      segmentAt: now,
      side: next,
      leftSeconds: secondsFor('left', now),
      rightSeconds: secondsFor('right', now),
      note: note,
      source: source,
      revision: revision + 1,
    );
  }

  NursingSession pause(DateTime now) {
    if (paused) return this;
    if (now.isBefore(segmentAt)) {
      throw const FormatException('Check the device clock.');
    }
    return NursingSession(
      id: id,
      familyId: familyId,
      startedAt: startedAt,
      segmentAt: now,
      side: side,
      leftSeconds: secondsFor('left', now),
      rightSeconds: secondsFor('right', now),
      paused: true,
      note: note,
      source: source,
      revision: revision + 1,
    );
  }

  NursingSession resume(DateTime now) => paused ? switchTo(side, now) : this;

  Feeding finish(DateTime now, String author) {
    if (now.isBefore(segmentAt)) {
      throw const FormatException('Check the device clock.');
    }
    final left = secondsFor('left', now), right = secondsFor('right', now);
    return Feeding(
      id: id,
      familyId: familyId,
      at: startedAt,
      endedAt: now,
      method: 'nursing',
      leftSeconds: left,
      rightSeconds: right,
      minutes: ((left + right) / 60).ceil(),
      author: author,
      note: note,
      source: source,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'familyId': familyId,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'segmentAt': segmentAt.toUtc().toIso8601String(),
    'side': side,
    'paused': paused,
    'revision': revision,
    'leftSeconds': leftSeconds,
    'rightSeconds': rightSeconds,
    'note': note,
    'source': source,
  };
  factory NursingSession.fromJson(Map<String, Object?> j) => NursingSession(
    id: j['id'] as String,
    familyId: j['familyId'] as String,
    startedAt: DateTime.parse(j['startedAt'] as String),
    segmentAt: DateTime.parse(j['segmentAt'] as String),
    side: j['side'] as String,
    paused: j['paused'] as bool? ?? false,
    revision: j['revision'] as int? ?? 0,
    leftSeconds: j['leftSeconds'] as int,
    rightSeconds: j['rightSeconds'] as int,
    note: j['note'] as String? ?? '',
    source: Map<String, Object?>.from(j['source'] as Map? ?? {}),
  );
}
