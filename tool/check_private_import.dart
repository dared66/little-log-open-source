import 'dart:convert';
import 'dart:io';
import 'package:little_log/models.dart';
import 'package:little_log/services/history_import.dart';

void main(List<String> args) {
  final text = File(args.single).readAsStringSync();
  final raw = text.startsWith('{')
      ? jsonDecode(text) as Map<String, dynamic>
      : null;
  final family = Family(
    id: 'private-fixture-check',
    name: 'Local test',
    babyName: raw == null ? 'Imported baby' : raw['profile']['name'] as String,
  );
  final plan = HistoryImport.preview(text, family, []);
  final repeat = HistoryImport.preview(text, family, plan.additions);
  if ((raw != null && plan.activityCount != (raw['tracks'] as Map).length) ||
      repeat.additions.isNotEmpty) {
    throw StateError('Import count or deduplication mismatch');
  }
  final withPumps = HistoryImport.preview(
    text,
    family,
    [],
    includeUnassignedPumps: true,
  );
  stdout.writeln(
    'Unassigned pumps: ${plan.unassignedPumps}; including them: ${withPumps.activityCount} activities',
  );
  stdout.writeln(
    'Verified ${plan.activityCount} activities, ${plan.additions.length - plan.activityCount} profile, ${repeat.duplicates} duplicates on reimport. No writes.',
  );
}
