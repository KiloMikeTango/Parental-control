class Interruption {
  final int? id;
  final DateTime fromTime;
  final DateTime toTime;
  final int durationMs;
  final bool sent;

  Interruption({
    this.id,
    required this.fromTime,
    required this.toTime,
    required this.durationMs,
    this.sent = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'from_time': fromTime.toIso8601String(),
      'to_time': toTime.toIso8601String(),
      'duration_ms': durationMs,
      'sent': sent ? 1 : 0,
    };
  }

  factory Interruption.fromMap(Map<String, dynamic> map) {
    return Interruption(
      id: map['id'] as int?,
      fromTime: DateTime.parse(map['from_time'] as String),
      toTime: DateTime.parse(map['to_time'] as String),
      durationMs: map['duration_ms'] as int,
      sent: (map['sent'] as int) == 1,
    );
  }

  Interruption copyWith({
    int? id,
    DateTime? fromTime,
    DateTime? toTime,
    int? durationMs,
    bool? sent,
  }) {
    return Interruption(
      id: id ?? this.id,
      fromTime: fromTime ?? this.fromTime,
      toTime: toTime ?? this.toTime,
      durationMs: durationMs ?? this.durationMs,
      sent: sent ?? this.sent,
    );
  }
}
