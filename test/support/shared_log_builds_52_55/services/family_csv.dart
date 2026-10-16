import 'dart:convert';
import '../models.dart';

/// The CSV is the portable working record, including family metadata.
class FamilyCsv {
  FamilyCsv(this.family, this.feeds);
  final Family family;
  final List<Feeding> feeds;
  static const header = [
    'record_type',
    'format_version',
    'family_name',
    'baby_name',
    'id',
    'family_id',
    'time_utc',
    'method',
    'amount_ml',
    'minutes',
    'note',
    'caregiver',
    'schema_version',
    'ended_at_utc',
    'left_seconds',
    'right_seconds',
    'diaper_kind',
    'details_json',
  ];
  static const maxBytes = 10 * 1024 * 1024;

  String encode() {
    final rows = <List<Object>>[
      header,
      [
        'family',
        '1',
        family.name,
        family.babyName,
        '',
        family.id,
        ...List.filled(12, ''),
      ],
      ...feeds.map(
        (f) => ['event', '1', '', '', ...f.toRow(), if (!f.hasDetailRow) ''],
      ),
    ];
    final text = "${rows.map((r) => r.map(_cell).join(',')).join('\r\n')}\r\n";
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException(
        'This CSV exceeds the 10 MB limit. Your local entries are retained.',
      );
    }
    return text;
  }

  // Escape formula-like cells reversibly, including literal leading apostrophes.
  static String _cell(Object value) {
    var text = value.toString();
    if (text.isNotEmpty && "'=+-@\t\r\n".contains(text[0])) text = "'$text";
    return '"${text.replaceAll('"', '""')}"';
  }

  static FamilyCsv decode(String text, {String? fileId, String? accountId}) {
    if (utf8.encode(text).length > maxBytes) {
      throw const FormatException('This CSV exceeds the 10 MB limit.');
    }
    final rows = parseRows(
      text.startsWith('\ufeff') ? text.substring(1) : text,
      unescapeFormulas: true,
    );
    final legacy =
        rows.isNotEmpty &&
        jsonEncode(rows.first) == jsonEncode(header.sublist(0, 17));
    if (rows.length < 2 ||
        (!legacy && jsonEncode(rows.first) != jsonEncode(header))) {
      throw const FormatException(
        'Choose a Nara Baby export or Little Log CSV backup.',
      );
    }
    if (legacy) {
      for (final row in rows.skip(1)) {
        if (row.length != 17) {
          throw const FormatException('Invalid legacy CSV row.');
        }
        row.add('');
      }
    }
    final meta = rows[1];
    if (meta.length != header.length ||
        meta[0] != 'family' ||
        meta[1] != '1' ||
        meta[5].isEmpty ||
        meta[2].isEmpty ||
        meta[3].isEmpty ||
        meta[4].isNotEmpty ||
        meta.skip(6).any((c) => c.isNotEmpty)) {
      throw const FormatException('Invalid Little Log CSV family metadata.');
    }
    final family = Family(
      id: meta[5],
      name: meta[2],
      babyName: meta[3],
      driveFileId: fileId,
      accountId: accountId,
    );
    final feeds = <String, Feeding>{};
    for (final row in rows.skip(2)) {
      if (row.length != header.length ||
          row[0] != 'event' ||
          row[1] != '1' ||
          row[2].isNotEmpty ||
          row[3].isNotEmpty) {
        throw const FormatException(
          'An unsupported CSV row prevents safe syncing. No cloud records were overwritten.',
        );
      }
      final feed = Feeding.fromRow(row.sublist(4), family.id);
      final previous = feeds[feed.id];
      if (previous != null &&
          jsonEncode(previous.originalRow) != jsonEncode(feed.originalRow)) {
        throw const FormatException(
          'Conflicting records use the same ID. No cloud records were overwritten.',
        );
      }
      if (previous?.deleted != true) feeds[feed.id] = feed;
    }
    return FamilyCsv(family, feeds.values.toList());
  }

  static List<List<String>> parseRows(
    String text, {
    bool unescapeFormulas = false,
  }) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false, closed = false;
    void finishCell() {
      var value = cell.toString();
      if (unescapeFormulas &&
          value.startsWith("'") &&
          value.length > 1 &&
          "'=+-@\t\r\n".contains(value[1])) {
        value = value.substring(1);
      }
      row.add(value);
      cell = StringBuffer();
      closed = false;
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
            closed = true;
          }
        } else {
          cell.write(char);
        }
      } else if (char == ',' || char == '\r' || char == '\n') {
        finishCell();
        if (char != ',') {
          rows.add(row);
          row = [];
          if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        }
      } else if (char == '"' && cell.isEmpty && !closed) {
        quoted = true;
      } else {
        if (closed || char == '"') {
          throw const FormatException('Malformed CSV quoting.');
        }
        cell.write(char);
      }
    }
    if (quoted) {
      throw const FormatException(
        'Incomplete CSV file. Retry after Drive finishes uploading.',
      );
    }
    if (cell.isNotEmpty || closed || row.isNotEmpty) {
      finishCell();
      rows.add(row);
    }
    return rows;
  }
}
