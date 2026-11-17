package com.example.cash_radar

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import android.content.Intent
import android.os.Build

object NotificationAccess {
    fun settingsIntent(context:Context):Intent = if(Build.VERSION.SDK_INT>=30) {
        Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
            ComponentName(context,NotificationCollectorService::class.java).flattenToString(),
        )
    } else Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
    fun isGranted(context:Context):Boolean {
        val enabled=Settings.Secure.getString(context.contentResolver,"enabled_notification_listeners") ?: return false
        val expected=ComponentName(context,NotificationCollectorService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it)==expected }
    }
}
