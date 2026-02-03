import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/app_state_provider.dart';
import '../models/usage_session.dart';
import 'settings_screen.dart';
import 'pin_verification_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final trackingStatus = ref.watch(trackingStatusProvider);
    final database = ref.read(databaseServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Parental Control'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () async {
              final hasPin = await ref.read(hasPinProvider.future);
              if (hasPin) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        const PinVerificationScreen(child: SettingsScreen()),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  trackingStatus.when(
                    data: (isRunning) => Row(
                      children: [
                        Icon(
                          isRunning ? Icons.check_circle : Icons.error,
                          color: isRunning ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isRunning ? 'Tracking Active' : 'Tracking Inactive',
                          style: TextStyle(
                            color: isRunning ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    loading: () => const CircularProgressIndicator(),
                    error: (_, __) => const Text('Error loading status'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<UsageSession>>(
              future: database.getAllUsageSessions(limit: 50),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final sessions = snapshot.data ?? [];

                if (sessions.isEmpty) {
                  return const Center(child: Text('No usage data yet'));
                }

                return ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final session = sessions[index];
                    final duration = session.durationMs != null
                        ? _formatDuration(session.durationMs!)
                        : 'Ongoing';
                    final startTime = DateFormat(
                      'MMM dd, HH:mm',
                    ).format(session.startTime);

                    return ListTile(
                      leading: const Icon(Icons.phone_android),
                      title: Text(session.appName),
                      subtitle: Text('$startTime • $duration'),
                      trailing: session.sent
                          ? const Icon(Icons.check, color: Colors.green)
                          : const Icon(Icons.sync, color: Colors.orange),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
}
