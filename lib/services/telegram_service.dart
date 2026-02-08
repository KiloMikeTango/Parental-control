import 'package:dio/dio.dart';
import 'dart:io';
import '../models/usage_session.dart';
import '../models/interruption.dart';
import 'secure_storage_service.dart';
import 'package:intl/intl.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum TelegramAvailability { ok, missingConfig, noNetwork, unreachable }

class TelegramService {
  final Dio _dio = Dio();
  final SecureStorageService _secureStorage = SecureStorageService();
  final Connectivity _connectivity = Connectivity();

  Future<bool> sendUsageReport(UsageSession session, {String? label}) async {
    try {
      final config = await _getConfig();
      if (config == null) {
        return false;
      }

      final durationMs = _resolveDurationMs(session);
      final duration = _formatDuration(durationMs);
      final startTime = DateFormat(
        'yyyy-MM-dd hh:mm a',
      ).format(session.startTime);
      final endTime = session.endTime != null
          ? DateFormat('yyyy-MM-dd hh:mm a').format(session.endTime!)
          : DateFormat('yyyy-MM-dd hh:mm a').format(session.startTime);

      final message = _applyLabel(
        '''
📱 App အသုံးပြုမှု

အသုံးပြုခဲ့သည့် App: ${session.appName}
Package: ${session.packageName}

$startTime မှ $endTime အထိအသုံးပြုခဲ့ပါသည်။

စုစုပေါင်းအသုံးပြုချိန်: $duration
''',
        label,
      );

      final url = 'https://api.telegram.org/bot${config.token}/sendMessage';
      final response = await _dio.post(
        url,
        data: {'chat_id': config.chatId, 'text': message},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<TelegramAvailability> checkAvailability() async {
    final config = await _getConfig();
    if (config == null) {
      return TelegramAvailability.missingConfig;
    }

    final connectivityResult = await _connectivity.checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.none)) {
      return TelegramAvailability.noNetwork;
    }

    final reachable = await canReachTelegram();
    if (!reachable) {
      return TelegramAvailability.unreachable;
    }

    return TelegramAvailability.ok;
  }

  Future<bool> canReachTelegram() async {
    try {
      final socket = await Socket.connect(
        'api.telegram.org',
        443,
        timeout: const Duration(seconds: 3),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> sendCurrentAppReport({
    required String appName,
    required String packageName,
    required DateTime startTime,
    String? label,
  }) async {
    try {
      final config = await _getConfig();
      if (config == null) {
        return false;
      }

      final displayName = appName.isNotEmpty ? appName : packageName;
      final timestamp = DateFormat('yyyy-MM-dd hh:mm a').format(startTime);
      final message = _applyLabel(
        'အသုံးပြုနေသည့် App: $displayName\nစတင်အသုံးပြုချိန်: $timestamp',
        label,
      );

      final url = 'https://api.telegram.org/bot${config.token}/sendMessage';

      final response = await _dio.post(
        url,
        data: {'chat_id': config.chatId, 'text': message},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<bool> sendInterruptionReport(Interruption interruption, {String? label}) async {
    try {
      final config = await _getConfig();
      if (config == null) {
        return false;
      }

      final duration = _formatDuration(interruption.durationMs);
      final fromTime = DateFormat(
        'yyyy-MM-dd hh:mm a',
      ).format(interruption.fromTime);
      final toTime = DateFormat(
        'yyyy-MM-dd hh:mm a',
      ).format(interruption.toTime);

      final message = _applyLabel(
        '''
⚠️ Monitoring Interruption

From: $fromTime
To: $toTime
Duration: $duration
''',
        label,
      );

      final url = 'https://api.telegram.org/bot${config.token}/sendMessage';

      await _dio.post(
        url,
        data: {'chat_id': config.chatId, 'text': message, 'parse_mode': 'HTML'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> testConnection() async {
    try {
      final config = await _getConfig();
      if (config == null) {
        return false;
      }

      final url = 'https://api.telegram.org/bot${config.token}/getMe';
      final response = await _dio.get(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<_TelegramConfig?> _getConfig() async {
    final token = await _secureStorage.getTelegramToken();
    final chatId = await _secureStorage.getTelegramChatId();
    if (token == null || chatId == null) {
      return null;
    }
    return _TelegramConfig(token: token, chatId: chatId);
  }

  int _resolveDurationMs(UsageSession session) {
    if (session.durationMs != null) {
      return session.durationMs!;
    }
    if (session.endTime != null) {
      final diff =
          session.endTime!.millisecondsSinceEpoch -
          session.startTime.millisecondsSinceEpoch;
      return diff >= 0 ? diff : 0;
    }
    return 0;
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  String _applyLabel(String message, String? label) {
    if (label == null || label.isEmpty) {
      return message;
    }
    return '$label\n\n$message';
  }
}

class _TelegramConfig {
  final String token;
  final String chatId;

  _TelegramConfig({required this.token, required this.chatId});
}
