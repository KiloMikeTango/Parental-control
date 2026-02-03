import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state_provider.dart';
import 'telegram_setup_screen.dart';
import 'pin_setup_screen.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trackingStatus = ref.watch(trackingStatusProvider);
    final hasPin = ref.watch(hasPinProvider);
    final hasTelegram = ref.watch(hasTelegramConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: const Text('Tracking Status'),
            subtitle: trackingStatus.when(
              data: (isRunning) => Text(isRunning ? 'Active' : 'Inactive'),
              loading: () => const Text('Loading...'),
              error: (_, __) => const Text('Error'),
            ),
            trailing: trackingStatus.when(
              data: (isRunning) => Switch(
                value: isRunning,
                onChanged: (value) async {
                  final tracking = ref.read(trackingServiceProvider);
                  if (value) {
                    await tracking.startTracking();
                  } else {
                    // Require PIN to stop tracking
                    final storage = ref.read(secureStorageProvider);
                    final hasPinValue = await storage.hasPin();
                    if (hasPinValue) {
                      // Show PIN dialog
                      final pin = await _showPinDialog(context);
                      if (pin != null) {
                        final isValid = await storage.verifyPin(pin);
                        if (isValid) {
                          await tracking.stopTracking();
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Invalid PIN')),
                            );
                          }
                        }
                      }
                    } else {
                      await tracking.stopTracking();
                    }
                  }
                  ref.invalidate(trackingStatusProvider);
                },
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.telegram),
            title: const Text('Telegram Configuration'),
            subtitle: hasTelegram.when(
              data: (has) => Text(has ? 'Configured' : 'Not configured'),
              loading: () => const Text('Loading...'),
              error: (_, __) => const Text('Error'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const TelegramSetupScreen(),
                ),
              );
              ref.invalidate(hasTelegramConfigProvider);
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock),
            title: const Text('Parent PIN'),
            subtitle: hasPin.when(
              data: (has) => Text(has ? 'PIN set' : 'No PIN set'),
              loading: () => const Text('Loading...'),
              error: (_, __) => const Text('Error'),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const PinSetupScreen()),
              );
              ref.invalidate(hasPinProvider);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Reset Setup'),
            subtitle: const Text('Start setup from beginning'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Setup'),
                  content: const Text(
                    'This will clear all settings. Continue?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                final storage = ref.read(secureStorageProvider);
                await storage.clearAll();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const OnboardingScreen(),
                    ),
                    (route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<String?> _showPinDialog(BuildContext context) async {
    final pinController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter PIN'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, pinController.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
