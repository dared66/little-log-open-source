import '../models.dart';
import 'family_csv.dart';

/// Partitions records by their UTC start month so every caregiver agrees on the
/// file, even across time zones. This does not expire or delete older history.
abstract final class MonthlyHistory {
  static String monthFor(DateTime at) {
    final utc = at.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-'
        '${utc.month.toString().padLeft(2, '0')}';
  }

  static Map<String, List<Feeding>> group(List<Feeding> records) {
    final months = <String, List<Feeding>>{};
    for (final record in records) {
      months.putIfAbsent(monthFor(record.at), () => []).add(record);
    }
    final keys = months.keys.toList()..sort();
    return {
      for (final key in keys)
        key: months[key]!
          ..sort((a, b) {
            final byTime = a.at.compareTo(b.at);
            return byTime != 0 ? byTime : a.id.compareTo(b.id);
          }),
    };
  }

  /// Produce self-contained CSVs using the existing portable schema.
  static Map<String, String> encode(Family family, List<Feeding> records) {
    if (records.any((record) => record.familyId != family.id)) {
      throw const FormatException(
        'Cannot partition records from another family.',
      );
    }
    return {
      for (final entry in group(records).entries)
        '${entry.key}.csv': FamilyCsv(family, entry.value).encode(),
    };
  }
}
