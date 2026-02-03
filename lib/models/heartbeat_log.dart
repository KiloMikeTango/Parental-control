class HeartbeatLog {
  final int? id;
  final DateTime timestamp;

  HeartbeatLog({this.id, required this.timestamp});

  Map<String, dynamic> toMap() {
    return {'id': id, 'timestamp': timestamp.toIso8601String()};
  }

  factory HeartbeatLog.fromMap(Map<String, dynamic> map) {
    return HeartbeatLog(
      id: map['id'] as int?,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
