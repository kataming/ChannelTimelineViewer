package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.Purchase
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
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
 * 課金の診断イベント `pro_billing_result` のテスト（2026-09-21）。
 *
 * 「購入画面までは出ているのに誰も買っていない」を切り分けるための記録。
 * **実売の数え方（`pro_purchase_success`）には関わらない**ので、ここでは
 *   1. どの応答コードがどの言葉になるか
 *   2. これまで記録の無かった形（OK なのに購入が空・すでに所有）も残ること
 *   3. 送ってはいけないもの（購入トークン等）が混ざらないこと
 * を見る。
 */
@RunWith(RobolectricTestRunner::class)
class ProBillingDiagnosticsTest {

    private class Recorder : Analytics {
        data class Entry(val name: String, val params: Map<String, Any>)

        val entries = mutableListOf<Entry>()

        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) {
            entries += Entry(event, params.toMap())
        }

        fun diagnostics() = entries.filter { it.name == Analytics.Event.PRO_BILLING_RESULT }
        fun dump() = entries.joinToString { it.name + it.params.toString() }
    }

    private fun reporter(recorder: Recorder): ProPurchaseReporter {
        val prefs = ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("diag_" + UUID.randomUUID(), Context.MODE_PRIVATE)
        return ProPurchaseReporter(recorder, ReportedPurchaseStore(prefs))
    }

    private fun snapshot(
        state: Int = Purchase.PurchaseState.PURCHASED,
        isProUnlock: Boolean = true,
        token: String = SECRET_TOKEN,
    ) = ProPurchaseReporter.PurchaseSnapshot(isProUnlock = isProUnlock, state = state, purchaseToken = token)

    // ---- 1. 応答コードの言い換え ----

    @Suppress("DEPRECATION") // SERVICE_TIMEOUT（非推奨）も言い換えの対象に含める。
    @Test
    fun everyKnownResponseCodeHasItsOwnWord() {
        val reporter = reporter(Recorder())
        val expected = mapOf(
            BillingClient.BillingResponseCode.OK to Analytics.BillingOutcome.OK,
            BillingClient.BillingResponseCode.USER_CANCELED to Analytics.BillingOutcome.USER_CANCELED,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE to Analytics.BillingOutcome.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.SERVICE_TIMEOUT to Analytics.BillingOutcome.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED to Analytics.BillingOutcome.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.NETWORK_ERROR to Analytics.BillingOutcome.NETWORK_ERROR,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE to Analytics.BillingOutcome.BILLING_UNAVAILABLE,
            BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED to Analytics.BillingOutcome.FEATURE_NOT_SUPPORTED,
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE to Analytics.BillingOutcome.ITEM_UNAVAILABLE,
            BillingClient.BillingResponseCode.DEVELOPER_ERROR to Analytics.BillingOutcome.DEVELOPER_ERROR,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED to Analytics.BillingOutcome.ITEM_ALREADY_OWNED,
            BillingClient.BillingResponseCode.ITEM_NOT_OWNED to Analytics.BillingOutcome.ITEM_NOT_OWNED,
            BillingClient.BillingResponseCode.ERROR to Analytics.BillingOutcome.ERROR,
        )
        expected.forEach { (code, word) ->
            assertEquals("応答コード " + code, word, reporter.outcomeFor(code))
        }
        assertEquals(Analytics.BillingOutcome.UNKNOWN, reporter.outcomeFor(9999))
    }

    // ---- 2. 購入画面のあとの結果 ----

    @Test
    fun purchasedIsOk() {
        val reporter = reporter(Recorder())
        assertEquals(
            Analytics.BillingOutcome.OK,
            reporter.purchaseCallbackOutcome(BillingClient.BillingResponseCode.OK, listOf(snapshot())),
        )
    }

    @Test
    fun pendingIsPending() {
        val reporter = reporter(Recorder())
        assertEquals(
            Analytics.BillingOutcome.PENDING,
            reporter.purchaseCallbackOutcome(
                BillingClient.BillingResponseCode.OK,
                listOf(snapshot(state = Purchase.PurchaseState.PENDING)),
            ),
        )
    }

    /** これまで記録が無かった形。「成功なのに購入が1件も入っていない」。 */
    @Test
    fun okWithEmptyPurchaseListIsVisibleNow() {
        val reporter = reporter(Recorder())
        assertEquals(
            Analytics.BillingOutcome.EMPTY_PURCHASE_LIST,
            reporter.purchaseCallbackOutcome(BillingClient.BillingResponseCode.OK, emptyList()),
        )
    }

    /** 2026-10-03〜: OK のまま購入が届かない形を、null／空／対象外／状態不明に分けて残す。 */
    @Test
    fun okWithoutPurchaseIsSplitByShape() {
        val reporter = reporter(Recorder())
        val ok = BillingClient.BillingResponseCode.OK
        assertEquals(Analytics.BillingOutcome.NULL_PURCHASE_LIST, reporter.purchaseCallbackOutcome(ok, null))
        assertEquals(Analytics.BillingOutcome.EMPTY_PURCHASE_LIST, reporter.purchaseCallbackOutcome(ok, emptyList()))
        assertEquals(
            Analytics.BillingOutcome.NO_PRO_ITEM,
            reporter.purchaseCallbackOutcome(ok, listOf(snapshot(isProUnlock = false))),
        )
        assertEquals(
            Analytics.BillingOutcome.UNSPECIFIED_STATE,
            reporter.purchaseCallbackOutcome(ok, listOf(snapshot(state = Purchase.PurchaseState.UNSPECIFIED_STATE))),
        )
        // 失敗のコードなら、一覧が null でもそのコードの言葉のまま。
        assertEquals(
            Analytics.BillingOutcome.ITEM_ALREADY_OWNED,
            reporter.purchaseCallbackOutcome(BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED, null),
        )
    }

    @Test
    fun failuresKeepTheirOwnWords() {
        val reporter = reporter(Recorder())
        val cases = listOf(
            BillingClient.BillingResponseCode.USER_CANCELED to Analytics.BillingOutcome.USER_CANCELED,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED to Analytics.BillingOutcome.ITEM_ALREADY_OWNED,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE to Analytics.BillingOutcome.BILLING_UNAVAILABLE,
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE to Analytics.BillingOutcome.ITEM_UNAVAILABLE,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE to Analytics.BillingOutcome.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED to Analytics.BillingOutcome.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.NETWORK_ERROR to Analytics.BillingOutcome.NETWORK_ERROR,
            BillingClient.BillingResponseCode.DEVELOPER_ERROR to Analytics.BillingOutcome.DEVELOPER_ERROR,
            9999 to Analytics.BillingOutcome.UNKNOWN,
        )
        cases.forEach { (code, word) ->
            assertEquals(
                "応答コード " + code,
                word,
                // 購入が入っていても、失敗のコードなら失敗のまま。
                reporter.purchaseCallbackOutcome(code, listOf(snapshot())),
            )
        }
    }

    // ---- 3. 記録の形と、送ってはいけないもの ----

    @Test
    fun diagnosticEventCarriesOnlyStageCategoryAndCode() {
        val recorder = Recorder()
        reporter(recorder).billingResult(
            Analytics.Stage.LAUNCH,
            Analytics.BillingOutcome.BILLING_UNAVAILABLE,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE,
        )
        assertEquals(
            mapOf(
                Analytics.Param.STAGE to Analytics.Stage.LAUNCH,
                Analytics.Param.CATEGORY to Analytics.BillingOutcome.BILLING_UNAVAILABLE,
                // 2026-10-02 までの版と並べて見るため、result にも同じ値を残す。
                Analytics.Param.RESULT to Analytics.BillingOutcome.BILLING_UNAVAILABLE,
                Analytics.Param.BILLING_RESPONSE_CODE to BillingClient.BillingResponseCode.BILLING_UNAVAILABLE,
            ),
            recorder.diagnostics().single().params,
        )
    }

    /** 例外・時間切れでは応答コードが無い。推測の値を入れずにコードごと送らない。 */
    @Test
    fun diagnosticEventOmitsCodeWhenThereIsNone() {
        val recorder = Recorder()
        reporter(recorder).billingResult(Analytics.Stage.CONNECT, Analytics.BillingOutcome.TIMEOUT)
        val params = recorder.diagnostics().single().params
        assertEquals(Analytics.BillingOutcome.TIMEOUT, params[Analytics.Param.CATEGORY])
        assertFalse(Analytics.Param.BILLING_RESPONSE_CODE in params)
    }

    /** 段階・分類の値はすべて決まった短い文字（GA4 の制限内・英小文字と _ だけ）。 */
    @Test
    fun stageAndCategoryValuesAreFixedShortWords() {
        val words = listOf(
            Analytics.Stage.CONNECT, Analytics.Stage.QUERY_PRODUCT, Analytics.Stage.LAUNCH,
            Analytics.Stage.PURCHASE_CALLBACK, Analytics.Stage.ACKNOWLEDGE, Analytics.Stage.QUERY_PURCHASES,
            Analytics.BillingOutcome.NULL_PURCHASE_LIST, Analytics.BillingOutcome.EMPTY_PURCHASE_LIST,
            Analytics.BillingOutcome.NO_PRO_ITEM, Analytics.BillingOutcome.UNSPECIFIED_STATE,
            Analytics.BillingOutcome.EXCEPTION, Analytics.BillingOutcome.TIMEOUT,
            Analytics.ErrorReason.ITEM_ALREADY_OWNED, Analytics.ErrorReason.OK_WITHOUT_PURCHASE,
        )
        words.forEach { assertTrue(it, Regex("^[a-z][a-z_]{1,39}$").matches(it)) }
    }

    @Test
    fun purchaseTokenNeverReachesAnalytics() {
        val recorder = Recorder()
        val reporter = reporter(recorder)
        val purchases = listOf(snapshot(), snapshot(state = Purchase.PurchaseState.PENDING, token = "$SECRET_TOKEN-2"))

        reporter.purchaseStarted()
        listOf(
            BillingClient.BillingResponseCode.OK,
            BillingClient.BillingResponseCode.USER_CANCELED,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED,
            BillingClient.BillingResponseCode.ERROR,
        ).forEach { code ->
            reporter.billingResult(
                Analytics.Stage.PURCHASE_CALLBACK,
                reporter.purchaseCallbackOutcome(code, purchases),
            )
            reporter.purchasesUpdated(
                responseCode = code,
                purchases = purchases,
                entitlementGranted = code == BillingClient.BillingResponseCode.OK,
                price = ProPurchaseReporter.PriceInfo(amountMicros = 700_000_000, currencyCode = "JPY"),
            )
        }

        val dump = recorder.dump()
        assertFalse("購入トークンは送らない", dump.contains(SECRET_TOKEN))
        assertFalse("トークンという語も出さない", dump.contains("purchaseToken"))
        assertTrue("診断は記録されている", recorder.diagnostics().isNotEmpty())
        // 手動の in_app_purchase は送らない（自動収集と二重に数えないため）。
        assertFalse(recorder.entries.any { it.name == "in_app_purchase" })
    }

    /** 既存イベントの意味を変えていないこと（診断を足しても実売の数は変わらない）。 */
    @Test
    fun diagnosticsDoNotChangeHowSalesAreCounted() {
        val recorder = Recorder()
        val reporter = reporter(recorder)
        val purchases = listOf(snapshot())

        reporter.billingResult(Analytics.Stage.PURCHASE_CALLBACK, Analytics.BillingOutcome.OK)
        reporter.purchasesUpdated(
            responseCode = BillingClient.BillingResponseCode.OK,
            purchases = purchases,
            entitlementGranted = true,
        )
        // 同じ購入が再通知されても、実売は1回だけ。
        reporter.billingResult(Analytics.Stage.PURCHASE_CALLBACK, Analytics.BillingOutcome.OK)
        reporter.purchasesUpdated(
            responseCode = BillingClient.BillingResponseCode.OK,
            purchases = purchases,
            entitlementGranted = true,
        )

        assertEquals(1, recorder.entries.count { it.name == Analytics.Event.PRO_PURCHASE_SUCCESS })
        assertEquals(2, recorder.diagnostics().size)
    }

    @Test
    fun cancelIsStillOnlyForUserCanceled() {
        val recorder = Recorder()
        val reporter = reporter(recorder)
        listOf(
            BillingClient.BillingResponseCode.ERROR,
            BillingClient.BillingResponseCode.ITEM_UNAVAILABLE,
            BillingClient.BillingResponseCode.NETWORK_ERROR,
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED,
        ).forEach { code ->
            reporter.purchasesUpdated(responseCode = code, purchases = emptyList(), entitlementGranted = false)
        }
        assertEquals(0, recorder.entries.count { it.name == Analytics.Event.PRO_PURCHASE_CANCEL })

        reporter.purchasesUpdated(
            responseCode = BillingClient.BillingResponseCode.USER_CANCELED,
            purchases = emptyList(),
            entitlementGranted = false,
        )
        assertEquals(1, recorder.entries.count { it.name == Analytics.Event.PRO_PURCHASE_CANCEL })
    }

    private companion object {
        /** 本物に似せた、記録に出てはいけない値。 */
        const val SECRET_TOKEN = "opaque.AO-J1Ox-must-never-be-logged"
    }
}
