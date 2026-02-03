import 'package:dio/dio.dart';
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

      if (token == null || chatId == null) {
        return false;
      }

      final duration = _formatDuration(session.durationMs ?? 0);
      final startTime = DateFormat('HH:mm').format(session.startTime);
      final endTime = session.endTime != null
          ? DateFormat('HH:mm').format(session.endTime!)
          : 'N/A';

      final message = '''
📱 App Usage

App: ${session.appName}
Package: ${session.packageName}
From: $startTime
To: $endTime
Duration: $duration
''';

      final url = 'https://api.telegram.org/bot$token/sendMessage';
      
      await _dio.post(
        url,
        data: {
          'chat_id': chatId,
          'text': message,
          'parse_mode': 'HTML',
        },
        options: Options(
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      return true;
    } catch (e) {
      print('Error sending usage report: $e');
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

      final message = '''
⚠️ Monitoring Interruption

From: $fromTime
To: $toTime
Duration: $duration
''';

      final url = 'https://api.telegram.org/bot$token/sendMessage';
      
      await _dio.post(
        url,
        data: {
          'chat_id': chatId,
          'text': message,
          'parse_mode': 'HTML',
        },
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

      if (token == null || chatId == null) {
        return false;
      }

      final url = 'https://api.telegram.org/bot$token/getMe';
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
