package com.example.novel_reader

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class TtsKeepAliveService : Service() {
    companion object {
        const val ACTION_START = "com.example.novel_reader.action.START_TTS_KEEP_ALIVE"
        const val ACTION_STOP = "com.example.novel_reader.action.STOP_TTS_KEEP_ALIVE"
        private const val CHANNEL_ID = "tts_keep_alive_channel"
        private const val NOTIFICATION_ID = 1001
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopKeepAlive()
                stopSelf()
            }
            else -> {
                startKeepAlive()
            }
        }
        return START_STICKY
    }

    private fun startKeepAlive() {
        startForeground(NOTIFICATION_ID, buildNotification())
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "novel_reader:tts_keep_alive")
        wakeLock?.setReferenceCounted(false)
        wakeLock?.acquire()
    }

    private fun stopKeepAlive() {
        if (wakeLock?.isHeld == true) {
            wakeLock?.release()
        }
        wakeLock = null
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("小说阅读器正在听书")
            .setContentText("屏幕熄灭时保持听书运行")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID,
            "TTS Keep Alive",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopKeepAlive()
        super.onDestroy()
    }
}

internal fun Context.startTtsKeepAliveService() {
    val intent = Intent(this, TtsKeepAliveService::class.java).apply {
        action = TtsKeepAliveService.ACTION_START
    }
    ContextCompat.startForegroundService(this, intent)
}

internal fun Context.stopTtsKeepAliveService() {
    val intent = Intent(this, TtsKeepAliveService::class.java).apply {
        action = TtsKeepAliveService.ACTION_STOP
    }
    startService(intent)
}
