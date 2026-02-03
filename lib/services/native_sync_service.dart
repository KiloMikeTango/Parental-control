import 'package:shared_preferences/shared_preferences.dart';
import '../models/usage_session.dart';
import '../models/heartbeat_log.dart';
import '../models/interruption.dart';
import '../services/database_service.dart';
import 'dart:async';

class NativeSyncService {
  final DatabaseService _database = DatabaseService();
  Timer? _syncTimer;

  // Start polling for usage sessions from native side
  void startPolling() {
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await syncUsageSessions();
      await syncHeartbeats();
      await syncInterruptions();
    });
  }

  void stopPolling() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> syncUsageSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('session_')).toList();
      
      for (final key in keys) {
        if (key.endsWith('_package')) {
          final sessionId = key.replaceAll('_package', '');
          final packageName = prefs.getString(key);
          final appName = prefs.getString('${sessionId}_name');
          final startTime = prefs.getInt('${sessionId}_start');
          final endTime = prefs.getInt('${sessionId}_end');
          final duration = prefs.getInt('${sessionId}_duration');

          if (packageName != null && appName != null && startTime != null) {
            final session = UsageSession(
              packageName: packageName,
              appName: appName,
              startTime: DateTime.fromMillisecondsSinceEpoch(startTime),
              endTime: endTime != null ? DateTime.fromMillisecondsSinceEpoch(endTime) : null,
              durationMs: duration,
            );

            // Insert into database
            await _database.insertUsageSession(session);

            // Remove from SharedPreferences
            await prefs.remove(key);
            await prefs.remove('${sessionId}_name');
            await prefs.remove('${sessionId}_start');
            if (endTime != null) await prefs.remove('${sessionId}_end');
            if (duration != null) await prefs.remove('${sessionId}_duration');
          }
        }
      }
    } catch (e) {
      print('Error syncing usage sessions: $e');
    }
  }

  Future<void> syncHeartbeats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastHeartbeat = prefs.getInt('last_heartbeat');
      
      if (lastHeartbeat != null) {
        final heartbeat = HeartbeatLog(
          timestamp: DateTime.fromMillisecondsSinceEpoch(lastHeartbeat),
        );
        await _database.insertHeartbeat(heartbeat);
      }
    } catch (e) {
      print('Error syncing heartbeats: $e');
    }
  }

  Future<void> syncInterruptions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith('interruption_')).toList();
      
      for (final key in keys) {
        if (key.endsWith('_from')) {
          final interruptionId = key.replaceAll('_from', '');
          final fromTime = prefs.getInt(key);
          final toTime = prefs.getInt('${interruptionId}_to');
          final duration = prefs.getInt('${interruptionId}_duration');

          if (fromTime != null && toTime != null && duration != null) {
            final interruption = Interruption(
              fromTime: DateTime.fromMillisecondsSinceEpoch(fromTime),
              toTime: DateTime.fromMillisecondsSinceEpoch(toTime),
              durationMs: duration,
            );

            await _database.insertInterruption(interruption);

            // Remove from SharedPreferences
            await prefs.remove(key);
            await prefs.remove('${interruptionId}_to');
            await prefs.remove('${interruptionId}_duration');
          }
        }
      }
    } catch (e) {
      print('Error syncing interruptions: $e');
    }
  }
}
