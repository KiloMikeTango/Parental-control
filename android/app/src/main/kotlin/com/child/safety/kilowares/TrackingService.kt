package com.child.safety.kilowares

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.*

class TrackingService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val handler = Handler(Looper.getMainLooper())
    
    private var lastForegroundPackage: String? = null
    private var lastForegroundTime: Long = 0
    private var heartbeatRunnable: Runnable? = null
    
    companion object {
        const val ACTION_START = "com.child.safety.kilowares.START_TRACKING"
        const val ACTION_STOP = "com.child.safety.kilowares.STOP_TRACKING"
        const val NOTIFICATION_ID = 1
        const val CHANNEL_ID = "tracking_channel"
        
        @Volatile
        var isRunning = false
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundTracking()
            }
            ACTION_STOP -> {
                stopForegroundTracking()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "App Usage Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tracks app usage and sends reports"
                setShowBadge(false)
            }
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundTracking() {
        isRunning = true
        startForeground(NOTIFICATION_ID, createNotification())
        
        // Start heartbeat
        startHeartbeat()
        
        // Start monitoring
        handler.postDelayed(object : Runnable {
            override fun run() {
                if (isRunning) {
                    checkForegroundApp()
                    handler.postDelayed(this, 5000) // Check every 5 seconds
                }
            }
        }, 5000)
    }

    private fun stopForegroundTracking() {
        isRunning = false
        handler.removeCallbacksAndMessages(null)
        heartbeatRunnable?.let { handler.removeCallbacks(it) }
        stopForeground(true)
        stopSelf()
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            pendingIntentFlags
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("App Usage Tracking Active")
            .setContentText("Monitoring app usage...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun checkForegroundApp() {
        serviceScope.launch {
            try {
                val usageStatsManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                val time = System.currentTimeMillis()
                val events = usageStatsManager.queryEvents(time - 10000, time)
                
                var currentPackage: String? = null
                var eventTime: Long = 0
                
                while (events.hasNextEvent()) {
                    val event = UsageEvents.Event()
                    events.getNextEvent(event)
                    
                    when (event.eventType) {
                        UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                            currentPackage = event.packageName
                            eventTime = event.timeStamp
                        }
                        UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                            if (currentPackage != null) {
                                // App moved to background, end session
                                handleAppSessionEnd(currentPackage, eventTime, event.timeStamp)
                                currentPackage = null
                            }
                        }
                    }
                }
                
                // Check if we have a current foreground app
                if (currentPackage != null && currentPackage != lastForegroundPackage) {
                    // New app in foreground
                    if (lastForegroundPackage != null && lastForegroundTime > 0) {
                        // End previous session
                        handleAppSessionEnd(lastForegroundPackage!!, lastForegroundTime, eventTime)
                    }
                    if (eventTime > 0) {
                        handleAppSessionStart(currentPackage, eventTime)
                    }
                    lastForegroundPackage = currentPackage
                    lastForegroundTime = eventTime
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun handleAppSessionEnd(packageName: String, startTime: Long, endTime: Long) {
        serviceScope.launch {
            try {
                val packageManager = packageManager
                var appName = packageName // Fallback to package name
                
                try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    appName = packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                    // Package not found or inaccessible - use package name as fallback
                    android.util.Log.w("TrackingService", "Could not get app name for $packageName, using package name")
                } catch (e: Exception) {
                    // Other errors - use package name as fallback
                    android.util.Log.w("TrackingService", "Error getting app name for $packageName: ${e.message}")
                }
                
                val duration = endTime - startTime
                
                // Store in default SharedPreferences for Flutter to sync
                // Use default SharedPreferences so Flutter can access it
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val sessionKey = "session_${System.currentTimeMillis()}"
                val editor = prefs.edit()
                editor.putString("flutter.${sessionKey}_package", packageName)
                editor.putString("flutter.${sessionKey}_name", appName)
                editor.putString("flutter.${sessionKey}_start", startTime.toString())
                editor.putString("flutter.${sessionKey}_end", endTime.toString())
                editor.putString("flutter.${sessionKey}_duration", duration.toString())
                editor.commit() // Use commit() for immediate write
                android.util.Log.d("TrackingService", "Stored session in SharedPreferences: flutter.$sessionKey")
                
                android.util.Log.d("TrackingService", "Saved session: $appName ($packageName) - ${duration}ms")
            } catch (e: Exception) {
                android.util.Log.e("TrackingService", "Error handling app session end", e)
                e.printStackTrace()
            }
        }
    }

    private fun handleAppSessionStart(packageName: String, startTime: Long) {
        serviceScope.launch {
            try {
                val packageManager = packageManager
                var appName = packageName

                try {
                    val appInfo = packageManager.getApplicationInfo(packageName, 0)
                    appName = packageManager.getApplicationLabel(appInfo).toString()
                } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
                    android.util.Log.w("TrackingService", "Could not get app name for $packageName, using package name")
                } catch (e: Exception) {
                    android.util.Log.w("TrackingService", "Error getting app name for $packageName: ${e.message}")
                }

                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val eventKey = "enter_${System.currentTimeMillis()}"
                val editor = prefs.edit()
                editor.putString("flutter.${eventKey}_package", packageName)
                editor.putString("flutter.${eventKey}_name", appName)
                editor.putString("flutter.${eventKey}_time", startTime.toString())
                editor.commit()
                android.util.Log.d("TrackingService", "Stored enter event in SharedPreferences: flutter.$eventKey")
            } catch (e: Exception) {
                android.util.Log.e("TrackingService", "Error handling app session start", e)
                e.printStackTrace()
            }
        }
    }

    private fun sendUsageEventToFlutter(
        packageName: String,
        appName: String,
        startTime: Long,
        endTime: Long,
        duration: Long
    ) {
        // This will be handled by EventChannel in MainActivity
        // For now, we store in SharedPreferences and Flutter polls
    }

    private fun startHeartbeat() {
        heartbeatRunnable = object : Runnable {
            override fun run() {
                if (isRunning) {
                    // Log heartbeat
                    val prefs = getSharedPreferences("heartbeats", Context.MODE_PRIVATE)
                    val currentTime = System.currentTimeMillis()
                    prefs.edit().putString("last_heartbeat", currentTime.toString()).apply()
                    
                    android.util.Log.d("TrackingService", "Heartbeat: $currentTime")
                    handler.postDelayed(this, 60000) // Every minute
                }
            }
        }
        handler.post(heartbeatRunnable!!)
    }

    override fun onDestroy() {
        super.onDestroy()
        isRunning = false
        handler.removeCallbacksAndMessages(null)
    }
}
