import 'package:flutter/services.dart';
import '../models/usage_session.dart';
import '../services/native_sync_service.dart';
import 'dart:async';

class TrackingService {
  static const MethodChannel _channel = MethodChannel('com.child.safety.kilowares/tracking');
  final NativeSyncService _nativeSync = NativeSyncService();

  // Start the foreground tracking service
  Future<bool> startTracking() async {
    try {
      // Schedule WorkManager sync first
      await _channel.invokeMethod('scheduleSync');
      
      final result = await _channel.invokeMethod<bool>('startTracking');
      if (result == true) {
        // Start polling for native data
        _nativeSync.startPolling();
      }
      return result ?? false;
    } catch (e) {
      print('Error starting tracking: $e');
      return false;
    }
  }

  // Stop the tracking service
  Future<bool> stopTracking() async {
    try {
      _nativeSync.stopPolling();
      final result = await _channel.invokeMethod<bool>('stopTracking');
      return result ?? false;
    } catch (e) {
      print('Error stopping tracking: $e');
      return false;
    }
  }

  // Check if tracking is running
  Future<bool> isTrackingRunning() async {
    try {
      final result = await _channel.invokeMethod<bool>('isTrackingRunning');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Request usage access permission
  Future<bool> requestUsageAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestUsageAccess');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Check if usage access is granted
  Future<bool> hasUsageAccess() async {
    try {
      final result = await _channel.invokeMethod<bool>('hasUsageAccess');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Request battery optimization exemption
  Future<bool> requestBatteryOptimizationExemption() async {
    try {
      final result = await _channel.invokeMethod<bool>('requestBatteryOptimizationExemption');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Enable Device Admin
  Future<bool> enableDeviceAdmin() async {
    try {
      final result = await _channel.invokeMethod<bool>('enableDeviceAdmin');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Check if Device Admin is enabled
  Future<bool> isDeviceAdminEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isDeviceAdminEnabled');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  // Listen to app usage events from native side
  StreamSubscription? _usageStreamSubscription;

  void startListeningToUsageEvents(Function(UsageSession) onSessionComplete) {
    _usageStreamSubscription = EventChannel('com.child.safety.kilowares/usageEvents')
        .receiveBroadcastStream()
        .listen((dynamic event) {
      if (event is Map) {
        final session = UsageSession(
          packageName: event['packageName'] as String,
          appName: event['appName'] as String,
          startTime: DateTime.parse(event['startTime'] as String),
          endTime: event['endTime'] != null
              ? DateTime.parse(event['endTime'] as String)
              : null,
          durationMs: event['durationMs'] as int?,
        );
        onSessionComplete(session);
      }
    });
  }

  void stopListeningToUsageEvents() {
    _usageStreamSubscription?.cancel();
    _usageStreamSubscription = null;
  }
}
