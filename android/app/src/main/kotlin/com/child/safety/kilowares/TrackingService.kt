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
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.text.SimpleDateFormat
import java.util.*
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class TrackingService : Service() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val handler = Handler(Looper.getMainLooper())
    
    private var lastProcessedEventTime: Long = 0
    private var activeSession: ActiveSession? = null
    private var heartbeatRunnable: Runnable? = null
    private var cachedHomePackages: Set<String>? = null
    private var cachedHomePackagesTime: Long = 0
    private var cachedLaunchablePackages: Set<String>? = null
    private var cachedLaunchablePackagesTime: Long = 0
    
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
        if (activeSession != null) {
            endSession(System.currentTimeMillis())
        }
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
                
                while (events.hasNextEvent()) {
                    val event = UsageEvents.Event()
                    events.getNextEvent(event)
                    if (event.timeStamp <= lastProcessedEventTime) {
                        continue
                    }
                    lastProcessedEventTime = event.timeStamp

                    when (event.eventType) {
                        UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                            startSession(event.packageName, event.timeStamp)
                        }
                        UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                            if (activeSession?.packageName == event.packageName) {
                                endSession(event.timeStamp)
                            }
                        }
                    }
                }

                val topApp = resolveTopApp(usageStatsManager, time)
                if (topApp != null) {
                    if (activeSession == null) {
                        startSession(topApp.packageName, topApp.lastTimeUsed)
                    } else if (activeSession?.packageName != topApp.packageName) {
                        endSession(time)
                        startSession(topApp.packageName, topApp.lastTimeUsed)
                    }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    private fun resolveTopApp(
        usageStatsManager: UsageStatsManager,
        now: Long
    ): TopApp? {
        val stats = usageStatsManager.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 60000,
            now
        )
        if (stats.isNullOrEmpty()) return null
        val recent = stats
            .filter { it.lastTimeUsed > 0 }
            .maxByOrNull { it.lastTimeUsed }
            ?: return null
        if (recent.lastTimeUsed < now - 60000) return null
        return TopApp(recent.packageName, recent.lastTimeUsed)
    }

    private data class TopApp(val packageName: String, val lastTimeUsed: Long)

    private data class ActiveSession(
        val packageName: String,
        val startTime: Long
    )

    private fun startSession(packageName: String, startTime: Long) {
        if (!isTrackablePackage(packageName)) {
            if (activeSession != null) {
                endSession(startTime)
            }
            activeSession = null
            return
        }
        if (activeSession?.packageName == packageName) {
            return
        }
        if (activeSession != null) {
            endSession(startTime)
        }
        activeSession = ActiveSession(packageName, startTime)
        handleAppSessionStart(packageName, startTime)
    }

    private fun endSession(endTime: Long) {
        val session = activeSession ?: return
        val normalizedEndTime = if (endTime >= session.startTime) endTime else session.startTime
        handleAppSessionEnd(session.packageName, session.startTime, normalizedEndTime)
        activeSession = null
    }

    private fun handleAppSessionEnd(packageName: String, startTime: Long, endTime: Long) {
        serviceScope.launch {
            try {
                val packageManager = packageManager
                val appName = resolveTrackableAppName(packageName) ?: return@launch
                
                val normalizedEndTime = if (endTime >= startTime) endTime else startTime
                val duration = normalizedEndTime - startTime
                if (duration < 1000) {
                    return@launch
                }

                val sent = sendTelegramMessage(
                    buildUsageMessage(appName, packageName, startTime, normalizedEndTime, duration)
                )
                if (!sent) {
                    val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val sessionKey = "session_${System.currentTimeMillis()}"
                    val editor = prefs.edit()
                    editor.putString("flutter.${sessionKey}_package", packageName)
                    editor.putString("flutter.${sessionKey}_name", appName)
                    editor.putString("flutter.${sessionKey}_start", startTime.toString())
                    editor.putString("flutter.${sessionKey}_end", normalizedEndTime.toString())
                    editor.putString("flutter.${sessionKey}_duration", duration.toString())
                    editor.commit()
                    android.util.Log.d("TrackingService", "Stored session in SharedPreferences: flutter.$sessionKey")
                }

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
                val appName = resolveTrackableAppName(packageName) ?: return@launch

                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val sent = sendTelegramMessage("App: $appName\nAt : ${formatDateTime(startTime)}")
                if (!sent) {
                    val eventKey = "enter_${System.currentTimeMillis()}"
                    val editor = prefs.edit()
                    editor.putString("flutter.${eventKey}_package", packageName)
                    editor.putString("flutter.${eventKey}_name", appName)
                    editor.putString("flutter.${eventKey}_time", startTime.toString())
                    editor.commit()
                    android.util.Log.d("TrackingService", "Stored enter event in SharedPreferences: flutter.$eventKey")
                }
            } catch (e: Exception) {
                android.util.Log.e("TrackingService", "Error handling app session start", e)
                e.printStackTrace()
            }
        }
    }

    private suspend fun sendTelegramMessage(message: String): Boolean {
        return withContext(Dispatchers.IO) {
            try {
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val token = prefs.getString("flutter.telegram_token", null)
                val chatId = prefs.getString("flutter.telegram_chat_id", null)
                if (token.isNullOrBlank() || chatId.isNullOrBlank()) return@withContext false

                val url = URL("https://api.telegram.org/bot$token/sendMessage")
                val connection = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    doOutput = true
                    connectTimeout = 5000
                    readTimeout = 5000
                }
                val data =
                    "chat_id=${URLEncoder.encode(chatId, "UTF-8")}&text=${URLEncoder.encode(message, "UTF-8")}"
                connection.outputStream.use { it.write(data.toByteArray(Charsets.UTF_8)) }
                val responseCode = connection.responseCode
                connection.disconnect()
                responseCode == 200
            } catch (e: Exception) {
                false
            }
        }
    }

    private fun buildUsageMessage(
        appName: String,
        packageName: String,
        startTime: Long,
        endTime: Long,
        durationMs: Long
    ): String {
        val from = formatDateTime(startTime)
        val to = formatDateTime(endTime)
        val duration = formatDuration(durationMs)
        return "📱 App Usage\n\nApp: $appName\nPackage: $packageName\nFrom: $from\nTo: $to\nDuration: $duration"
    }

    private fun formatDateTime(timestamp: Long): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd hh:mm a", Locale.getDefault())
        return formatter.format(Date(timestamp))
    }

    private fun formatDuration(durationMs: Long): String {
        val seconds = durationMs / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        val remainingMinutes = minutes % 60
        val remainingSeconds = seconds % 60
        return when {
            hours > 0 -> "${hours}h ${remainingMinutes}m"
            minutes > 0 -> "${minutes}m ${remainingSeconds}s"
            else -> "${remainingSeconds}s"
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

    private fun isSystemApp(appInfo: ApplicationInfo): Boolean {
        val flags = appInfo.flags
        return (flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
    }

    private fun isTrackablePackage(packageName: String): Boolean {
        if (isHomePackage(packageName)) return false
        val launchablePackages = getLaunchablePackages()
        if (launchablePackages != null) {
            return launchablePackages.contains(packageName)
        }
        return packageManager.getLaunchIntentForPackage(packageName) != null
    }

    private fun resolveTrackableAppName(packageName: String): String? {
        if (!isTrackablePackage(packageName)) return null
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(appInfo).toString()
        } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
            packageName
        } catch (e: Exception) {
            packageName
        }
    }

    private fun isHomePackage(packageName: String): Boolean {
        return getHomePackages().contains(packageName)
    }

    private fun getHomePackages(): Set<String> {
        val now = System.currentTimeMillis()
        val cached = cachedHomePackages
        if (cached != null && now - cachedHomePackagesTime < 60 * 60 * 1000) {
            return cached
        }
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
        }
        val resolveInfos = packageManager.queryIntentActivities(intent, 0)
        val packages = resolveInfos.mapNotNull { it.activityInfo?.packageName }.toSet()
        cachedHomePackages = packages
        cachedHomePackagesTime = now
        return packages
    }

    private fun getLaunchablePackages(): Set<String>? {
        val now = System.currentTimeMillis()
        val cached = cachedLaunchablePackages
        if (cached != null && now - cachedLaunchablePackagesTime < 60 * 60 * 1000) {
            return cached
        }
        cachedLaunchablePackagesTime = now
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
            }
            val resolveInfos = packageManager.queryIntentActivities(intent, 0)
            val packages = resolveInfos.mapNotNull { it.activityInfo?.packageName }.toSet()
            cachedLaunchablePackages = packages
            packages
        } catch (e: Exception) {
            cachedLaunchablePackages = null
            null
        }
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
