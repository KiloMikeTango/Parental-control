import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/onboarding_screen.dart';
import 'screens/home_screen.dart';
import 'providers/app_state_provider.dart';

void main() {
  runApp(const ProviderScope(child: MainApp()));
}

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState  extends ConsumerState<MainApp> {
  @override
  void initState() {
    super.initState();
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    final storage = ref.read(secureStorageProvider);
    final tracking = ref.read(trackingServiceProvider);
    final setupComplete = await storage.isSetupComplete();

    if (setupComplete) {
      await tracking.startTracking();
    }

    Future.delayed(const Duration(seconds: 5), () async {
      try {
        final syncService = ref.read(syncServiceProvider);
        await syncService.syncAll();
      } catch (e) {
        print('Error in initial sync: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final setupComplete = ref.watch(setupCompleteProvider);

    return MaterialApp(
      title: 'Parental Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: setupComplete.when(
        data: (complete) =>
            complete ? const HomeScreen() : const OnboardingScreen(),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, __) => const OnboardingScreen(),
      ),
      routes: {
        '/home': (context) => const HomeScreen(),
        '/onboarding': (context) => const OnboardingScreen(),
      },
    );
  }
}
