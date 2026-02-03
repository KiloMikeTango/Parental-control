import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state_provider.dart';
import '../services/telegram_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TelegramSetupScreen extends ConsumerStatefulWidget {
  const TelegramSetupScreen({super.key});

  @override
  ConsumerState<TelegramSetupScreen> createState() =>
      _TelegramSetupScreenState();
}

class _TelegramSetupScreenState extends ConsumerState<TelegramSetupScreen> {
  final _tokenController = TextEditingController();
  final _chatIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isTesting = false;
  bool _testSuccess = false;

  @override
  void initState() {
    super.initState();
    _loadExistingValues();
  }

  Future<void> _loadExistingValues() async {
    final storage = ref.read(secureStorageProvider);
    final token = await storage.getTelegramToken();
    final chatId = await storage.getTelegramChatId();

    if (mounted) {
      setState(() {
        if (token != null) _tokenController.text = token;
        if (chatId != null) _chatIdController.text = chatId;
        // If values exist, mark as tested
        if (token != null && chatId != null) {
          _testSuccess = true;
        }
      });
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isTesting = true;
      _testSuccess = false;
    });

    final storage = ref.read(secureStorageProvider);
    final token = _tokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    print(
      'TelegramSetup: Storing token: ${token.isNotEmpty}, chatId: ${chatId.isNotEmpty}',
    );

    await storage.setTelegramToken(token);
    await storage.setTelegramChatId(chatId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('telegram_token', token);
    await prefs.setString('telegram_chat_id', chatId);

    // Verify storage
    final storedToken = await storage.getTelegramToken();
    final storedChatId = await storage.getTelegramChatId();
    print(
      'TelegramSetup: Stored token: ${storedToken != null}, stored chatId: ${storedChatId != null}',
    );

    final telegram = TelegramService();
    final success = await telegram.testConnection();

    setState(() {
      _isTesting = false;
      _testSuccess = success;
    });

    if (success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Connection successful!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Connection failed. Please check your token and chat ID.',
          ),
        ),
      );
    }
  }

  void _saveAndContinue() {
    if (!_formKey.currentState!.validate()) return;
    if (!_testSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please test the connection first.')),
      );
      return;
    }

    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Telegram Configuration')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            const Text(
              'Configure Telegram Bot',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'To receive usage reports, you need to create a Telegram bot and get your chat ID.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Bot Token',
                hintText: 'Enter your Telegram bot token',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter bot token';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _chatIdController,
              decoration: const InputDecoration(
                labelText: 'Chat ID',
                hintText: 'Enter your Telegram chat ID',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter chat ID';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isTesting ? null : _testConnection,
              child: _isTesting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Test Connection'),
            ),
            if (_testSuccess)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '✓ Connection successful!',
                  style: TextStyle(color: Colors.green),
                ),
              ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saveAndContinue,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save and Continue'),
            ),
            const SizedBox(height: 16),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to get Bot Token and Chat ID:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('1. Open Telegram and search for @BotFather'),
                    Text('2. Send /newbot and follow instructions'),
                    Text('3. Copy the bot token'),
                    Text('4. Start a chat with your bot'),
                    Text('5. Send a message to your bot'),
                    Text(
                      '6. Visit: https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates',
                    ),
                    Text('7. Find "chat":{"id":...} in the response'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
