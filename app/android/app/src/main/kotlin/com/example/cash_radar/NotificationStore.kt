package com.example.cash_radar

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Device credential and parsed summaries are encrypted with an Android Keystore key. */
object NotificationStore {
    private const val ALIAS = "cashradar.notification.v1"
    private const val PREFS = "cashradar_notification_queue"
    private val lock = Any()
    private fun key():SecretKey {
        val ks=KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing=ks.getKey(ALIAS,null) as? SecretKey
        if(existing!=null)return existing
        val generator=KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(ALIAS,KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }
    private fun encrypt(value:String):String {
        val cipher=Cipher.getInstance("AES/GCM/NoPadding");cipher.init(Cipher.ENCRYPT_MODE,key())
        val result=cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv+result,Base64.NO_WRAP)
    }
    private fun decrypt(value:String):String {
        val all=Base64.decode(value,Base64.NO_WRAP);require(all.size>28)
        val cipher=Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE,key(),GCMParameterSpec(128,all.copyOfRange(0,12)))
        return String(cipher.doFinal(all.copyOfRange(12,all.size)),Charsets.UTF_8)
    }
    private fun read(ctx:Context):JSONObject {
        val raw=ctx.getSharedPreferences(PREFS,Context.MODE_PRIVATE).getString("data",null) ?: return JSONObject()
        return JSONObject(decrypt(raw))
    }
    private fun write(ctx:Context,data:JSONObject) {
        check(ctx.getSharedPreferences(PREFS,Context.MODE_PRIVATE).edit().putString("data",encrypt(data.toString())).commit())
    }
    fun activate(ctx:Context,config:JSONObject) = synchronized(lock) {
        val existing=try { read(ctx) } catch (_:Exception) { JSONObject() }
        val previous=existing.optJSONObject("config")
        val sameOwner=previous?.optString("user_id") == config.optString("user_id")
        val events=if(sameOwner) existing.optJSONArray("events") ?: JSONArray() else JSONArray()
        val installation=if(sameOwner) previous?.optString("installation_id")?.takeIf { it.isNotEmpty() } else null
        config.put("installation_id",installation ?: java.util.UUID.randomUUID().toString())
        write(ctx,JSONObject().put("config",config).put("events",events).put("dropped",if(sameOwner) existing.optInt("dropped",0) else 0))
    }
    fun owner(ctx:Context):String? = synchronized(lock) { try { read(ctx).optJSONObject("config")?.optString("user_id")?.takeIf { it.isNotEmpty() } } catch (_:Exception) { null } }
    fun deviceId(ctx:Context):String? = synchronized(lock) { try { read(ctx).optJSONObject("config")?.optString("device_id")?.takeIf { it.isNotEmpty() } } catch (_:Exception) { null } }
    fun installation(ctx:Context):String? = synchronized(lock) {
        try { val data=read(ctx); val config=data.optJSONObject("config") ?: return@synchronized null
            val existing=config.optString("installation_id").takeIf { it.isNotEmpty() }
            if(existing!=null)return@synchronized existing
            val created=java.util.UUID.randomUUID().toString();config.put("installation_id",created);write(ctx,data);created
        } catch (_:Exception) { null }
    }
    fun enabled(ctx:Context):Boolean = synchronized(lock) { try { read(ctx).optJSONObject("config")?.optBoolean("enabled",false)==true } catch (_:Exception) { false } }
    fun pause(ctx:Context) = synchronized(lock) { try { val d=read(ctx); d.optJSONObject("config")?.put("enabled",false);write(ctx,d) } catch (_:Exception) {} }
    fun clear(ctx:Context) = synchronized(lock) { ctx.getSharedPreferences(PREFS,Context.MODE_PRIVATE).edit().clear().commit() }
    fun append(ctx:Context,event:JSONObject,owner:String,installation:String):Boolean = synchronized(lock) {
        try {
            val d=read(ctx); val config=d.optJSONObject("config") ?: return@synchronized false
            if(!config.optBoolean("enabled",false) || config.optString("user_id")!=owner || config.optString("installation_id")!=installation)return@synchronized false
            val arr=d.optJSONArray("events") ?: JSONArray()
            // Exact repeated callbacks are ignored; two distinct notification keys remain distinct.
            for(i in 0 until arr.length()) if(arr.getJSONObject(i).optString("event_key")==event.optString("event_key")) return@synchronized false
            if(arr.length()>=256) { d.put("dropped",d.optInt("dropped",0)+1);write(ctx,d);return@synchronized false }
            arr.put(event);d.put("events",arr);write(ctx,d);true
        } catch (_:Exception) { false }
    }
    fun first(ctx:Context):Pair<JSONObject,JSONObject>? = synchronized(lock) {
        try { val d=read(ctx);val c=d.optJSONObject("config") ?: return@synchronized null
            if(!c.optBoolean("enabled",false))return@synchronized null
            val arr=d.optJSONArray("events") ?: return@synchronized null
            if(arr.length()==0)null else Pair(JSONObject(c.toString()),JSONObject(arr.getJSONObject(0).toString()))
        } catch (_:Exception) { null }
    }
    fun acknowledge(ctx:Context,eventKey:String) = synchronized(lock) {
        try { val d=read(ctx);val old=d.optJSONArray("events") ?: return@synchronized
            val updated=JSONArray();for(i in 0 until old.length()) { val e=old.getJSONObject(i);if(e.optString("event_key")!=eventKey)updated.put(e) }
            d.put("events",updated);write(ctx,d)
        } catch (_:Exception) {}
    }
    fun contains(ctx:Context,eventKey:String):Boolean = synchronized(lock) {
        try { val arr=read(ctx).optJSONArray("events") ?: return@synchronized false
            (0 until arr.length()).any { arr.getJSONObject(it).optString("event_key")==eventKey }
        } catch (_:Exception) { false }
    }
    fun count(ctx:Context):Int = synchronized(lock) { try { read(ctx).optJSONArray("events")?.length() ?: 0 } catch (_:Exception) { 0 } }
    fun dropped(ctx:Context):Int = synchronized(lock) { try { read(ctx).optInt("dropped",0) } catch (_:Exception) { 0 } }
}
