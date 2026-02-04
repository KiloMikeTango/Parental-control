import '../services/database_service.dart';
import '../services/telegram_service.dart';

class SyncService {
  final DatabaseService _database = DatabaseService();
  final TelegramService _telegram = TelegramService();

  Future<bool> syncAll() async {
    final availability = await _telegram.checkAvailability();
    if (availability != TelegramAvailability.ok) {
      return false;
    }

    final queue = <_QueuedReport>[];

    final usageStarts = await _database.getUnsentUsageStarts();
    for (final session in usageStarts) {
      queue.add(
        _QueuedReport(
          timestamp: session.startTime,
          send: () async {
            final success = await _telegram.sendCurrentAppReport(
              appName: session.appName,
              packageName: session.packageName,
              startTime: session.startTime,
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
      queue.add(
        _QueuedReport(
          timestamp: endTime,
          send: () async {
            final success = await _telegram.sendUsageReport(session);
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
      queue.add(
        _QueuedReport(
          timestamp: interruption.toTime,
          send: () async {
            final success = await _telegram.sendInterruptionReport(
              interruption,
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

    for (final item in queue) {
      final ok = await item.send();
      if (!ok) {
        return false;
      }
    }

    return true;
  }

  Future<void> syncPeriodically() async {
    // This will be called by WorkManager periodically
    await syncAll();
  }
}

class _QueuedReport {
  final DateTime timestamp;
  final Future<bool> Function() send;

  _QueuedReport({required this.timestamp, required this.send});
}
