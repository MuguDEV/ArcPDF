package com.arcpdf.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class ArcPdfJobService : Service() {
    companion object {
        private const val channelId = "arcpdf_operations"
        private const val notificationId = 4102
        private const val preferences = "arcpdf_job_recovery"
        private const val actionStart = "com.arcpdf.app.JOB_START"
        private const val actionUpdate = "com.arcpdf.app.JOB_UPDATE"
        private const val actionFinish = "com.arcpdf.app.JOB_FINISH"

        fun start(context: Context, jobId: String, title: String, stage: String, outputPath: String?) {
            val intent = Intent(context, ArcPdfJobService::class.java).apply {
                action = actionStart
                putExtra("jobId", jobId)
                putExtra("title", title)
                putExtra("stage", stage)
                putExtra("outputPath", outputPath)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun update(context: Context, stage: String, progress: Int?) {
            context.startService(Intent(context, ArcPdfJobService::class.java).apply {
                action = actionUpdate
                putExtra("stage", stage)
                if (progress != null) putExtra("progress", progress)
            })
        }

        fun finish(context: Context) {
            context.startService(Intent(context, ArcPdfJobService::class.java).apply {
                action = actionFinish
            })
        }

        fun recover(context: Context): Map<String, Any?>? {
            val values = context.getSharedPreferences(preferences, Context.MODE_PRIVATE)
            if (!values.getBoolean("active", false)) return null
            return mapOf(
                "jobId" to values.getString("jobId", null),
                "title" to values.getString("title", null),
                "stage" to values.getString("stage", null),
                "outputPath" to values.getString("outputPath", null),
            )
        }

        fun clearRecovery(context: Context) {
            context.getSharedPreferences(preferences, Context.MODE_PRIVATE).edit().clear().apply()
        }
    }

    private var title = "ArcPDF operation"
    private var stage = "Preparing…"
    private var progress: Int? = null

    override fun onCreate() {
        super.onCreate()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "PDF operations",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply { description = "Progress for PDF processing operations" }
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            actionStart -> {
                title = intent.getStringExtra("title") ?: title
                stage = intent.getStringExtra("stage") ?: stage
                progress = null
                getSharedPreferences(preferences, Context.MODE_PRIVATE).edit()
                    .putBoolean("active", true)
                    .putString("jobId", intent.getStringExtra("jobId"))
                    .putString("title", title)
                    .putString("stage", stage)
                    .putString("outputPath", intent.getStringExtra("outputPath"))
                    .apply()
                startForeground(notificationId, notification())
            }
            actionUpdate -> {
                stage = intent.getStringExtra("stage") ?: stage
                progress = if (intent.hasExtra("progress")) {
                    intent.getIntExtra("progress", 0).coerceIn(0, 100)
                } else null
                getSharedPreferences(preferences, Context.MODE_PRIVATE).edit()
                    .putString("stage", stage).apply()
                getSystemService(NotificationManager::class.java)
                    .notify(notificationId, notification())
            }
            actionFinish -> {
                clearRecovery(this)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
        }
        // The Rust/Dart job cannot safely resume after process death. Recovery
        // metadata is consumed on the next app launch instead of presenting a
        // stale notification for work that no longer exists.
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val pending = PendingIntent.getActivity(
            this,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(title)
            .setContentText(stage)
            .setContentIntent(pending)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        val value = progress
        if (value == null) builder.setProgress(0, 0, true)
        else builder.setProgress(100, value, false)
        return builder.build()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
