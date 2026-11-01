// Synthetic medical entries surrounded by supported activities. Padding uses
// logical CSV rows so multiline notes do not change the reported row number.
String naraMedicalCsvFixture({
  String note = '',
  Map<String, String> medical = const {},
  int medicalRow = 3,
}) {
  assert(medicalRow >= 3);
  Map<String, String> row(String type, String id, int index) {
    final at = DateTime.utc(2026, 10, 13, 12).add(Duration(seconds: index));
    return {
      'Type': type,
      'Profile Name': 'Schema Baby',
      'Start Date/time': at.toIso8601String(),
      'Start Date/time (Epoch)': '${at.millisecondsSinceEpoch}',
      'Created By Caregiver': 'Synthetic caregiver',
      'Note': '',
      'Time Zone': 'UTC',
      '_familyKey': 'synthetic-medical-family',
      '_profileKey': 'synthetic-medical-baby',
      '_activityKey': id,
    };
  }

  final rows = [
    for (var i = 0; i < medicalRow - 2; i++)
      {
        ...row('Diaper', 'medical-diaper-before-$i', i),
        '[Diaper] Type': 'Wet',
      },
    {
      ...row('Medical', 'medical-entry', medicalRow - 2),
      'Note': note,
      for (final field in medical.entries) '[Medical] ${field.key}': field.value,
    },
    {
      ...row('Diaper', 'medical-diaper-after', medicalRow - 1),
      '[Diaper] Type': 'Dirty',
    },
  ];
  final header = {
    ...rows.expand((r) => r.keys),
    '[Medical] Medication',
    '[Medical] Temperature',
    '[Medical] Temperature Unit',
  }.toList();
  String line(Iterable<String> cells) =>
      cells.map((s) => '"${s.replaceAll('"', '""')}"').join(',');
  return [
    line(header),
    for (final r in rows) line(header.map((k) => r[k] ?? '')),
  ].join('\r\n');
}
