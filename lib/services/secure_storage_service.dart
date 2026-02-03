import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // PIN Management
  Future<void> setPin(String pin) async {
    final hashedPin = _hashPin(pin);
    await _storage.write(key: 'parent_pin_hash', value: hashedPin);
  }

  Future<bool> verifyPin(String pin) async {
    final storedHash = await _storage.read(key: 'parent_pin_hash');
    if (storedHash == null) return false;
    final inputHash = _hashPin(pin);
    return storedHash == inputHash;
  }

  Future<bool> hasPin() async {
    final pin = await _storage.read(key: 'parent_pin_hash');
    return pin != null;
  }

  String _hashPin(String pin) {
    final bytes = utf8.encode(pin);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // Telegram Configuration
  Future<void> setTelegramToken(String token) async {
    await _storage.write(key: 'telegram_token', value: token);
  }

  Future<String?> getTelegramToken() async {
    return await _storage.read(key: 'telegram_token');
  }

  Future<void> setTelegramChatId(String chatId) async {
    await _storage.write(key: 'telegram_chat_id', value: chatId);
  }

  Future<String?> getTelegramChatId() async {
    return await _storage.read(key: 'telegram_chat_id');
  }

  Future<bool> hasTelegramConfig() async {
    final token = await getTelegramToken();
    final chatId = await getTelegramChatId();
    return token != null && chatId != null;
  }

  // Setup completion
  Future<void> setSetupComplete(bool complete) async {
    await _storage.write(key: 'setup_complete', value: complete.toString());
  }

  Future<bool> isSetupComplete() async {
    final value = await _storage.read(key: 'setup_complete');
    return value == 'true';
  }

  // Clear all data (for reset)
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
