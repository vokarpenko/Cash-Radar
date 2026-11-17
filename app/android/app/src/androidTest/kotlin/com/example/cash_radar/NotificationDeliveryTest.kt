package com.example.cash_radar

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import android.content.ComponentName
import android.os.Build
import android.provider.Settings
import org.junit.Test
import org.junit.runner.RunWith

/** Uses only synthetic data and the device credential already activated by the user. */
@RunWith(AndroidJUnit4::class)
class NotificationDeliveryTest {
    @Test fun systemSettingsReceivesStringComponentName() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        val intent=NotificationAccess.settingsIntent(context)
        if(Build.VERSION.SDK_INT>=30) assertEquals(ComponentName(context,NotificationCollectorService::class.java).flattenToString(),intent.getStringExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME))
        else assertEquals(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS,intent.action)
    }
    @Test fun syntheticAcbaEventTraversesEncryptedQueueAndUpload() {
        val context=InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue("Notification access must be enabled by the user",NotificationAccess.isGranted(context))
        assertTrue("Collector must be enabled by the user",NotificationStore.enabled(context))
        val now=System.currentTimeMillis()
        val event=NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE 123.45 AMD 4355***9999, CASHRADAR SYNTHETIC TEST, AM 11.11.2026 22:47",now)
        assertNotNull(event)
        val owner=NotificationStore.owner(context)!!
        val installation=NotificationStore.installation(context)!!
        val rejected=NotificationCollectorService.enqueue(context,NotificationParser.ACBA,"wrong-owner-${now}",now,event!!,"00000000-0000-4000-8000-000000000000",installation)
        assertNull("A different owner must not capture the event",rejected)
        val id=NotificationCollectorService.enqueue(context,NotificationParser.ACBA,"cashradar-instrumentation-${now}",now,event,owner,installation)
        val stored=context.getSharedPreferences("cashradar_notification_queue",android.content.Context.MODE_PRIVATE).getString("data","") ?: ""
        assertFalse("Queue must not contain cleartext merchant",stored.contains("CASHRADAR SYNTHETIC"))
        assertFalse("Device token must not be stored in cleartext",stored.contains("device_token"))
        assertNotNull("Synthetic event could not enter the queue",id)
        val end=System.currentTimeMillis()+60000
        while(System.currentTimeMillis()<end && NotificationStore.contains(context,id!!)) Thread.sleep(500)
        assertFalse("Synthetic event remained in the upload queue",NotificationStore.contains(context,id!!))
    }
}
