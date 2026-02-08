import 'package:shared_preferences/shared_preferences.dart';
import '../models/usage_session.dart';
import '../models/heartbeat_log.dart';
import '../models/interruption.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';
import 'dart:async';

class NativeSyncService {
  final DatabaseService _database = DatabaseService();
  Timer? _syncTimer;

  // Start polling for usage sessions from native side
  void startPolling() {
    print('NativeSync: Starting polling service');
    // Do immediate sync first
    syncUsageStarts();
    syncUsageSessions();
    syncHeartbeats();
    syncInterruptions();

    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      print('NativeSync: Periodic sync triggered');
      await syncUsageStarts();
      await syncUsageSessions();
      await syncHeartbeats();
      await syncInterruptions();

      // Also trigger Telegram sync periodically to catch any missed sessions
      try {
        print('NativeSync: Triggering periodic Telegram sync');
        final syncService = SyncService();
        await syncService.syncAll();
      } catch (e) {
        print('NativeSync: Error in periodic Telegram sync: $e');
      }
    });
  }

  void stopPolling() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  Future<void> syncUsageStarts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final allKeys = prefs.getKeys();

      final startKeys = allKeys
          .where(
            (key) =>
                key.startsWith('flutter.enter_') && key.endsWith('_package'),
          )
          .toList();

      final legacyKeys = allKeys
          .where(
            (key) =>
                key.startsWith('enter_') &&
                key.endsWith('_package') &&
                !key.startsWith('flutter.'),
          )
          .toList();

      final allStartKeys = [...startKeys, ...legacyKeys];

      final events = <_StartEntry>[];
      for (final key in allStartKeys) {
        final isLegacy = !key.startsWith('flutter.');
        final eventId = key
            .replaceFirst('flutter.', '')
            .replaceAll('_package', '');
        final prefix = isLegacy ? '' : 'flutter.';

        final packageName = prefs.getString(key);
        final appName = prefs.getString('${prefix}${eventId}_name');
        final timeStr = prefs.getString('${prefix}${eventId}_time');

        if (packageName != null && timeStr != null) {
          final timeMs = int.tryParse(timeStr);
          if (timeMs == null) {
            await prefs.remove(key);
            await prefs.remove('${prefix}${eventId}_name');
            await prefs.remove('${prefix}${eventId}_time');
            continue;
          }
          events.add(
            _StartEntry(
              key: key,
              prefix: prefix,
              eventId: eventId,
              packageName: packageName,
              appName: appName ?? packageName,
              timeMs: timeMs,
            ),
          );
        }
      }

      events.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      for (final entry in events) {
        final startTime = DateTime.fromMillisecondsSinceEpoch(entry.timeMs);
        final session = UsageSession(
          packageName: entry.packageName,
          appName: entry.appName,
          startTime: startTime,
          endTime: null,
          durationMs: null,
        );
        await _database.insertUsageSession(session);
        await prefs.remove(entry.key);
        await prefs.remove('${entry.prefix}${entry.eventId}_name');
        await prefs.remove('${entry.prefix}${entry.eventId}_time');
      }
    } catch (e) {
      print('Error syncing usage starts: $e');
    }
  }

  Future<void> syncUsageSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final allKeys = prefs.getKeys();
      print('NativeSync: All SharedPreferences keys count: ${allKeys.length}');

      // Debug: Print first few keys to see what we have
      if (allKeys.isNotEmpty) {
        final sampleKeys = allKeys.take(10).toList();
        print('NativeSync: Sample keys: $sampleKeys');
      }

      // Find all session keys - they follow pattern: flutter.session_TIMESTAMP_package
      final sessionKeys = allKeys
          .where(
            (key) =>
                key.startsWith('flutter.session_') && key.endsWith('_package'),
          )
          .toList();
      print('NativeSync: Found ${sessionKeys.length} session keys');

      // Also check for keys without flutter prefix (legacy format)
      final legacyKeys = allKeys
          .where(
            (key) =>
                key.startsWith('session_') &&
                key.endsWith('_package') &&
                !key.startsWith('flutter.'),
          )
          .toList();
      print(
        'NativeSync: Found ${legacyKeys.length} legacy session keys (without flutter. prefix)',
      );

      // Process both new format (with flutter. prefix) and legacy format
      final allSessionKeys = [...sessionKeys, ...legacyKeys];
      print(
        'NativeSync: Total session keys to process: ${allSessionKeys.length}',
      );

      final sessions = <_SessionEntry>[];
      for (final key in allSessionKeys) {
        // Check if this is a legacy key (without flutter. prefix)
        final isLegacy = !key.startsWith('flutter.');

        // Extract session ID (remove 'flutter.' prefix if present and '_package' suffix)
        final sessionId = key
            .replaceFirst('flutter.', '')
            .replaceAll('_package', '');

        // Use appropriate prefix based on key format
        final prefix = isLegacy ? '' : 'flutter.';

        final packageName = prefs.getString(key);
        final appName = prefs.getString('${prefix}${sessionId}_name');
        final startTimeStr = prefs.getString('${prefix}${sessionId}_start');
        final endTimeStr = prefs.getString('${prefix}${sessionId}_end');
        final durationStr = prefs.getString('${prefix}${sessionId}_duration');

        print(
          'NativeSync: Processing session $sessionId - package: $packageName, app: $appName',
        );

        if (packageName != null && appName != null && startTimeStr != null) {
          if (endTimeStr == null) {
            continue;
          }
          try {
            final startTime = int.parse(startTimeStr);
            final endTime = int.parse(endTimeStr);
            final duration = durationStr != null
                ? int.parse(durationStr)
                : (endTime - startTime);

            sessions.add(
              _SessionEntry(
                key: key,
                prefix: prefix,
                sessionId: sessionId,
                packageName: packageName,
                appName: appName,
                startTime: startTime,
                endTime: endTime,
                duration: duration,
              ),
            );
          } catch (e) {
            print('Error parsing session data: $e');
            await prefs.remove(key);
            await prefs.remove('${prefix}${sessionId}_name');
            await prefs.remove('${prefix}${sessionId}_start');
            await prefs.remove('${prefix}${sessionId}_end');
            await prefs.remove('${prefix}${sessionId}_duration');
          }
        }
      }

      sessions.sort((a, b) => a.endTime.compareTo(b.endTime));
      for (final entry in sessions) {
        final session = UsageSession(
          packageName: entry.packageName,
          appName: entry.appName,
          startTime: DateTime.fromMillisecondsSinceEpoch(entry.startTime),
          endTime: DateTime.fromMillisecondsSinceEpoch(entry.endTime),
          durationMs: entry.duration,
        );
        await _database.insertUsageSession(session);

        await prefs.remove(entry.key);
        await prefs.remove('${entry.prefix}${entry.sessionId}_name');
        await prefs.remove('${entry.prefix}${entry.sessionId}_start');
        await prefs.remove('${entry.prefix}${entry.sessionId}_end');
        await prefs.remove('${entry.prefix}${entry.sessionId}_duration');
      }
    } catch (e) {
      print('Error syncing usage sessions: $e');
    }
  }

  Future<void> syncHeartbeats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      // Check for both int and string formats for compatibility
      final lastHeartbeatInt = prefs.getInt('last_heartbeat');
      final lastHeartbeatStr = prefs.getString('last_heartbeat');

      int? lastHeartbeat;
      if (lastHeartbeatInt != null) {
        lastHeartbeat = lastHeartbeatInt;
      } else if (lastHeartbeatStr != null) {
        lastHeartbeat = int.tryParse(lastHeartbeatStr);
      }

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
      await prefs.reload();
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith('interruption_'))
          .toList();

      for (final key in keys) {
        if (key.endsWith('_from')) {
          final interruptionId = key.replaceAll('_from', '');
          final fromTimeStr = prefs.getString(key);
          final toTimeStr = prefs.getString('${interruptionId}_to');
          final durationStr = prefs.getString('${interruptionId}_duration');

          if (fromTimeStr != null && toTimeStr != null && durationStr != null) {
            try {
              final fromTime = int.parse(fromTimeStr);
              final toTime = int.parse(toTimeStr);
              final duration = int.parse(durationStr);

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
            } catch (e) {
              print('Error parsing interruption data: $e');
              // Remove invalid entry
              await prefs.remove(key);
              await prefs.remove('${interruptionId}_to');
              await prefs.remove('${interruptionId}_duration');
            }
          }
        }
      }
    } catch (e) {
      print('Error syncing interruptions: $e');
    }
  }
}

class _StartEntry {
  final String key;
  final String prefix;
  final String eventId;
  final String packageName;
  final String appName;
  final int timeMs;

  _StartEntry({
    required this.key,
    required this.prefix,
    required this.eventId,
    required this.packageName,
    required this.appName,
    required this.timeMs,
  });
}

class _SessionEntry {
  final String key;
  final String prefix;
  final String sessionId;
  final String packageName;
  final String appName;
  final int startTime;
  final int endTime;
  final int duration;

  _SessionEntry({
    required this.key,
    required this.prefix,
    required this.sessionId,
    required this.packageName,
    required this.appName,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });
}
