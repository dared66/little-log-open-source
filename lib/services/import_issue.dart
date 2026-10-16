class ImportIssue {
  const ImportIssue({
    required this.row,
    required this.type,
    required this.recordId,
    required this.time,
    required this.reason,
    this.requiresConsent = true,
  });
  final int row;
  final String type, recordId, time, reason;
  final bool requiresConsent;
  Map<String, Object?> toJson() => {
    'row': row,
    'type': type,
    'recordId': recordId,
    'time': time,
    'reason': reason,
    'requiresConsent': requiresConsent,
  };
  factory ImportIssue.fromJson(Map<String, Object?> json) => ImportIssue(
    row: json['row'] as int,
    type: json['type'] as String,
    recordId: json['recordId'] as String,
    time: json['time'] as String,
    reason: json['reason'] as String,
    requiresConsent: json['requiresConsent'] as bool? ?? true,
  );
}
