package com.child.safety.kilowares

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

class SyncWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            // Check if tracking service is running
            if (!TrackingService.isRunning) {
                // Restart tracking service if it's not running
                val serviceIntent = android.content.Intent(applicationContext, TrackingService::class.java)
                serviceIntent.action = TrackingService.ACTION_START
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(serviceIntent)
                } else {
                    applicationContext.startService(serviceIntent)
                }
            }
            
            // Check for interruptions (gap in heartbeat)
            checkForInterruptions()
            TrackingService.triggerSendPendingReports(applicationContext)
            
            return Result.success()
        } catch (e: Exception) {
            e.printStackTrace()
            return Result.retry()
        }
    }

    private fun checkForInterruptions() {
        val prefs = applicationContext.getSharedPreferences("heartbeats", Context.MODE_PRIVATE)
        // Get heartbeat as string (we store it as string now)
        val lastHeartbeatStr = prefs.getString("last_heartbeat", null)
        
        val lastHeartbeat = if (lastHeartbeatStr != null) {
            try {
                lastHeartbeatStr.toLong()
            } catch (e: Exception) {
                0L
            }
        } else {
            0L
        }
        
        if (lastHeartbeat > 0) {
            val now = System.currentTimeMillis()
            val gap = now - lastHeartbeat
            
            // If gap is more than 5 minutes, consider it an interruption
            if (gap > 5 * 60 * 1000) {
                // Log interruption
                val interruptionPrefs = applicationContext.getSharedPreferences("interruptions", Context.MODE_PRIVATE)
                val interruptionKey = "interruption_${System.currentTimeMillis()}"
                interruptionPrefs.edit().apply {
                    putString("${interruptionKey}_from", lastHeartbeat.toString())
                    putString("${interruptionKey}_to", now.toString())
                    putString("${interruptionKey}_duration", gap.toString())
                    apply()
                }
                android.util.Log.w("SyncWorker", "Interruption detected: ${gap / 1000 / 60} minutes")
            }
        }
    }

    companion object {
        fun scheduleSync(context: Context) {
            val syncRequest = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(
                    androidx.work.Constraints.Builder()
                        .setRequiredNetworkType(androidx.work.NetworkType.CONNECTED)
                        .build()
                )
                .build()
            
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "sync_work",
                androidx.work.ExistingPeriodicWorkPolicy.KEEP,
                syncRequest
            )
        }
    }
}
