package com.example.cash_radar

import java.math.BigDecimal
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** Strictly parses known transaction layouts. It never returns notification text. */
object NotificationParser {
    const val WALLET = "com.google.android.apps.walletnfcrel"
    const val AMERIA = "com.banqr.ameriabank"
    const val ACBA = "am.acba.ACBA_Mobile"
    val allowedPackages = setOf(WALLET, AMERIA, ACBA)
    private val sensitive = Regex("(?iu)(\\botp\\b|one[ -]?time|pass(?:word|code)|verification code|\\bcode\\b|\\bкод\\b|одноразов|парол)")
    private val currency = "(AMD|RUB|USD|EUR)"
    private val money = "([0-9]{1,3}(?:,[0-9]{3})*(?:\\.[0-9]{1,2})?|[0-9]{1,16}(?:\\.[0-9]{1,2})?)"
    private val maskedCard = "[0-9]{4}\\*{3}([0-9]{4}),?"
    private val bankDate = "([0-9]{2}\\.[0-9]{2}\\.[0-9]{4} [0-9]{2}:[0-9]{2})"
    private val wallet = Regex("(?i)^$currency\\s+$money\\s+with\\s+.{1,120}?(?:mastercard|visa)\\b.{0,100}?[•·*]{1,4}\\s*([0-9]{4})$")
    private val ameria = Regex("(?i)^(PURCHASE|CREDIT ACCOUNT)\\s*\\|\\s*$money\\s+$currency\\s*\\|\\s*$maskedCard\\s*\\|\\s*(.{2,120}?)\\s*\\|\\s*$bankDate(?:\\s*\\|\\s*BALANCE:.*)?$")
    private val acba = Regex("(?i)^(PRE-PURCHASE COMPLETION|PRE-PURCHASE)\\s+$money\\s+$currency\\s+$maskedCard\\s+(.{2,120}?)\\s+$bankDate$")
    data class Event(val source:String, val kind:String, val amount:String, val currency:String, val merchant:String, val cardLast4:String, val occurredAtMillis:Long, val timeSource:String)
    private fun amount(value:String):String? {
        val plain = value.replace(",", "")
        return try {
            val n=BigDecimal(plain)
            if (n.signum()<=0 || n >= BigDecimal("1000000000000000000") || n.scale()>2) null else n.setScale(2).toPlainString()
        } catch (_:NumberFormatException) { null }
    }
    private fun merchant(value:String):String? {
        val x=value.trim().replace(Regex("\\s+")," ")
        if(x.length !in 2..120 || x.count { it in '0'..'9' } >= 8 || Regex("(?i)https?://|www\\.|@").containsMatchIn(x) || sensitive.containsMatchIn(x)) return null
        return x
    }
    private fun date(value:String):Long? = try {
        val format=SimpleDateFormat("dd.MM.yyyy HH:mm",Locale.US)
        format.isLenient=false
        format.parse(value)?.time
    } catch (_:Exception) { null }
    fun parse(packageName:String, title:String?, body:String?, postedAtMillis:Long):Event? {
        if(packageName !in allowedPackages || title == null || body == null || title.length>500 || body.length>2000) return null
        if(sensitive.containsMatchIn(title) || sensitive.containsMatchIn(body)) return null
        val t=title.trim(); val text=body.trim().replace(Regex("\\s+")," ")
        if(postedAtMillis<=0) return null
        return when(packageName) {
            WALLET -> {
                val m=wallet.matchEntire(text) ?: return null
                Event("wallet","purchase",amount(m.groupValues[2]) ?: return null,m.groupValues[1].uppercase(Locale.ROOT),merchant(t) ?: return null,m.groupValues[3],postedAtMillis,"notification")
            }
            AMERIA -> {
                if(!t.equals("АРКА транзакции",true) && !t.equals("ARKA transactions",true)) return null
                val m=ameria.matchEntire(text) ?: return null
                Event("ameria",if(m.groupValues[1].equals("PURCHASE",true)) "purchase" else "credit",amount(m.groupValues[2]) ?: return null,m.groupValues[3].uppercase(Locale.ROOT),merchant(m.groupValues[5]) ?: return null,m.groupValues[4],date(m.groupValues[6]) ?: return null,"bank")
            }
            ACBA -> {
                if(!t.equals("ACBA BANK",true)) return null
                val m=acba.matchEntire(text) ?: return null
                Event("acba",if(m.groupValues[1].equals("PRE-PURCHASE",true)) "pre_purchase" else "pre_purchase_completion",amount(m.groupValues[2]) ?: return null,m.groupValues[3].uppercase(Locale.ROOT),merchant(m.groupValues[5]) ?: return null,m.groupValues[4],date(m.groupValues[6]) ?: return null,"bank")
            }
            else -> null
        }
    }
    fun iso(millis:Long):String = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",Locale.US).apply { timeZone=TimeZone.getTimeZone("UTC") }.format(java.util.Date(millis))
}
