import '../services/database_service.dart';
import '../services/telegram_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  final DatabaseService _database = DatabaseService();
  final TelegramService _telegram = TelegramService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> syncAll() async {
    // Check connectivity
    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return false;
    }

    bool allSuccess = true;

    // Sync usage sessions
    final unsentSessions = await _database.getUnsentUsageSessions();
    for (final session in unsentSessions) {
      final success = await _telegram.sendUsageReport(session);
      if (success && session.id != null) {
        await _database.markUsageSessionSent(session.id!);
      } else {
        allSuccess = false;
      }
    }

    // Sync interruptions
    final unsentInterruptions = await _database.getUnsentInterruptions();
    for (final interruption in unsentInterruptions) {
      final success = await _telegram.sendInterruptionReport(interruption);
      if (success && interruption.id != null) {
        await _database.markInterruptionSent(interruption.id!);
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
