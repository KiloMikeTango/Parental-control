import '../services/database_service.dart';
import '../services/telegram_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  final DatabaseService _database = DatabaseService();
  final TelegramService _telegram = TelegramService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> syncAll() async {
    print('SyncService: Starting sync...');

    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      print('SyncService: No internet connection');
      return false;
    }

    final canReachTelegram = await _telegram.canReachTelegram();
    if (!canReachTelegram) {
      print('SyncService: Network reachable but Telegram is not');
      return false;
    }

    print('SyncService: Internet connection available');

    bool allSuccess = true;

    // Sync usage sessions
    final unsentSessions = await _database.getUnsentUsageSessions();
    print('SyncService: Found ${unsentSessions.length} unsent sessions');

    if (unsentSessions.isEmpty) {
      print('SyncService: No unsent sessions to sync');
    } else {
      print('SyncService: Processing ${unsentSessions.length} sessions...');
      for (final session in unsentSessions) {
        print(
          'SyncService: Sending session ID ${session.id} for ${session.appName} (${session.packageName})',
        );
        try {
          final success = await _telegram.sendUsageReport(session);
          print('SyncService: Send result for session ${session.id}: $success');
          if (success && session.id != null) {
            await _database.deleteUsageSession(session.id!);
            print('SyncService: Session ${session.id} deleted after send');
          } else {
            print(
              'SyncService: Failed to send session ${session.id} - success: $success, id: ${session.id}',
            );
            allSuccess = false;
          }
        } catch (e, stackTrace) {
          print('SyncService: Exception sending session ${session.id}: $e');
          print('SyncService: Stack trace: $stackTrace');
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
