package com.example.cash_radar

import android.content.Context
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NotificationUploadWorker(ctx:Context,params:WorkerParameters):Worker(ctx,params) {
    override fun doWork():Result {
        while(!isStopped && NotificationAccess.isGranted(applicationContext)) {
            val pair=NotificationStore.first(applicationContext) ?: return Result.success()
            val config=pair.first; val event=pair.second
            val endpoint=config.optString("url")+"/rest/v1/rpc/ingest_notification_event"
            val publicKey=config.optString("public_key");val token=config.optString("device_token")
            if(publicKey.isEmpty() || !token.matches(Regex("^[0-9a-f]{64}$"))) { NotificationStore.pause(applicationContext);return Result.failure() }
            try {
                val conn=URL(endpoint).openConnection() as HttpURLConnection
                try {
                    conn.requestMethod="POST";conn.connectTimeout=15000;conn.readTimeout=15000;conn.doOutput=true
                    conn.setRequestProperty("Content-Type","application/json");conn.setRequestProperty("apikey",publicKey)
                    if(publicKey.startsWith("eyJ"))conn.setRequestProperty("Authorization","Bearer $publicKey")
                    val body=JSONObject().put("p_device_token",token).put("p_event",event).toString().toByteArray(Charsets.UTF_8)
                    conn.outputStream.use { it.write(body) }
                    val status=conn.responseCode
                    if(status in 200..299) {
                        val data=conn.inputStream.bufferedReader().use { it.readText() }
                        if(!JSONObject(data).has("id"))return Result.retry()
                        NotificationStore.acknowledge(applicationContext,event.getString("event_key"))
                    } else if(status==401 || status==403) {
                        NotificationStore.pause(applicationContext);return Result.failure()
                    } else return Result.retry()
                } finally { conn.disconnect() }
            } catch (_:Exception) { return Result.retry() }
        }
        return Result.success()
    }
}
