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
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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

        private val sendScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        private val sendLock = Any()
        @Volatile
        private var isSendingReports = false

        fun triggerSendPendingReports(context: Context) {
            synchronized(sendLock) {
                if (isSendingReports) return
                isSendingReports = true
            }
            sendScope.launch {
                try {
                    val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                    val token = resolveTelegramValue(prefs, "telegram_token")
                    val chatId = resolveTelegramValue(prefs, "telegram_chat_id")
                    if (token.isNullOrEmpty() || chatId.isNullOrEmpty()) {
                        return@launch
                    }

                    val queue = mutableListOf<PendingReport>()
                    val allKeys = prefs.all.keys

                    val startKeys = allKeys.filter { key ->
                        key.startsWith("flutter.enter_") && key.endsWith("_package")
                    } + allKeys.filter { key ->
                        key.startsWith("enter_") && key.endsWith("_package") && !key.startsWith("flutter.")
                    }

                    for (key in startKeys) {
                        val isLegacy = !key.startsWith("flutter.")
                        val eventId = key.removePrefix("flutter.").removeSuffix("_package")
                        val prefix = if (isLegacy) "" else "flutter."
                        val packageName = prefs.getString(key, null)
                        val appName = prefs.getString("${prefix}${eventId}_name", null)
                        val timeStr = prefs.getString("${prefix}${eventId}_time", null)
                        val timeMs = timeStr?.toLongOrNull()
                        if (packageName != null && timeMs != null) {
                            val displayName = if (appName.isNullOrEmpty()) packageName else appName
                            val timestamp = formatTimestamp(timeMs)
                            val message = "App: $displayName\nAt : $timestamp"
                            queue.add(
                                PendingReport(
                                    timestamp = timeMs,
                                    send = { sendTelegramMessage(token, chatId, message) },
                                    onSuccess = {
                                        prefs.edit()
                                            .remove(key)
                                            .remove("${prefix}${eventId}_name")
                                            .remove("${prefix}${eventId}_time")
                                            .apply()
                                    }
                                )
                            )
                        }
                    }

                    val sessionKeys = allKeys.filter { key ->
                        key.startsWith("flutter.session_") && key.endsWith("_package")
                    } + allKeys.filter { key ->
                        key.startsWith("session_") && key.endsWith("_package") && !key.startsWith("flutter.")
                    }

                    for (key in sessionKeys) {
                        val isLegacy = !key.startsWith("flutter.")
                        val sessionId = key.removePrefix("flutter.").removeSuffix("_package")
                        val prefix = if (isLegacy) "" else "flutter."
                        val packageName = prefs.getString(key, null)
                        val appName = prefs.getString("${prefix}${sessionId}_name", null)
                        val startStr = prefs.getString("${prefix}${sessionId}_start", null)
                        val endStr = prefs.getString("${prefix}${sessionId}_end", null)
                        val durationStr = prefs.getString("${prefix}${sessionId}_duration", null)
                        val startMs = startStr?.toLongOrNull()
                        val endMs = endStr?.toLongOrNull()
                        if (packageName != null && startMs != null && endMs != null) {
                            val durationMs = durationStr?.toLongOrNull() ?: (endMs - startMs).coerceAtLeast(0)
                            val startTime = formatTimestamp(startMs)
                            val endTime = formatTimestamp(endMs)
                            val duration = formatDuration(durationMs)
                            val message =
                                "📱 App Usage\n\nApp: ${appName ?: packageName}\nPackage: $packageName\nFrom: $startTime\nTo: $endTime\nDuration: $duration"
                            queue.add(
                                PendingReport(
                                    timestamp = endMs,
                                    send = { sendTelegramMessage(token, chatId, message) },
                                    onSuccess = {
                                        prefs.edit()
                                            .remove(key)
                                            .remove("${prefix}${sessionId}_name")
                                            .remove("${prefix}${sessionId}_start")
                                            .remove("${prefix}${sessionId}_end")
                                            .remove("${prefix}${sessionId}_duration")
                                            .apply()
                                    }
                                )
                            )
                        }
                    }

                    val interruptionPrefs = context.getSharedPreferences("interruptions", Context.MODE_PRIVATE)
                    val interruptionKeys = interruptionPrefs.all.keys.filter { it.endsWith("_from") }
                    for (key in interruptionKeys) {
                        val baseKey = key.removeSuffix("_from")
                        val fromStr = interruptionPrefs.getString("${baseKey}_from", null)
                        val toStr = interruptionPrefs.getString("${baseKey}_to", null)
                        val durationStr = interruptionPrefs.getString("${baseKey}_duration", null)
                        val fromMs = fromStr?.toLongOrNull()
                        val toMs = toStr?.toLongOrNull()
                        val durationMs = durationStr?.toLongOrNull()
                        if (fromMs != null && toMs != null && durationMs != null) {
                            val fromTime = formatTimestamp(fromMs)
                            val toTime = formatTimestamp(toMs)
                            val duration = formatDuration(durationMs)
                            val message =
                                "⚠️ Monitoring Interruption\n\nFrom: $fromTime\nTo: $toTime\nDuration: $duration"
                            queue.add(
                                PendingReport(
                                    timestamp = toMs,
                                    send = { sendTelegramMessage(token, chatId, message) },
                                    onSuccess = {
                                        interruptionPrefs.edit()
                                            .remove("${baseKey}_from")
                                            .remove("${baseKey}_to")
                                            .remove("${baseKey}_duration")
                                            .apply()
                                    }
                                )
                            )
                        }
                    }

                    if (queue.isNotEmpty()) {
                        queue.sortBy { it.timestamp }
                        for (item in queue) {
                            val ok = item.send()
                            if (!ok) {
                                break
                            }
                            item.onSuccess()
                        }
                    }
                } finally {
                    synchronized(sendLock) {
                        isSendingReports = false
                    }
                }
            }
        }

        private fun formatTimestamp(timeMs: Long): String {
            val formatter = SimpleDateFormat("yyyy-MM-dd hh:mm a", Locale.getDefault())
            return formatter.format(Date(timeMs))
        }

        private fun formatDuration(milliseconds: Long): String {
            val totalSeconds = milliseconds / 1000
            val hours = totalSeconds / 3600
            val minutes = (totalSeconds % 3600) / 60
            val seconds = totalSeconds % 60
            return when {
                hours > 0 -> "${hours}h ${minutes}m"
                minutes > 0 -> "${minutes}m ${seconds}s"
                else -> "${seconds}s"
            }
        }

        private fun sendTelegramMessage(token: String, chatId: String, message: String): Boolean {
            return try {
                val url = URL("https://api.telegram.org/bot$token/sendMessage")
                val connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 10000
                connection.readTimeout = 10000
                connection.doOutput = true

                val data = "chat_id=${URLEncoder.encode(chatId, "UTF-8")}" +
                    "&text=${URLEncoder.encode(message, "UTF-8")}"
                connection.outputStream.use { output ->
                    output.write(data.toByteArray(Charsets.UTF_8))
                }
                val code = connection.responseCode
                connection.disconnect()
                code == 200
            } catch (e: Exception) {
                false
            }
        }

        private fun resolveTelegramValue(
            prefs: android.content.SharedPreferences,
            key: String
        ): String? {
            val direct = prefs.getString(key, null)
            if (!direct.isNullOrEmpty()) return direct
            return prefs.getString("flutter.$key", null)
        }
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
                        UsageEvents.Event.MOVE_TO_FOREGROUND,
                        UsageEvents.Event.ACTIVITY_RESUMED -> {
                            startSession(event.packageName, event.timeStamp)
                        }
                        UsageEvents.Event.MOVE_TO_BACKGROUND,
                        UsageEvents.Event.ACTIVITY_PAUSED,
                        UsageEvents.Event.ACTIVITY_STOPPED -> {
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

    private data class PendingReport(
        val timestamp: Long,
        val send: () -> Boolean,
        val onSuccess: () -> Unit
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

                android.util.Log.d("TrackingService", "Saved session: $appName ($packageName) - ${duration}ms")
                triggerSendPendingReports(this@TrackingService)
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
                val eventKey = "enter_${System.currentTimeMillis()}"
                val editor = prefs.edit()
                editor.putString("flutter.${eventKey}_package", packageName)
                editor.putString("flutter.${eventKey}_name", appName)
                editor.putString("flutter.${eventKey}_time", startTime.toString())
                editor.commit()
                android.util.Log.d("TrackingService", "Stored enter event in SharedPreferences: flutter.$eventKey")
                triggerSendPendingReports(this@TrackingService)
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

    private fun isSystemApp(appInfo: ApplicationInfo): Boolean {
        val flags = appInfo.flags
        return (flags and ApplicationInfo.FLAG_SYSTEM) != 0 ||
            (flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) != 0
    }

    private fun isTrackablePackage(packageName: String): Boolean {
        if (packageName == this.packageName) return false
        if (isHomePackage(packageName)) return false
        val launchablePackages = getLaunchablePackages()
        if (launchablePackages != null && launchablePackages.isNotEmpty()) {
            return launchablePackages.contains(packageName)
        }
        return true
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
