import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_state_provider.dart';
import 'telegram_setup_screen.dart';
import 'pin_setup_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with WidgetsBindingObserver {
  int _currentStep = 0;
  bool _usageAccessGranted = false;
  bool _batteryOptimizationGranted = false;
  bool _deviceAdminEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check permissions when app resumes (user returns from settings)
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final tracking = ref.read(trackingServiceProvider);
    final usageAccess = await tracking.hasUsageAccess();
    final deviceAdmin = await tracking.isDeviceAdminEnabled();
    final batteryOptimization = await tracking.isBatteryOptimizationExempt();
    
    if (mounted) {
      setState(() {
        _usageAccessGranted = usageAccess;
        _deviceAdminEnabled = deviceAdmin;
        _batteryOptimizationGranted = batteryOptimization;
      });
    }
  }

  Future<void> _requestUsageAccess() async {
    final tracking = ref.read(trackingServiceProvider);
    await tracking.requestUsageAccess();
    // Wait a bit for the user to navigate to settings
    await Future.delayed(const Duration(milliseconds: 500));
    // Re-check permission when user returns
    await _checkPermissions();
  }

  Future<void> _requestBatteryOptimization() async {
    final tracking = ref.read(trackingServiceProvider);
    await tracking.requestBatteryOptimizationExemption();
    // Wait a bit for the user to navigate to settings
    await Future.delayed(const Duration(milliseconds: 500));
    // Re-check permission when user returns
    await _checkPermissions();
  }

  Future<void> _enableDeviceAdmin() async {
    final tracking = ref.read(trackingServiceProvider);
    await tracking.enableDeviceAdmin();
    // Wait a bit for the user to navigate to settings
    await Future.delayed(const Duration(milliseconds: 500));
    // Re-check permission when user returns
    await _checkPermissions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup - Parental Control'),
        automaticallyImplyLeading: false,
      ),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 4) {
            setState(() {
              _currentStep++;
            });
          } else {
            _completeSetup();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() {
              _currentStep--;
            });
          }
        },
        steps: [
          Step(
            title: const Text('Welcome'),
            content: const Padding(
              padding: EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PC - Android Parental Usage Reporter',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'This app tracks app usage and sends reports to parents via Telegram.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Features:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('• Tracks app launches and usage duration'),
                  Text('• Logs timestamps accurately'),
                  Text('• Works offline and syncs later'),
                  Text('• Sends reports via Telegram bot'),
                  Text('• PIN-protected settings'),
                  Text('• Device Admin protection'),
                ],
              ),
            ),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Usage Access Permission'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This app needs Usage Access permission to track app usage.',
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _usageAccessGranted ? null : _requestUsageAccess,
                  child: Text(_usageAccessGranted
                      ? '✓ Permission Granted'
                      : 'Grant Usage Access'),
                ),
                if (_usageAccessGranted)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Permission granted!',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
              ],
            ),
            isActive: _currentStep >= 1,
            state: _usageAccessGranted
                ? StepState.complete
                : (_currentStep > 1 ? StepState.complete : StepState.indexed),
          ),
          Step(
            title: const Text('Battery Optimization'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Please disable battery optimization for this app to ensure continuous monitoring.',
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _batteryOptimizationGranted
                      ? null
                      : _requestBatteryOptimization,
                  child: Text(_batteryOptimizationGranted
                      ? '✓ Exemption Granted'
                      : 'Request Battery Optimization Exemption'),
                ),
                if (_batteryOptimizationGranted)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Exemption granted!',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
              ],
            ),
            isActive: _currentStep >= 2,
            state: _batteryOptimizationGranted
                ? StepState.complete
                : (_currentStep > 2 ? StepState.complete : StepState.indexed),
          ),
          Step(
            title: const Text('Device Admin'),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enable Device Admin to protect the app from being uninstalled easily.',
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _deviceAdminEnabled ? null : _enableDeviceAdmin,
                  child: Text(_deviceAdminEnabled
                      ? '✓ Device Admin Enabled'
                      : 'Enable Device Admin'),
                ),
                if (_deviceAdminEnabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Device Admin enabled!',
                      style: TextStyle(color: Colors.green),
                    ),
                  ),
              ],
            ),
            isActive: _currentStep >= 3,
            state: _deviceAdminEnabled
                ? StepState.complete
                : (_currentStep > 3 ? StepState.complete : StepState.indexed),
          ),
          Step(
            title: const Text('Telegram Configuration'),
            content: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure your Telegram bot token and chat ID to receive usage reports.',
                ),
                SizedBox(height: 16),
                Text(
                  'You will be taken to the Telegram setup screen.',
                ),
              ],
            ),
            isActive: _currentStep >= 4,
            state: _currentStep > 4 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Parent PIN'),
            content: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set up a PIN to protect app settings.',
                ),
                SizedBox(height: 16),
                Text(
                  'You will be taken to the PIN setup screen.',
                ),
              ],
            ),
            isActive: _currentStep >= 5,
            state: _currentStep > 5 ? StepState.complete : StepState.indexed,
          ),
        ],
      ),
    );
  }

  Future<void> _completeSetup() async {
    // Navigate to Telegram setup
    final telegramResult = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TelegramSetupScreen()),
    );

    if (telegramResult == true) {
      // Navigate to PIN setup
      final pinResult = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const PinSetupScreen()),
      );

      if (pinResult == true) {
        // Mark setup as complete
        final storage = ref.read(secureStorageProvider);
        await storage.setSetupComplete(true);

        // Start tracking
        final tracking = ref.read(trackingServiceProvider);
        await tracking.startTracking();

        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
      }
    }
  }
}
