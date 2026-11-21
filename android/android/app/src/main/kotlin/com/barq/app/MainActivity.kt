package com.barq.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        createBarqNotificationChannels()
    }

    private fun createBarqNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java) ?: return
        val channels = listOf(
            NotificationChannel(
                "barq_messages",
                "رسائل برق الخاصة",
                NotificationManager.IMPORTANCE_HIGH
            ),
            NotificationChannel(
                "barq_groups",
                "رسائل مجموعات برق",
                NotificationManager.IMPORTANCE_HIGH
            ),
            NotificationChannel(
                "barq_statuses",
                "حالات برق",
                NotificationManager.IMPORTANCE_DEFAULT
            )
        )
        channels.forEach { channel ->
            channel.description = "إشعارات تطبيق برق"
            channel.enableVibration(true)
            manager.createNotificationChannel(channel)
        }
    }
}
