package com.example.cash_radar

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.Constraints
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import org.json.JSONObject
import java.security.MessageDigest
import java.util.concurrent.Executors

class NotificationCollectorService : NotificationListenerService() {
    private val executor=Executors.newSingleThreadExecutor()
    override fun onNotificationPosted(sbn:StatusBarNotification) {
        // Check source and opt-in before reading any notification content. SMS,
        // email and arbitrary apps are never inspected.
        if(sbn.packageName !in NotificationParser.allowedPackages || !NotificationStore.enabled(this))return
        val owner=NotificationStore.owner(this) ?: return
        val installation=NotificationStore.installation(this) ?: return
        val extras=sbn.notification.extras ?: return
        val title=extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val body=(extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString()
        val parsed=NotificationParser.parse(sbn.packageName,title,body,sbn.postTime) ?: return
        val notificationKey=sbn.key
        val packageName=sbn.packageName
        val postedAt=sbn.postTime
        executor.execute { enqueue(applicationContext,packageName,notificationKey,postedAt,parsed,owner,installation) }
    }
    override fun onDestroy() { executor.shutdown();super.onDestroy() }
    companion object {
        internal fun enqueue(ctx:android.content.Context,sourcePackage:String,notificationKey:String,postedAt:Long,parsed:NotificationParser.Event,owner:String,installation:String):String? {
            if(sourcePackage !in NotificationParser.allowedPackages || !NotificationAccess.isGranted(ctx) || !NotificationStore.enabled(ctx))return null
            val identity=listOf(installation,sourcePackage,notificationKey,postedAt.toString(),parsed.kind,parsed.amount,parsed.currency,parsed.merchant,parsed.cardLast4,parsed.occurredAtMillis.toString()).joinToString("\u0000")
            val eventKey=MessageDigest.getInstance("SHA-256").digest(identity.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }
            val event=JSONObject().put("event_key",eventKey).put("source",parsed.source).put("kind",parsed.kind).put("amount",parsed.amount)
                .put("currency",parsed.currency).put("merchant",parsed.merchant).put("card_last4",parsed.cardLast4)
                .put("occurred_at",NotificationParser.iso(parsed.occurredAtMillis)).put("time_source",parsed.timeSource)
            if(!NotificationStore.append(ctx,event,owner,installation))return null
            schedule(ctx)
            return eventKey
        }
        fun schedule(ctx:android.content.Context) {
            val work=OneTimeWorkRequestBuilder<NotificationUploadWorker>().setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()).build()
            WorkManager.getInstance(ctx).enqueueUniqueWork("cashradar-notification-upload",ExistingWorkPolicy.APPEND_OR_REPLACE,work)
        }
    }
}
