package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.Purchase
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import com.deskflowlabs.channeltimelineviewer.billing.ProEntitlementStore
import com.deskflowlabs.channeltimelineviewer.billing.ProPurchaseReporter
import com.deskflowlabs.channeltimelineviewer.billing.ReportedPurchaseStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

/**
 * 「実売として数えてよい瞬間」だけ `pro_purchase_success` が出ることのテスト。
 *
 * 売上の数字に直結するので、**数えすぎ（水増し）と数え落とし**の両方を見る。
 * BillingClient は実機の Play ストアが要るため作れない。判断は
 * [ProPurchaseReporter] に切り出してあるので、そこを直接叩いて確かめる。
 */
@RunWith(RobolectricTestRunner::class)
class ProPurchaseAnalyticsTest {

    /** 記録された内容を控えるだけの [Analytics]。 */
    private class Recorder : Analytics {
        data class Entry(val name: String, val params: Map<String, Any>)

        val entries = mutableListOf<Entry>()

        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) {
            entries += Entry(event, params.toMap())
        }

        fun count(event: String) = entries.count { it.name == event }
        fun names() = entries.map { it.name }
        fun paramsOf(event: String) = entries.last { it.name == event }.params
    }

    /** 送信のたびに必ず落ちる [Analytics]。fail-open の確認に使う。 */
    private class ExplodingAnalytics : Analytics {
        override fun setCollectionEnabled(enabled: Boolean) = error("記録は壊れている")
        override fun logScreen(screenName: String) = error("記録は壊れている")
        override fun log(event: String, vararg params: Pair<String, Any>): Unit =
            error("記録は壊れている")
    }

    private fun prefs(label: String) =
        ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("purchase_" + label + "_" + UUID.randomUUID(), Context.MODE_PRIVATE)

    private fun store() = ReportedPurchaseStore(prefs("reported"))

    private fun purchased(token: String = "token-1") = ProPurchaseReporter.PurchaseSnapshot(
        isProUnlock = true,
        state = Purchase.PurchaseState.PURCHASED,
        purchaseToken = token,
    )

    private fun pending(token: String = "token-pending") = ProPurchaseReporter.PurchaseSnapshot(
        isProUnlock = true,
        state = Purchase.PurchaseState.PENDING,
        purchaseToken = token,
    )

    private val success = Analytics.Event.PRO_PURCHASE_SUCCESS

    // ---- 1. 購入成功 ----

    @Test
    fun `購入が成立したら success が1回だけ出る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchaseStarted()
        val counted = reporter.purchasesUpdated(
            responseCode = BillingClient.BillingResponseCode.OK,
            purchases = listOf(purchased()),
            entitlementGranted = true,
        )

        assertTrue("実売として数えられるべき", counted)
        assertEquals(1, recorder.count(Analytics.Event.PRO_PURCHASE_START))
        assertEquals(1, recorder.count(success))
        assertEquals(0, recorder.count(Analytics.Event.PRO_PURCHASE_CANCEL))
        assertEquals(0, recorder.count(Analytics.Event.PRO_PURCHASE_ERROR))
    }

    @Test
    fun `購入開始と購入成功は別のイベントになっている`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchaseStarted()
        assertEquals("開始しただけで売れてはいない", 0, recorder.count(success))

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased()), entitlementGranted = true,
        )
        assertEquals(
            listOf(Analytics.Event.PRO_PURCHASE_START, success),
            recorder.names(),
        )
    }

    @Test
    fun `権限付与が確定していなければ success は出ない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        val counted = reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased()), entitlementGranted = false,
        )

        assertFalse(counted)
        assertEquals(0, recorder.count(success))
    }

    @Test
    fun `対象商品でなければ success は出ない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())
        val other = ProPurchaseReporter.PurchaseSnapshot(
            isProUnlock = false,
            state = Purchase.PurchaseState.PURCHASED,
            purchaseToken = "token-other",
        )

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(other), entitlementGranted = true,
        )

        assertEquals(0, recorder.count(success))
    }

    // ---- 2. キャンセル ----

    @Test
    fun `本人がやめたら cancel だけが出る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.USER_CANCELED, emptyList(), entitlementGranted = false,
        )

        assertEquals(1, recorder.count(Analytics.Event.PRO_PURCHASE_CANCEL))
        assertEquals(0, recorder.count(success))
        assertEquals("キャンセルはエラーではない", 0, recorder.count(Analytics.Event.PRO_PURCHASE_ERROR))
    }

    // ---- 3. エラー ----

    @Test
    fun `Billing エラーでは error だけが出る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.ERROR, emptyList(), entitlementGranted = false,
        )

        assertEquals(1, recorder.count(Analytics.Event.PRO_PURCHASE_ERROR))
        assertEquals(0, recorder.count(success))
        assertEquals(0, recorder.count(Analytics.Event.PRO_PURCHASE_CANCEL))
    }

    @Test
    fun `エラーの理由は決まった短い文字だけを送る`() {
        val allowed = setOf(
            Analytics.ErrorReason.SERVICE_UNAVAILABLE,
            Analytics.ErrorReason.BILLING_UNAVAILABLE,
            Analytics.ErrorReason.ITEM_UNAVAILABLE,
            Analytics.ErrorReason.DEVELOPER_ERROR,
            Analytics.ErrorReason.GENERIC_ERROR,
        )
        val codes = listOf(
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE,
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE,
            BillingClient.BillingResponseCode.DEVELOPER_ERROR,
            BillingClient.BillingResponseCode.ERROR,
            BillingClient.BillingResponseCode.ITEM_NOT_OWNED,
            BillingClient.BillingResponseCode.NETWORK_ERROR,
        )

        codes.forEach { code ->
            val recorder = Recorder()
            val reporter = ProPurchaseReporter(recorder, store())
            reporter.purchasesUpdated(code, emptyList(), entitlementGranted = false)

            val reason = recorder.paramsOf(Analytics.Event.PRO_PURCHASE_ERROR)[Analytics.Param.REASON]
            assertTrue("応答コード " + code + " の理由 '" + reason + "' は許可外", reason in allowed)
        }
    }

    @Test
    fun `応答コードや Play の文面そのものは送らない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.DEVELOPER_ERROR, emptyList(), entitlementGranted = false,
        )

        val sent = recorder.entries.flatMap { it.params.values.map(Any::toString) }
        sent.forEach {
            assertFalse("数値の応答コードを送ってはいけない", it.toIntOrNull() != null)
        }
        assertEquals(
            Analytics.ErrorReason.DEVELOPER_ERROR,
            recorder.paramsOf(Analytics.Event.PRO_PURCHASE_ERROR)[Analytics.Param.REASON],
        )
    }

    // ---- 4. 保留 ----

    @Test
    fun `保留では success を出さず pending を出す`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        val counted = reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(pending()), entitlementGranted = false,
        )

        assertFalse("保留はまだ売れていない", counted)
        assertEquals(0, recorder.count(success))
        assertEquals(1, recorder.count(Analytics.Event.PRO_PURCHASE_PENDING))
    }

    // ---- 5. 復元 ----

    @Test
    fun `復元では restore だけが出る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.restoreRequested()

        assertEquals(1, recorder.count(Analytics.Event.PRO_RESTORE))
        assertEquals(0, recorder.count(success))
    }

    // ---- 6. 起動時の既購入検出 ----

    @Test
    fun `起動時に既購入を見つけても success は出ない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.markSeenWithoutCounting(listOf(purchased()))

        assertEquals(0, recorder.count(success))
        assertTrue("記録は何も出ないはず", recorder.entries.isEmpty())
    }

    @Test
    fun `起動時に見た購入は後から実売として数え直されない`() {
        val recorder = Recorder()
        val shared = store()
        val reporter = ProPurchaseReporter(recorder, shared)

        // 起動時の問い合わせで既に持っていると分かった購入。
        reporter.markSeenWithoutCounting(listOf(purchased("token-restored")))
        // そのあと Play が同じ購入を再通知してきても、新しい売上ではない。
        val counted = reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK,
            listOf(purchased("token-restored")),
            entitlementGranted = true,
        )

        assertFalse(counted)
        assertEquals(0, recorder.count(success))
    }

    // ---- 7. 同一購入の再通知 ----

    @Test
    fun `同じ購入が何度通知されても success は1回だけ`() {
        val recorder = Recorder()
        val shared = store()
        val reporter = ProPurchaseReporter(recorder, shared)

        repeat(5) {
            reporter.purchasesUpdated(
                BillingClient.BillingResponseCode.OK,
                listOf(purchased("token-same")),
                entitlementGranted = true,
            )
        }

        assertEquals(1, recorder.count(success))
    }

    @Test
    fun `アプリを作り直しても同じ購入は数え直されない`() {
        val recorder = Recorder()
        val samePrefs = prefs("across_restart")

        // 1回目の起動。
        ProPurchaseReporter(recorder, ReportedPurchaseStore(samePrefs)).purchasesUpdated(
            BillingClient.BillingResponseCode.OK,
            listOf(purchased("token-restart")),
            entitlementGranted = true,
        )
        // 作り直し（プロセス再起動に相当）。控えは端末に残っている。
        ProPurchaseReporter(recorder, ReportedPurchaseStore(samePrefs)).purchasesUpdated(
            BillingClient.BillingResponseCode.OK,
            listOf(purchased("token-restart")),
            entitlementGranted = true,
        )

        assertEquals(1, recorder.count(success))
    }

    @Test
    fun `返金後に買い直した別の購入はもう一度数える`() {
        val recorder = Recorder()
        val shared = store()
        val reporter = ProPurchaseReporter(recorder, shared)

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased("token-first")),
            entitlementGranted = true,
        )
        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased("token-second")),
            entitlementGranted = true,
        )

        assertEquals("別の購入なので2件とも実売", 2, recorder.count(success))
    }

    // ---- 8. 記録が壊れても購入は壊れない（fail-open） ----

    @Test
    fun `記録が失敗しても実売判定の呼び出しは落ちない`() {
        val reporter = ProPurchaseReporter(ExplodingAnalytics(), store())

        // どれも例外を投げないこと自体が確認内容。
        reporter.purchaseStarted()
        reporter.restoreRequested()
        reporter.purchaseFailedBeforeFlow(Analytics.ErrorReason.GENERIC_ERROR)
        reporter.markSeenWithoutCounting(listOf(purchased("token-boom")))
        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased("token-boom-2")),
            entitlementGranted = true,
        )
    }

    @Test
    fun `記録が失敗しても Pro 権限は付与される`() {
        // 実際の順番（権限を先に確定し、記録はそのあと）を写したもの。
        val entitlement = ProEntitlementStore(prefs("entitlement"))
        val reporter = ProPurchaseReporter(ExplodingAnalytics(), store())

        entitlement.grant()
        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased()), entitlementGranted = true,
        )

        assertTrue("記録の失敗で Pro が消えてはいけない", entitlement.isPro.value)
    }

    // ---- 送ってはいけないもの ----

    @Test
    fun `purchaseToken は記録に出ない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())
        val secret = "SECRET-PURCHASE-TOKEN-0123456789"

        reporter.purchaseStarted()
        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased(secret)),
            entitlementGranted = true,
            price = ProPurchaseReporter.PriceInfo(amountMicros = 4_990_000, currencyCode = "JPY"),
        )
        reporter.markSeenWithoutCounting(listOf(purchased(secret)))

        val everything = recorder.entries.flatMap {
            listOf(it.name) + it.params.keys + it.params.values.map(Any::toString)
        }
        everything.forEach {
            assertFalse("記録に purchaseToken が混ざっている: " + it, it.contains(secret))
            assertFalse("ハッシュ化したトークンも送ってはいけない", it.length == 64 && it.all(Char::isLetterOrDigit))
        }
    }

    // ---- GA4 標準の purchase ----

    @Test
    fun `値段が取れていれば GA4 標準の purchase も実売と同時に出る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased()),
            entitlementGranted = true,
            price = ProPurchaseReporter.PriceInfo(amountMicros = 4_990_000, currencyCode = "JPY"),
        )

        assertEquals(1, recorder.count(Analytics.Event.PURCHASE))
        val params = recorder.paramsOf(Analytics.Event.PURCHASE)
        assertEquals(4.99, params[Analytics.Param.VALUE] as Double, 0.0001)
        assertEquals("JPY", params[Analytics.Param.CURRENCY])
    }

    @Test
    fun `値段が取れていなければ GA4 標準の purchase は送らない`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())

        reporter.purchasesUpdated(
            BillingClient.BillingResponseCode.OK, listOf(purchased()),
            entitlementGranted = true,
            price = null,
        )

        assertEquals("実売そのものは数える", 1, recorder.count(success))
        assertEquals("金額が不確かなら収益イベントは出さない", 0, recorder.count(Analytics.Event.PURCHASE))
    }

    @Test
    fun `GA4 標準の purchase も同じ購入では1回だけ`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, store())
        val price = ProPurchaseReporter.PriceInfo(amountMicros = 4_990_000, currencyCode = "JPY")

        repeat(3) {
            reporter.purchasesUpdated(
                BillingClient.BillingResponseCode.OK, listOf(purchased("token-ga4")),
                entitlementGranted = true, price = price,
            )
        }

        assertEquals(1, recorder.count(Analytics.Event.PURCHASE))
        assertEquals(1, recorder.count(success))
    }

    // ---- 重複防止の入れ物そのもの ----

    @Test
    fun `控えは同じトークンを一度しか受け付けない`() {
        val store = store()
        assertTrue(store.reportOnce("token-a"))
        assertFalse(store.reportOnce("token-a"))
        assertTrue(store.isReported("token-a"))
        assertFalse(store.isReported("token-b"))
    }

    @Test
    fun `空のトークンは数えない`() {
        val store = store()
        assertFalse(store.reportOnce(""))
        assertFalse(store.isReported(""))
    }
}
