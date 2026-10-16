import 'activity_details.dart';

const defaultQuickLog = ['bottle', 'nursing', 'diaper', 'sleep'];
const maxQuickLogItems = 6;
const quickLogActivities = {
  'bottle': 'Bottle',
  'nursing': 'Nursing',
  'diaper': 'Diaper',
  ...activityNames,
};

List<String> validQuickLog(Object? stored) {
  if (stored is! List) return [...defaultQuickLog];
  final choices = <String>[];
  for (final item in stored) {
    if (item is String &&
        quickLogActivities.containsKey(item) &&
        !choices.contains(item) &&
        choices.length < maxQuickLogItems) {
      choices.add(item);
    }
  }
  return choices.isEmpty ? [...defaultQuickLog] : choices;
}
