package com.deskflowlabs.channeltimelineviewer.billing

import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.Purchase
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics

/**
 * 課金まわりで「何を実売として数えるか」を決める唯一の場所。
 *
 * [ProBillingManager] から Billing SDK の生の型を渡さずここへ集めているのは、
 * **BillingClient を作らずにテストできるようにするため**（BillingClient は実機の
 * Play ストアが要る）。判断の分かれ目をここ1か所に集めてあるので、
 * 「これは売上に数えてよいか？」を読むときはこのファイルだけ見ればよい。
 *
 * 数え方の約束（docs/analytics/CTV_PURCHASE_ANALYTICS.md と同じ）:
 * - 実売 = Play が PURCHASED を返し、対象商品で、Pro 権限を付与した瞬間**だけ**
 * - 保留・キャンセル・失敗・復元・起動時の既購入検出は**実売ではない**
 * - 同じ購入は何度通知されても1回だけ数える（[ReportedPurchaseStore]）
 *
 * ⚠️ Analytics へ出してよいのは「起きた種類」だけ。purchaseToken・orderId・
 *    Play の debugMessage・アカウント情報は**絶対に渡さない**。
 *
 * ⚠️ ここでの失敗が購入や権限付与を壊してはいけないので、外向きの関数はすべて
 *    [safely] で包んである（fail-open）。
 */
class ProPurchaseReporter(
    private val analytics: Analytics,
    private val reported: ReportedPurchaseStore,
) {

    /** 購入に必要な情報だけを写したもの。Billing SDK の型をテストへ持ち込まないための器。 */
    data class PurchaseSnapshot(
        /** 対象商品（pro_unlock）を含む購入か。 */
        val isProUnlock: Boolean,
        /** [Purchase.PurchaseState] の値。 */
        val state: Int,
        /** 重複防止にだけ使う。**Analytics へは出さない。** */
        val purchaseToken: String,
    )

    /** Play が返した商品の値段。取れていなければ null（その場合 GA4 標準イベントは送らない）。 */
    data class PriceInfo(val amountMicros: Long, val currencyCode: String)

    /** 購入ボタンが押され、これからフローを開くところ。 */
    fun purchaseStarted() = safely {
        analytics.log(Analytics.Event.PRO_PURCHASE_START)
    }

    /**
     * 購入フローを開く前に諦めた（Play に繋がらない・商品情報が取れない・
     * launchBillingFlow が OK を返さない）。
     */
    fun purchaseFailedBeforeFlow(reason: String) = safely {
        analytics.log(Analytics.Event.PRO_PURCHASE_ERROR, Analytics.Param.REASON to reason)
    }

    /** 「購入を復元」を押した。**実売ではない。** */
    fun restoreRequested() = safely {
        analytics.log(Analytics.Event.PRO_RESTORE)
    }

    /**
     * Play からの購入結果（`PurchasesUpdatedListener`）を受けて記録する。
     *
     * @param entitlementGranted PURCHASED を見て Pro 権限を実際に付与したか。
     *   false なら（付与が確定していないので）実売として数えない。
     * @return 実売として数えた購入があれば true。テストと呼び出し側の確認用。
     */
    fun purchasesUpdated(
        responseCode: Int,
        purchases: List<PurchaseSnapshot>,
        entitlementGranted: Boolean,
        price: PriceInfo? = null,
    ): Boolean {
        var counted = false
        safely {
            val owned = purchases.filter { it.isProUnlock }
            when (responseCode) {
                BillingClient.BillingResponseCode.OK -> {
                    val purchased = owned.filter { it.state == Purchase.PurchaseState.PURCHASED }
                    when {
                        purchased.isNotEmpty() && entitlementGranted ->
                            counted = countRealSale(purchased, price)

                        // PURCHASED はあるのに権限付与が確定していない＝数えない。
                        // （実際には起きない経路だが、「付与＝実売」の約束をコードでも守る）
                        purchased.isNotEmpty() -> Unit

                        owned.any { it.state == Purchase.PurchaseState.PENDING } ->
                            analytics.log(Analytics.Event.PRO_PURCHASE_PENDING)
                    }
                }

                BillingClient.BillingResponseCode.USER_CANCELED ->
                    analytics.log(Analytics.Event.PRO_PURCHASE_CANCEL)

                // すでに持っている＝この場での購入ではない。復元側で権限が戻るので
                // 失敗でも実売でもない。数えないし、エラーとしても記録しない。
                BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> Unit

                else -> analytics.log(
                    Analytics.Event.PRO_PURCHASE_ERROR,
                    Analytics.Param.REASON to reasonFor(responseCode),
                )
            }
        }
        return counted
    }

    /**
     * 復元や起動時の問い合わせ（`queryPurchasesAsync`）で既に持っていると分かった購入。
     *
     * **実売としては数えない。** ただし「アプリ内で買った瞬間」を一度も見ていない購入
     * （例: 保留がアプリを閉じている間に成立した）を、あとから実売として二重に数えないよう、
     * 数えた印だけは付けておく。
     */
    fun markSeenWithoutCounting(purchases: List<PurchaseSnapshot>) = safely {
        purchases
            .filter { it.isProUnlock && it.state == Purchase.PurchaseState.PURCHASED }
            .forEach { reported.reportOnce(it.purchaseToken) }
    }

    private fun countRealSale(purchased: List<PurchaseSnapshot>, price: PriceInfo?): Boolean {
        // 同じ購入が再通知されても1回だけ。トークンは照合に使うだけで外へは出さない。
        val fresh = purchased.filter { reported.reportOnce(it.purchaseToken) }
        if (fresh.isEmpty()) return false

        analytics.log(Analytics.Event.PRO_PURCHASE_SUCCESS)

        // GA4 標準の収益イベント。値段が取れているときだけ併送する
        // （価格はコードに持たず、Play が返したものだけを使う）。
        if (price != null) {
            analytics.log(
                Analytics.Event.PURCHASE,
                Analytics.Param.VALUE to price.amountMicros / 1_000_000.0,
                Analytics.Param.CURRENCY to price.currencyCode,
            )
        }
        return true
    }

    /** Play の応答コードを、送ってよい決まった文字へ。生のコードや文面は出さない。 */
    fun reasonFor(responseCode: Int): String = when (responseCode) {
        BillingClient.BillingResponseCode.SERVICE_DISCONNECTED,
        BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
        BillingClient.BillingResponseCode.NETWORK_ERROR,
        -> Analytics.ErrorReason.SERVICE_UNAVAILABLE

        BillingClient.BillingResponseCode.BILLING_UNAVAILABLE,
        BillingClient.BillingResponseCode.FEATURE_NOT_SUPPORTED,
        -> Analytics.ErrorReason.BILLING_UNAVAILABLE

        BillingClient.BillingResponseCode.ITEM_UNAVAILABLE ->
            Analytics.ErrorReason.ITEM_UNAVAILABLE

        BillingClient.BillingResponseCode.DEVELOPER_ERROR ->
            Analytics.ErrorReason.DEVELOPER_ERROR

        else -> Analytics.ErrorReason.GENERIC_ERROR
    }

    /**
     * 記録の失敗で購入・権限付与・復元を巻き込まないための蓋（fail-open）。
     * 握りつぶすのは**記録側の例外だけ**で、呼び出し元の処理は続く。
     */
    private inline fun safely(block: () -> Unit) {
        runCatching(block)
    }
}
