package com.child.safety.kilowares

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.child.safety.kilowares/tracking"
    private val USAGE_EVENTS_CHANNEL = "com.child.safety.kilowares/usageEvents"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startTracking" -> {
                    val intent = Intent(this, TrackingService::class.java)
                    intent.action = TrackingService.ACTION_START
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }
                "stopTracking" -> {
                    val intent = Intent(this, TrackingService::class.java)
                    intent.action = TrackingService.ACTION_STOP
                    stopService(intent)
                    result.success(true)
                }
                "isTrackingRunning" -> {
                    result.success(TrackingService.isRunning)
                }
                "requestUsageAccess" -> {
                    val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    startActivity(intent)
                    result.success(true)
                }
                "hasUsageAccess" -> {
                    result.success(hasUsageAccess())
                }
                "requestBatteryOptimizationExemption" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                        intent.data = android.net.Uri.parse("package:$packageName")
                        startActivity(intent)
                    }
                    result.success(true)
                }
                "isBatteryOptimizationExempt" -> {
                    result.success(isBatteryOptimizationExempt())
                }
                "enableDeviceAdmin" -> {
                    val intents = listOf(
                        Intent().setClassName(
                            "com.android.settings",
                            "com.android.settings.Settings\$DeviceAdminSettingsActivity"
                        ),
                        Intent().setClassName(
                            "com.android.settings",
                            "com.android.settings.DeviceAdminSettings"
                        ),
                        Intent("android.settings.DEVICE_ADMIN_SETTINGS"),
                        Intent(Settings.ACTION_SECURITY_SETTINGS),
                        Intent(Settings.ACTION_SETTINGS)
                    )
                    var launched = false
                    for (intent in intents) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        if (packageManager.resolveActivity(intent, 0) != null) {
                            startActivity(intent)
                            launched = true
                            break
                        }
                    }
                    if (!launched) {
                        startActivity(Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    result.success(true)
                }
                "isDeviceAdminEnabled" -> {
                    val devicePolicyManager = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                    val adminComponent = DeviceAdminReceiver.getComponentName(this)
                    val isActive = devicePolicyManager.isAdminActive(adminComponent)
                    val activeAdmins = devicePolicyManager.activeAdmins
                    val packageActive = activeAdmins?.any { it.packageName == packageName } == true
                    result.success(isActive || packageActive)
                }
                "scheduleSync" -> {
                    SyncWorker.scheduleSync(this)
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun hasUsageAccess(): Boolean {
        val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            time - 1000 * 60,
            time
        )
        return stats != null && stats.isNotEmpty()
    }

    private fun isBatteryOptimizationExempt(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            return powerManager.isIgnoringBatteryOptimizations(packageName)
        }
        return true // On older versions, assume exempt
    }
}
