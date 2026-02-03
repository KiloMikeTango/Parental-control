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

    bool allSuccess = true;

    // Sync usage sessions
    final unsentSessions = await _database.getUnsentUsageSessions();
    if (unsentSessions.isNotEmpty) {
      for (final session in unsentSessions) {
        try {
          final success = await _telegram.sendUsageReport(session);
          if (success && session.id != null) {
            await _database.deleteUsageSession(session.id!);
          } else {
            allSuccess = false;
          }
        } catch (e, stackTrace) {
          allSuccess = false;
        }
      }
    }

    // Sync interruptions
    final unsentInterruptions = await _database.getUnsentInterruptions();
    for (final interruption in unsentInterruptions) {
      final success = await _telegram.sendInterruptionReport(interruption);
      if (success && interruption.id != null) {
        await _database.deleteInterruption(interruption.id!);
      } else {
        allSuccess = false;
      }
    }

    return allSuccess;
  }

  Future<void> syncPeriodically() async {
    // This will be called by WorkManager periodically
    await syncAll();
  }
}
