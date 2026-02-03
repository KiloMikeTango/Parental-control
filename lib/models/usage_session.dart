class UsageSession {
  final int? id;
  final String packageName;
  final String appName;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMs;
  final bool sent;

  UsageSession({
    this.id,
    required this.packageName,
    required this.appName,
    required this.startTime,
    this.endTime,
    this.durationMs,
    this.sent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'package_name': packageName,
      'app_name': appName,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'duration_ms': durationMs,
      'sent': sent ? 1 : 0,
    };
  }

  factory UsageSession.fromMap(Map<String, dynamic> map) {
    return UsageSession(
      id: map['id'] as int?,
      packageName: map['package_name'] as String,
      appName: map['app_name'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: map['end_time'] != null
          ? DateTime.parse(map['end_time'] as String)
          : null,
      durationMs: map['duration_ms'] as int?,
      sent: (map['sent'] as int) == 1,
    );
  }

  UsageSession copyWith({
    int? id,
    String? packageName,
    String? appName,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMs,
    bool? sent,
  }) {
    return UsageSession(
      id: id ?? this.id,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMs: durationMs ?? this.durationMs,
      sent: sent ?? this.sent,
    );
  }
}
