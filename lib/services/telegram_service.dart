import 'package:dio/dio.dart';
import 'dart:io';
import '../models/usage_session.dart';
import '../models/interruption.dart';
import 'secure_storage_service.dart';
import 'package:intl/intl.dart';

class TelegramService {
  final Dio _dio = Dio();
  final SecureStorageService _secureStorage = SecureStorageService();

  Future<bool> sendUsageReport(UsageSession session) async {
    try {
      final token = await _secureStorage.getTelegramToken();
      final chatId = await _secureStorage.getTelegramChatId();

      print(
        'TelegramService: Token present: ${token != null}, ChatId present: ${chatId != null}',
      );

      if (token == null || chatId == null) {
        print(
          'TelegramService: Missing token or chatId. Token: $token, ChatId: $chatId',
        );
        return false;
      }

      final duration = _formatDuration(session.durationMs ?? 0);
      final startTime = DateFormat('HH:mm').format(session.startTime);
      final endTime = session.endTime != null
          ? DateFormat('HH:mm').format(session.endTime!)
          : 'N/A';

      final message =
          '''
📱 App Usage

App: ${session.appName}
Package: ${session.packageName}
From: $startTime
To: $endTime
Duration: $duration
''';

      final url = 'https://api.telegram.org/bot$token/sendMessage';

      print('TelegramService: Sending to URL: $url');
      print('TelegramService: Chat ID: $chatId');
      print(
        'TelegramService: Message preview: ${message.substring(0, message.length > 50 ? 50 : message.length)}...',
      );

      final response = await _dio.post(
        url,
        data: {'chat_id': chatId, 'text': message},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      print('TelegramService: Response status: ${response.statusCode}');
      print('TelegramService: Response data: ${response.data}');
      final success = response.statusCode == 200;
      print('TelegramService: Send success: $success');
      return success;
    } catch (e) {
      print('TelegramService: Error sending usage report: $e');
      if (e is DioException) {
        print(
          'TelegramService: DioException - ${e.response?.statusCode}, ${e.response?.data}',
        );
      }
      return false;
    }
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
  }) async {
    try {
      final token = await _secureStorage.getTelegramToken();
      final chatId = await _secureStorage.getTelegramChatId();

      if (token == null || chatId == null) {
        return false;
      }

      final displayName = appName.isNotEmpty ? appName : packageName;
      final message = 'App: $displayName';

      final url = 'https://api.telegram.org/bot$token/sendMessage';

      final response = await _dio.post(
        url,
        data: {'chat_id': chatId, 'text': message},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('TelegramService: Error sending current app report: $e');
      if (e is DioException) {
        print(
          'TelegramService: DioException - ${e.response?.statusCode}, ${e.response?.data}',
        );
      }
      return false;
    }
  }

  Future<bool> sendInterruptionReport(Interruption interruption) async {
    try {
      final token = await _secureStorage.getTelegramToken();
      final chatId = await _secureStorage.getTelegramChatId();

      if (token == null || chatId == null) {
        return false;
      }

      final duration = _formatDuration(interruption.durationMs);
      final fromTime = DateFormat('HH:mm').format(interruption.fromTime);
      final toTime = DateFormat('HH:mm').format(interruption.toTime);

      final message =
          '''
⚠️ Monitoring Interruption

From: $fromTime
To: $toTime
Duration: $duration
''';

      final url = 'https://api.telegram.org/bot$token/sendMessage';

      await _dio.post(
        url,
        data: {'chat_id': chatId, 'text': message, 'parse_mode': 'HTML'},
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return true;
    } catch (e) {
      print('Error sending interruption report: $e');
      return false;
    }
  }

  Future<bool> testConnection() async {
    try {
      final token = await _secureStorage.getTelegramToken();
      final chatId = await _secureStorage.getTelegramChatId();

      print(
        'TelegramService: Test connection - Token: ${token != null ? "present" : "missing"}, ChatId: ${chatId != null ? "present" : "missing"}',
      );

      if (token == null || chatId == null) {
        print('TelegramService: Test failed - missing credentials');
        return false;
      }

      final url = 'https://api.telegram.org/bot$token/getMe';
      print('TelegramService: Testing connection to Telegram API...');

      final response = await _dio.get(
        url,
        options: Options(
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      print('TelegramService: Test response status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('TelegramService: Test connection error: $e');
      if (e is DioException) {
        print(
          'TelegramService: DioException - ${e.response?.statusCode}, ${e.response?.data}',
        );
      }
      return false;
    }
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
}
