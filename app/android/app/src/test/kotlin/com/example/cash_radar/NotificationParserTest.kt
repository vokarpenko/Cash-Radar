package com.example.cash_radar

import org.junit.Assert.*
import org.junit.Test

class NotificationParserTest {
    private val time=1_800_000_000_000L
    @Test fun walletParsesOnlySanitizedFields() {
        val x=NotificationParser.parse(NotificationParser.WALLET,"Synthetic Shop","AMD 1,550.00 with Ameriabank Mastercard Standard ••1111",time)!!
        assertEquals("wallet",x.source);assertEquals("1550.00",x.amount);assertEquals("1111",x.cardLast4);assertEquals("notification",x.timeSource)
    }
    @Test fun ameriaParsesPurchaseAndTreatsCreditSeparately() {
        val x=NotificationParser.parse(NotificationParser.AMERIA,"АРКА транзакции","PURCHASE | 24,100.00 AMD | 5501***1111, | SYNTHETIC MARKET, AM | 17.11.2026 20:54 | BALANCE: 2,575.65 AMD",time)!!
        assertEquals("purchase",x.kind);assertEquals("24100.00",x.amount);assertEquals("SYNTHETIC MARKET, AM",x.merchant);assertEquals("1111",x.cardLast4);assertEquals("bank",x.timeSource)
        val credit=NotificationParser.parse(NotificationParser.AMERIA,"АРКА транзакции","CREDIT ACCOUNT | 5,000.00 AMD | 5501***1111, | SYNTHETIC BANK | 17.11.2026 20:57 | BALANCE: 7,575.65 AMD",time)!!
        assertEquals("credit",credit.kind)
        val hold=NotificationParser.parse(NotificationParser.AMERIA,"АРКА транзакции","PRE-PURCHASE | 3,289.60 AMD | 5501***1111, | SYNTHETIC DELIVERY, AM | 17.11.2026 20:57 | BALANCE: 7,575.65 AMD",time)!!
        assertEquals("pre_purchase",hold.kind)
    }
    @Test fun acbaDistinguishesHoldAndCompletionWithoutMerging() {
        val hold=NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE 19,398.92 AMD 4355***2222, SYNTHETIC DELIVERY, AM 11.11.2026 22:47",time)!!
        val completion=NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE COMPLETION 19,360.59 AMD 4355***2222, SYNTHETIC DELIVERY, AM 11.11.2026 23:28",time)!!
        assertEquals("pre_purchase",hold.kind);assertEquals("pre_purchase_completion",completion.kind);assertNotEquals(hold.amount,completion.amount)
    }
    @Test fun rejectsMessagesOtpUnknownTruncatedAndFullCardNumbers() {
        assertNull(NotificationParser.parse(NotificationParser.WALLET,"Synthetic Shop","DECLINED - AMD 3,289.60 with Ameriabank Mastercard Standard ••1111",time))
        assertNull(NotificationParser.parse("com.google.android.apps.messaging","Synthetic sender","Your OTP for purchase is 123456",time))
        assertNull(NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","OTP 123456 PRE-PURCHASE 10.00 AMD 4355***2222, SYNTHETIC SHOP 11.11.2026 22:47",time))
        assertNull(NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE 10.00 AMD 4355***2222, CODE 123456 11.11.2026 22:47",time))
        assertNull(NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE 10.00 AMD 4355***2222, 1234 5678 9012 3456 11.11.2026 22:47",time))
        assertNull(NotificationParser.parse(NotificationParser.AMERIA,"Исполнено","5,000.00 AMD перевод между своими счетами исполнен",time))
        assertNull(NotificationParser.parse(NotificationParser.AMERIA,"АРКА транзакции","PURCHASE | 1,000",time))
        assertNull(NotificationParser.parse(NotificationParser.ACBA,"ACBA BANK","PRE-PURCHASE 10.00 AMD 4355123412342222, SYNTHETIC SHOP 11.11.2026 22:47",time))
    }
}
