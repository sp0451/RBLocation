package com.clocation.location_bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Holds Android's visible foreground lifetime; coordinates stay in native memory. */
class MockLocationService : Service() {
    companion object {
        const val ACTION_STOP = "com.clocation.location_bridge.STOP"
        internal const val CHANNEL_ID = "clocation_mock_location"
        private const val NOTIFICATION_ID = 24601
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val runtime = MockLocationRuntime.get(applicationContext)
        if (intent?.action == ACTION_STOP) {
            runtime.stopFromNotification()
            finish()
            return START_NOT_STICKY
        }
        try {
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "定位模拟", NotificationManager.IMPORTANCE_LOW),
                )
            }
            val stop = PendingIntent.getService(
                this,
                0,
                Intent(this, MockLocationService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, CHANNEL_ID)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
            builder
                .setSmallIcon(android.R.drawable.ic_menu_mylocation)
                .setContentTitle("CLocation 定位服务")
                .setContentText("定位模拟会话运行中，可点按停止。")
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_SERVICE)
                .addAction(Notification.Action.Builder(null, "停止模拟", stop).build())
            packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
                builder.setContentIntent(
                    PendingIntent.getActivity(
                        this,
                        1,
                        launch,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    ),
                )
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(NOTIFICATION_ID, builder.build(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            } else {
                startForeground(NOTIFICATION_ID, builder.build())
            }
            runtime.onServiceReady(this)
        } catch (failure: Exception) {
            runtime.onServiceStartFailed(failure)
            finish()
        }
        // A killed process must never replay its previous location.
        return START_NOT_STICKY
    }

    internal fun finish() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        MockLocationRuntime.get(applicationContext).onServiceDestroyed(this)
        super.onDestroy()
    }
}
