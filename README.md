# PC - Android Parental Usage Reporter

A comprehensive Android-only Flutter app that tracks app usage and sends reports to parents via Telegram.

## Features

-  **App Usage Tracking**: Tracks foreground app usage using Android UsageStatsManager
-  **Session Calculation**: Computes open/close sessions with accurate timestamps
-  **Local Persistence**: All logs stored in SQLite database
-  **Foreground Service**: Runs continuously via foreground service
-  **Auto-Restart**: Restarts automatically after device reboot
-  **Watchdog**: WorkManager monitors and restarts service if killed
-  **Heartbeat Logging**: Logs heartbeat events to detect monitoring gaps
-  **Interruption Detection**: Detects and reports monitoring gaps
-  **Telegram Integration**: Sends usage and interruption reports via Telegram bot
-  **Offline Queue**: Queues data when offline and syncs when online
-  **State Management**: Uses Riverpod for clean state management
-  **Secure Storage**: Uses flutter_secure_storage and Android Keystore
-  **PIN Protection**: Settings locked behind parent PIN
-  **Device Admin**: Discourages uninstall via Device Admin
-  **Battery Optimization**: Requests battery optimization exemption
-  **Persistent Notification**: Shows ongoing notification
-  **Play Policy Compliant**: Designed to comply with Google Play policies

## Setup Instructions

### 1. Prerequisites

- Flutter SDK (3.10.1 or higher)
- Android Studio
- Android device/emulator with API 26+ (Android 8.0+)
- Telegram bot token and chat ID

### 2. Getting Telegram Bot Token and Chat ID

1. Open Telegram and search for `@BotFather`
2. Send `/newbot` and follow the instructions
3. Copy the bot token provided
4. Start a chat with your bot
5. Send a message to your bot
6. Visit: `https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates`
7. Find `"chat":{"id":...}` in the response - this is your chat ID

### 3. Installation

```bash
# Clone the repository
cd parental_control

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### 4. First Run Setup

The app will guide you through:

1. **Welcome Screen**: Read the app description
2. **Usage Access Permission**: Grant usage access permission
3. **Battery Optimization**: Disable battery optimization for the app
4. **Device Admin**: Enable device admin protection
5. **Telegram Configuration**: Enter bot token and chat ID
6. **Parent PIN**: Set up a PIN to protect settings

After setup, the tracking service will start automatically.

## Project Structure

```
lib/
├── models/              # Data models
│   ├── usage_session.dart
│   ├── heartbeat_log.dart
│   └── interruption.dart
├── services/            # Business logic
│   ├── database_service.dart
│   ├── secure_storage_service.dart
│   ├── telegram_service.dart
│   ├── sync_service.dart
│   ├── tracking_service.dart
│   └── native_sync_service.dart
├── providers/           # Riverpod providers
│   └── app_state_provider.dart
├── screens/             # UI screens
│   ├── onboarding_screen.dart
│   ├── home_screen.dart
│   ├── settings_screen.dart
│   ├── telegram_setup_screen.dart
│   ├── pin_setup_screen.dart
│   └── pin_verification_screen.dart
└── main.dart            # App entry point

android/
└── app/
    └── src/
        └── main/
            ├── kotlin/  # Native Android code
            │   ├── MainActivity.kt
            │   ├── TrackingService.kt
            │   ├── DeviceAdminReceiver.kt
            │   ├── BootReceiver.kt
            │   └── SyncWorker.kt
            └── res/
                └── xml/
                    └── device_admin.xml
```

## Database Schema

### usage_sessions
- `id`: Primary key
- `package_name`: App package name
- `app_name`: App display name
- `start_time`: Session start timestamp
- `end_time`: Session end timestamp
- `duration_ms`: Session duration in milliseconds
- `sent`: Whether report has been sent (0/1)

### heartbeat_logs
- `id`: Primary key
- `timestamp`: Heartbeat timestamp

### interruptions
- `id`: Primary key
- `from_time`: Interruption start time
- `to_time`: Interruption end time
- `duration_ms`: Interruption duration
- `sent`: Whether report has been sent (0/1)

## Telegram Reports

The app sends two types of reports:

### App Usage Report
```
📱 App Usage

App: YouTube
Package: com.google.android.youtube
From: 2026-02-04 12:26 AM
To: 2026-02-04 12:27 AM
Duration: 2h 24m
```

### Interruption Report
```
⚠️ Monitoring Interruption

From: 2026-02-04 12:10 AM
To: 2026-02-04 12:17 AM
Duration: 7m 0s
```

## Security Features

- **PIN Protection**: All settings require PIN verification
- **Secure Storage**: Sensitive data stored using Android Keystore
- **Device Admin**: Prevents easy uninstallation
- **Encrypted Storage**: PIN hash and Telegram credentials encrypted

## Monitoring Features

- **Continuous Tracking**: Foreground service ensures continuous monitoring
- **Gap Detection**: Detects when monitoring stops unexpectedly
- **Heartbeat System**: Logs heartbeat every minute
- **Watchdog**: WorkManager restarts service if killed
- **Boot Restart**: Automatically starts after device reboot

## Offline Support

- All usage data stored locally in SQLite
- Reports queued when offline
- Automatic sync when internet connection available
- WorkManager handles periodic sync

## Permissions Required

- `PACKAGE_USAGE_STATS`: Track app usage
- `FOREGROUND_SERVICE`: Run foreground service
- `RECEIVE_BOOT_COMPLETED`: Restart after reboot
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`: Prevent battery optimization
- `BIND_DEVICE_ADMIN`: Device admin protection
- `INTERNET`: Send reports to Telegram
- `POST_NOTIFICATIONS`: Show persistent notification

## Development Notes

### Testing

1. **Battery Impact**: Monitor battery usage during testing
2. **Reboot Test**: Verify service restarts after reboot
3. **Airplane Mode**: Test offline queue functionality
4. **Force Stop**: Test gap detection when service is killed
5. **Uninstall Protection**: Verify device admin prevents easy uninstall

### Play Store Compliance

This app is designed to comply with Google Play policies:
- Transparent about monitoring functionality
- Requires explicit user consent
- Provides clear disclosure during setup
- Allows users to disable monitoring (with PIN)

## Troubleshooting

### Service Not Starting
- Check if usage access permission is granted
- Verify battery optimization is disabled
- Ensure device admin is enabled

### Reports Not Sending
- Verify Telegram bot token and chat ID are correct
- Check internet connection
- Review sync service logs

### Data Not Syncing
- Check WorkManager status
- Verify database permissions
- Review native sync service logs

## License

This project is for educational purposes. Ensure compliance with local laws regarding monitoring software.

## Support

For issues or questions, please check the code comments or create an issue in the repository.
