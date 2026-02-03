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
  Timer? _pendingSyncTimer;
  int _sessionsInsertedCount = 0;

  // Start polling for usage sessions from native side
  void startPolling() {
    print('NativeSync: Starting polling service');
    // Do immediate sync first
    syncUsageSessions();
    syncHeartbeats();
    syncInterruptions();

    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      print('NativeSync: Periodic sync triggered');
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
    _pendingSyncTimer?.cancel();
    _pendingSyncTimer = null;
  }

  Future<void> syncUsageSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
          try {
            final startTime = int.parse(startTimeStr);
            final endTime = endTimeStr != null ? int.parse(endTimeStr) : null;
            final duration = durationStr != null
                ? int.parse(durationStr)
                : null;

            final session = UsageSession(
              packageName: packageName,
              appName: appName,
              startTime: DateTime.fromMillisecondsSinceEpoch(startTime),
              endTime: endTime != null
                  ? DateTime.fromMillisecondsSinceEpoch(endTime)
                  : null,
              durationMs: duration,
            );

            // Insert into database
            final dbSessionId = await _database.insertUsageSession(session);
            _sessionsInsertedCount++;
            print(
              'NativeSync: Synced session: $appName ($packageName) - ${duration}ms, DB ID: $dbSessionId (Total inserted this cycle: $_sessionsInsertedCount)',
            );

            // Remove from SharedPreferences AFTER inserting to DB
            await prefs.remove(key);
            await prefs.remove('${prefix}${sessionId}_name');
            await prefs.remove('${prefix}${sessionId}_start');
            if (endTimeStr != null)
              await prefs.remove('${prefix}${sessionId}_end');
            if (durationStr != null)
              await prefs.remove('${prefix}${sessionId}_duration');

            // Trigger sync after inserting
            // Use debounce: wait 2 seconds for more sessions, then sync
            _pendingSyncTimer?.cancel();
            _pendingSyncTimer = Timer(const Duration(seconds: 2), () async {
              try {
                final count = _sessionsInsertedCount;
                print(
                  'NativeSync: Triggering Telegram sync after batch insert ($count sessions)',
                );
                final syncService = SyncService();
                final success = await syncService.syncAll();
                print('NativeSync: Sync result: $success');
                _sessionsInsertedCount = 0; // Reset counter after sync
              } catch (e, stackTrace) {
                print(
                  'NativeSync: Error triggering sync after session insert: $e',
                );
                print('NativeSync: Stack trace: $stackTrace');
              }
            });

            // Also trigger a backup sync after 5 seconds to ensure nothing is missed
            Future.delayed(const Duration(seconds: 5), () async {
              if (_sessionsInsertedCount > 0) {
                print(
                  'NativeSync: Backup sync triggered ($_sessionsInsertedCount sessions still pending)',
                );
                try {
                  final syncService = SyncService();
                  await syncService.syncAll();
                  _sessionsInsertedCount = 0;
                } catch (e) {
                  print('NativeSync: Error in backup sync: $e');
                }
              }
            });
          } catch (e) {
            print('Error parsing session data: $e');
            // Remove invalid entry
            await prefs.remove(key);
            await prefs.remove('${prefix}${sessionId}_name');
            await prefs.remove('${prefix}${sessionId}_start');
            await prefs.remove('${prefix}${sessionId}_end');
            await prefs.remove('${prefix}${sessionId}_duration');
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
