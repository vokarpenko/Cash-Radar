package com.example.cash_radar

import android.content.Intent
import android.provider.Settings
import androidx.work.WorkManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URI

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine:FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,"cashradar/notifications").setMethodCallHandler { call,result ->
            try {
                when(call.method) {
                    "status" -> result.success(mapOf("permission" to NotificationAccess.isGranted(this),"enabled" to NotificationStore.enabled(this),"deviceId" to NotificationStore.deviceId(this),"ownerId" to NotificationStore.owner(this),"queued" to NotificationStore.count(this),"dropped" to NotificationStore.dropped(this)))
                    "openSettings" -> {
                        val intent=NotificationAccess.settingsIntent(this)
                        try { startActivity(intent) } catch (_:Exception) { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
                        result.success(null)
                    }
                    "activate" -> {
                        if(!NotificationAccess.isGranted(this)) { result.error("permission_required","Notification access is required",null);return@setMethodCallHandler }
                        val user=call.argument<String>("userId") ?: error("user")
                        val device=call.argument<String>("deviceId") ?: error("device")
                        val token=call.argument<String>("token") ?: error("token")
                        val base=call.argument<String>("url") ?: error("url")
                        val publicKey=call.argument<String>("publicKey") ?: error("public key")
                        val local=call.argument<Boolean>("allowLocal") ?: false
                        val uri=URI(base)
                        val safeUrl=uri.userInfo==null && uri.rawQuery==null && uri.rawFragment==null && (uri.path.isNullOrEmpty() || uri.path=="/") && (uri.scheme=="https" || (local && uri.scheme=="http" && uri.host in setOf("127.0.0.1","localhost","10.0.2.2")))
                        require(user.matches(Regex("^[0-9a-fA-F-]{36}$")) && device.matches(Regex("^[0-9a-fA-F-]{36}$")) && token.matches(Regex("^[0-9a-f]{64}$")) && publicKey.isNotBlank() && safeUrl && !uri.host.isNullOrEmpty())
                        val config=JSONObject().put("user_id",user).put("device_id",device).put("device_token",token).put("url",base.trimEnd('/')).put("public_key",publicKey).put("enabled",true)
                        NotificationStore.activate(this,config);NotificationCollectorService.schedule(this);result.success(null)
                    }
                    "syncOwner" -> {
                        val owner=call.argument<String>("userId")
                        if(NotificationStore.owner(this)!=null && NotificationStore.owner(this)!=owner) { NotificationStore.clear(this);WorkManager.getInstance(this).cancelUniqueWork("cashradar-notification-upload") }
                        result.success(null)
                    }
                    "deactivate" -> { NotificationStore.clear(this);WorkManager.getInstance(this).cancelUniqueWork("cashradar-notification-upload");result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (_:Exception) { result.error("notification_error","Could not update notification settings",null) }
        }
    }
}
