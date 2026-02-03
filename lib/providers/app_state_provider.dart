import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/secure_storage_service.dart';
import '../services/tracking_service.dart';
import '../services/database_service.dart';
import '../services/sync_service.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final trackingServiceProvider = Provider<TrackingService>((ref) {
  return TrackingService();
});

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});

final setupCompleteProvider = FutureProvider<bool>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return await storage.isSetupComplete();
});

final trackingStatusProvider = FutureProvider<bool>((ref) async {
  final tracking = ref.read(trackingServiceProvider);
  return await tracking.isTrackingRunning();
});

final hasPinProvider = FutureProvider<bool>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return await storage.hasPin();
});

final hasTelegramConfigProvider = FutureProvider<bool>((ref) async {
  final storage = ref.read(secureStorageProvider);
  return await storage.hasTelegramConfig();
});
