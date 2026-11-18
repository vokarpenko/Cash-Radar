package com.example.cash_radar

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.provider.Settings
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.util.UUID

/** Synthetic data only. Run against an explicitly activated local Supabase device. */
@RunWith(AndroidJUnit4::class)
class NotificationDeliveryTest {
    @Test fun systemSettingsReceivesStringComponentName() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val intent = NotificationAccess.settingsIntent(context)
        if (Build.VERSION.SDK_INT >= 30) assertEquals(ComponentName(context, NotificationCollectorService::class.java).flattenToString(), intent.getStringExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME))
        else assertEquals(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS, intent.action)
    }

    @Test fun syntheticEventsReachLocalBackendAndDuplicatesRemainSafe() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        assertTrue("Enable Android notification access first", NotificationAccess.isGranted(context))
        assertTrue("Enable collection in CashRadar first", NotificationStore.enabled(context))
        val owner = requireNotNull(NotificationStore.owner(context))
        val installation = requireNotNull(NotificationStore.installation(context))
        // Inspect the existing test-device config without printing any credentials.
        val read = NotificationStore::class.java.getDeclaredMethod("read", Context::class.java).apply { isAccessible = true }
        val config = (read.invoke(NotificationStore, context) as JSONObject).getJSONObject("config")
        val url = URI(config.getString("url"))
        assertTrue("This test only runs against local Supabase over USB or emulator", url.scheme == "http" && url.host in setOf("127.0.0.1", "localhost", "10.0.2.2") && url.port == 54321)
        val token = config.getString("device_token")
        val publicKey = config.getString("public_key")
        val now = System.currentTimeMillis()
        val run = UUID.randomUUID().toString()
        data class Example(val pkg: String, val title: String, val body: String, val kind: String, val amount: String)
        val examples = listOf(
            Example(NotificationParser.WALLET, "CASHRADAR TEST WALLET", "AMD 1,550.00 with Ameriabank Mastercard Standard ••1111", "purchase", "1550.00"),
            Example(NotificationParser.AMERIA, "АРКА транзакции", "PURCHASE | 4,400.00 AMD | 5501***1111, | CASHRADAR TEST AMERIA | 01.01.2020 12:30 | BALANCE: 2,575.65 AMD", "purchase", "4400.00"),
            Example(NotificationParser.AMERIA, "АРКА транзакции", "PRE-PURCHASE | 3,289.60 AMD | 5501***1111, | CASHRADAR TEST DELIVERY, AM | 01.01.2020 12:30 | BALANCE: 7,575.65 AMD", "pre_purchase", "3289.60"),
            Example(NotificationParser.AMERIA, "АРКА транзакции", "CREDIT ACCOUNT | 5,000.00 AMD | 5501***1111, | CASHRADAR TEST CREDIT | 01.01.2020 12:30 | BALANCE: 7,575.65 AMD", "credit", "5000.00"),
            Example(NotificationParser.ACBA, "ACBA BANK", "PRE-PURCHASE 19,398.92 AMD 4355***2222, CASHRADAR TEST DELIVERY 01.01.2020 12:30", "pre_purchase", "19398.92"),
            Example(NotificationParser.ACBA, "ACBA BANK", "PRE-PURCHASE COMPLETION 19,360.59 AMD 4355***2222, CASHRADAR TEST DELIVERY 01.01.2020 13:30", "pre_purchase_completion", "19360.59"),
        )
        val ids = mutableSetOf<String>()
        fun deliver(example: Example, key: String): Pair<String, NotificationParser.Event> {
            val event = requireNotNull(NotificationParser.parse(example.pkg, example.title, example.body, now))
            assertEquals(example.kind, event.kind)
            assertEquals(example.amount, event.amount)
            assertNull("A different user must not capture the event", NotificationCollectorService.enqueue(context, example.pkg, key, now, event, "00000000-0000-4000-8000-000000000000", installation))
            val eventKey = requireNotNull(NotificationCollectorService.enqueue(context, example.pkg, key, now, event, owner, installation))
            val deadline = System.currentTimeMillis() + 60000
            while (System.currentTimeMillis() < deadline && NotificationStore.contains(context, eventKey)) Thread.sleep(250)
            assertFalse("Upload timed out for ${example.kind}", NotificationStore.contains(context, eventKey))
            return eventKey to event
        }
        fun verifyUploaded(key: String, event: NotificationParser.Event): String {
            val payload = JSONObject().put("event_key", key).put("source", event.source).put("kind", event.kind)
                .put("amount", event.amount).put("currency", event.currency).put("merchant", event.merchant)
                .put("card_last4", event.cardLast4).put("occurred_at", NotificationParser.iso(event.occurredAtMillis)).put("time_source", event.timeSource)
            val conn = URL("$url/rest/v1/rpc/ingest_notification_event").openConnection() as HttpURLConnection
            try {
                conn.requestMethod = "POST"; conn.connectTimeout = 15000; conn.readTimeout = 15000; conn.doOutput = true
                conn.setRequestProperty("Content-Type", "application/json"); conn.setRequestProperty("apikey", publicKey)
                if (publicKey.startsWith("eyJ")) conn.setRequestProperty("Authorization", "Bearer $publicKey")
                conn.outputStream.use { it.write(JSONObject().put("p_device_token", token).put("p_event", payload).toString().toByteArray()) }
                assertEquals("Local backend must accept duplicate", 200, conn.responseCode)
                val response = JSONObject(conn.inputStream.bufferedReader().use { it.readText() })
                assertTrue("Worker must already have uploaded this event", response.getBoolean("duplicate"))
                return response.getString("id")
            } finally { conn.disconnect() }
        }
        examples.forEachIndexed { index, example ->
            val notificationKey = "cashradar-test-$run-$index"
            val (eventKey, event) = deliver(example, notificationKey)
            val id = verifyUploaded(eventKey, event)
            assertTrue("Different events must remain separate", ids.add(id))
            // The same callback after a successful upload must resolve to the same backend record.
            val (repeatedKey, repeated) = deliver(example, notificationKey)
            assertEquals(eventKey, repeatedKey)
            assertEquals(id, verifyUploaded(repeatedKey, repeated))
        }
        // Two separate notifications with identical contents are not silently combined.
        val (otherKey, otherEvent) = deliver(examples.first(), "cashradar-test-$run-distinct")
        assertTrue(ids.add(verifyUploaded(otherKey, otherEvent)))
        val encrypted = context.getSharedPreferences("cashradar_notification_queue", Context.MODE_PRIVATE).getString("data", "") ?: ""
        assertFalse(encrypted.contains("CASHRADAR TEST")); assertFalse(encrypted.contains(token))

        assertNull(NotificationParser.parse("com.google.android.apps.messaging", "Sender", "OTP 123456", now))
        assertNull(NotificationParser.parse(NotificationParser.WALLET, "CASHRADAR TEST DELIVERY", "DECLINED - AMD 3,289.60 with Ameriabank Mastercard Standard ••1111", now))
        assertNull(NotificationParser.parse(NotificationParser.ACBA, "ACBA BANK", "OTP 123456 PRE-PURCHASE 10 AMD 4355***2222, CASHRADAR TEST 01.01.2020 12:30", now))
        assertNull(NotificationParser.parse(NotificationParser.ACBA, "ACBA BANK", "PRE-PURCHASE 10 AMD 4355123412342222, CASHRADAR TEST 01.01.2020 12:30", now))
        assertNull(NotificationParser.parse(NotificationParser.AMERIA, "Исполнено", "Перевод между своими счетами", now))
        assertNull(NotificationParser.parse(NotificationParser.AMERIA, "АРКА транзакции", "PURCHASE | 1,000", now))
    }
}
