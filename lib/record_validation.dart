import 'models.dart';
import 'activity_details.dart';
import 'diaper_details.dart';

void validateRecord(Feeding r, String familyId) {
  if (r.id.isEmpty ||
      r.familyId != familyId ||
      r.note.length > 2000 ||
      (r.endedAt?.isBefore(r.at) ?? false)) {
    throw const FormatException('Check the entry details.');
  }
  if (r.source.isNotEmpty &&
      (r.source['system'] is! String ||
          r.source['recordId'] is! String ||
          r.source['original'] is! Map)) {
    throw const FormatException('Invalid import source.');
  }
  if (r.method == 'diaper') {
    validateDiaper(r, familyId);
  } else if (r.method == 'bottle') {
    final d = r.details;
    final milk = d['breastMilkMl'], formula = d['formulaMl'];
    bool volume(Object? v) => v is num && v.isFinite && v >= 0 && v <= 2000;
    if (r.amountMl == null ||
        !r.amountMl!.isFinite ||
        r.amountMl! <= 0 ||
        r.amountMl! > 2000 ||
        r.minutes != null ||
        r.leftSeconds != null ||
        r.rightSeconds != null ||
        r.endedAt != null ||
        r.diaperKind != null ||
        d.keys.any(
          (k) => !['breastMilkMl', 'formulaMl', 'formulaName'].contains(k),
        ) ||
        (d.isNotEmpty &&
            (!volume(milk) ||
                !volume(formula) ||
                ((milk as num) + (formula as num) - r.amountMl!).abs() >
                    0.00001)) ||
        (d.containsKey('formulaName') &&
            (d['formulaName'] is! String ||
                (d['formulaName'] as String).length > 500))) {
      throw const FormatException(
        'Milk and formula amounts must add up to the bottle total.',
      );
    }
  } else if (r.method == 'nursing') {
    final l = r.leftSeconds, right = r.rightSeconds;
    if (r.amountMl != null ||
        r.diaperKind != null ||
        r.details.isNotEmpty ||
        (l == null) != (right == null) ||
        (l == null && (r.minutes == null || r.minutes! <= 0)) ||
        (l != null &&
            (l < 0 ||
                right! < 0 ||
                (r.endedAt != null &&
                    l + right > r.endedAt!.difference(r.at).inSeconds)))) {
      throw const FormatException('Check nursing durations and end time.');
    }
  } else if (r.method == 'profile') {
    validateProfile(r.details);
    if (r.amountMl != null ||
        r.minutes != null ||
        r.endedAt != null ||
        r.leftSeconds != null ||
        r.rightSeconds != null ||
        r.diaperKind != null) {
      throw const FormatException('Invalid baby profile.');
    }
  } else {
    validateActivity(r, familyId);
  }
}

void validateProfile(Map<String, Object?> d) {
  if (d.keys.any(
    (k) => !['birthDate', 'gender', 'nightStart', 'nightEnd'].contains(k),
  )) {
    throw const FormatException('Unknown baby profile field.');
  }
  if (d['birthDate'] != null) {
    final date = d['birthDate'];
    final parsed = date is String ? DateTime.tryParse(date) : null;
    if (parsed == null ||
        parsed.toIso8601String().substring(0, 10) != date ||
        parsed.isAfter(DateTime.now())) {
      throw const FormatException('Choose a valid birth date.');
    }
  }
  if (d['gender'] != null &&
      !['FEMALE', 'MALE', 'OTHER', 'UNSPECIFIED'].contains(d['gender'])) {
    throw const FormatException('Choose a valid sex.');
  }
  for (final key in ['nightStart', 'nightEnd']) {
    if (d[key] != null &&
        (d[key] is! String ||
            !RegExp(
              r'^(?:[01]\d|2[0-3]):[0-5]\d$',
            ).hasMatch(d[key] as String))) {
      throw const FormatException('Use a valid time in HH:mm format.');
    }
  }
}

String bottleContentsLabel(Feeding r) {
  final milk = r.details['breastMilkMl'] as num?;
  final formula = r.details['formulaMl'] as num?;
  if (milk == null || formula == null) return '';
  if (milk > 0 && formula > 0) return 'Breast milk + formula';
  return milk > 0 ? 'Breast milk' : 'Formula';
}
