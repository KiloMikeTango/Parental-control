import '../services/database_service.dart';
import '../services/telegram_service.dart';

class SyncService {
  final DatabaseService _database = DatabaseService();
  final TelegramService _telegram = TelegramService();
  static const Duration _sendDelay = Duration(seconds: 3);
  static const Duration _delayLabelThreshold = Duration(seconds: 30);
  static const String _delayedLabel = 'Delayed/Offline';

  Future<bool> syncAll() async {
    final availability = await _telegram.checkAvailability();
    if (availability != TelegramAvailability.ok) {
      return false;
    }

    final queue = <_QueuedReport>[];

    final now = DateTime.now();
    final usageStarts = await _database.getUnsentUsageStarts();
    for (final session in usageStarts) {
      final label = _resolveDelayLabel(now, session.startTime);
      queue.add(
        _QueuedReport(
          timestamp: session.startTime,
          send: () async {
            final success = await _telegram.sendCurrentAppReport(
              appName: session.appName,
              packageName: session.packageName,
              startTime: session.startTime,
              label: label,
            );
            if (success && session.id != null) {
              await _database.deleteUsageSession(session.id!);
              return true;
            }
            return false;
          },
        ),
      );
    }

    final unsentSessions = await _database.getUnsentUsageSessions();
    for (final session in unsentSessions) {
      final endTime = session.endTime ?? session.startTime;
      final label = _resolveDelayLabel(now, endTime);
      queue.add(
        _QueuedReport(
          timestamp: endTime,
          send: () async {
            final success = await _telegram.sendUsageReport(
              session,
              label: label,
            );
            if (success && session.id != null) {
              await _database.deleteUsageSession(session.id!);
              return true;
            }
            return false;
          },
        ),
      );
    }

    final unsentInterruptions = await _database.getUnsentInterruptions();
    for (final interruption in unsentInterruptions) {
      final label = _resolveDelayLabel(now, interruption.toTime);
      queue.add(
        _QueuedReport(
          timestamp: interruption.toTime,
          send: () async {
            final success = await _telegram.sendInterruptionReport(
              interruption,
              label: label,
            );
            if (success && interruption.id != null) {
              await _database.deleteInterruption(interruption.id!);
              return true;
            }
            return false;
          },
        ),
      );
    }

    if (queue.isEmpty) {
      return true;
    }

    queue.sort((a, b) => a.timestamp.compareTo(b.timestamp));

    for (var i = 0; i < queue.length; i++) {
      final ok = await queue[i].send();
      if (!ok) {
        return false;
      }
      if (i < queue.length - 1) {
        await Future.delayed(_sendDelay);
      }
    }

    return true;
  }

  Future<void> syncPeriodically() async {
    // This will be called by WorkManager periodically
    await syncAll();
  }

  String? _resolveDelayLabel(DateTime now, DateTime eventTime) {
    final diff = now.difference(eventTime);
    if (diff >= _delayLabelThreshold) {
      return _delayedLabel;
    }
    return null;
  }
}

class _QueuedReport {
  final DateTime timestamp;
  final Future<bool> Function() send;

  _QueuedReport({required this.timestamp, required this.send});
}
