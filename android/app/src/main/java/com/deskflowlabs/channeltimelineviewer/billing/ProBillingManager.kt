package com.deskflowlabs.channeltimelineviewer.billing

import android.app.Activity
import android.content.Context
import android.util.Log
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import com.deskflowlabs.channeltimelineviewer.R
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Google Play Billing の入口。買い切り（One-time product）1つだけを扱う。
 *
 * 方針:
 * - 商品は `pro_unlock` の1つ。**価格はコードに持たない**（Play Console 側で変更できるようにする）
 * - 購入が確認できたら必ず `acknowledge` する（3日以内に確認しないと自動返金になる）
 * - 消費（consume）はしない。買い切りなので所有し続ける
 * - 失敗・キャンセル・保留・復元失敗のどれでも落ちない。UI にメッセージを返すだけ
 *
 * 端末やアカウントの都合で Play に繋がらないことは普通にあるので、
 * 繋がらないこと自体はエラー扱いにせず、購入操作をしたときにだけ知らせる。
 */
class ProBillingManager(
    context: Context,
    private val entitlement: ProEntitlementStore,
) {

    private val appContext = context.applicationContext

    private val _priceText = MutableStateFlow<String?>(null)
    /** 「¥700」のような Play が返す表示用の価格。取れていなければ null。 */
    val priceText: StateFlow<String?> = _priceText.asStateFlow()

    private val _isBusy = MutableStateFlow(false)
    /** 購入・復元の処理中。ボタンの二度押しを止めるために使う。 */
    val isBusy: StateFlow<Boolean> = _isBusy.asStateFlow()

    private val _messageRes = MutableStateFlow<Int?>(null)
    /** 画面に出す一言（購入できた・保留・失敗など）。表示したら [clearMessage]。 */
    val messageRes: StateFlow<Int?> = _messageRes.asStateFlow()

    private var productDetails: ProductDetails? = null
    private var isConnecting = false

    private val client: BillingClient = BillingClient.newBuilder(appContext)
        .setListener { result, purchases -> onPurchasesUpdated(result, purchases) }
        .enablePendingPurchases(
            // 買い切りのみ。コンビニ払いなどの「保留中の購入」を受け取れるようにする。
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        )
        .enableAutoServiceReconnection()
        .build()

    /** アプリ起動時に一度呼ぶ。接続して、購入状態と価格を読み直す。 */
    fun start() = connectThen {
        queryPurchases(reportResult = false)
        queryProductDetails()
    }

    /** 前面に戻ったとき・購入画面を開いたときに呼ぶ。 */
    fun refresh() = connectThen {
        queryPurchases(reportResult = false)
        if (productDetails == null) queryProductDetails()
    }

    /** 「購入を復元」。結果をメッセージで知らせる点だけ [refresh] と違う。 */
    fun restore() {
        _isBusy.value = true
        connectThen(
            onUnavailable = {
                _isBusy.value = false
                _messageRes.value = R.string.pro_error_unavailable
            },
        ) {
            queryPurchases(reportResult = true)
        }
    }

    /** 購入フローを開く。Play に繋がらないときは何もせずメッセージだけ返す。 */
    fun purchase(activity: Activity) {
        if (_isBusy.value) return
        _isBusy.value = true
        connectThen(
            onUnavailable = {
                _isBusy.value = false
                _messageRes.value = R.string.pro_error_unavailable
            },
        ) {
            val details = productDetails
            if (details == null) {
                // 価格が取れていない＝商品が Play Console 側で未公開のことが多い。
                queryProductDetails { fetched ->
                    if (fetched == null) {
                        _isBusy.value = false
                        _messageRes.value = R.string.pro_error_unavailable
                    } else {
                        launchFlow(activity, fetched)
                    }
                }
            } else {
                launchFlow(activity, details)
            }
        }
    }

    fun clearMessage() {
        _messageRes.value = null
    }

    fun dispose() {
        runCatching { client.endConnection() }
    }

    // ---- 以下、内部 ----

    private fun launchFlow(activity: Activity, details: ProductDetails) {
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(
                listOf(
                    BillingFlowParams.ProductDetailsParams.newBuilder()
                        .setProductDetails(details)
                        .build()
                )
            )
            .build()
        val result = runCatching { client.launchBillingFlow(activity, params) }.getOrNull()
        if (result == null || result.responseCode != BillingClient.BillingResponseCode.OK) {
            _isBusy.value = false
            _messageRes.value = R.string.pro_error_failed
        }
        // OK のときは onPurchasesUpdated 側で isBusy を戻す。
    }

    /**
     * 接続できていれば [action]、まだなら繋いでから [action]。
     * 繋がらなければ [onUnavailable]（既定では何もしない）。
     */
    private fun connectThen(onUnavailable: () -> Unit = {}, action: () -> Unit) {
        if (client.isReady) {
            runCatching(action)
            return
        }
        if (isConnecting) return
        isConnecting = true
        runCatching {
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(billingResult: BillingResult) {
                    isConnecting = false
                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                        runCatching(action)
                    } else {
                        Log.w(TAG, "接続できず: ${billingResult.responseCode} ${billingResult.debugMessage}")
                        runCatching(onUnavailable)
                    }
                }

                override fun onBillingServiceDisconnected() {
                    isConnecting = false
                    // enableAutoServiceReconnection() に任せる。
                }
            })
        }.onFailure {
            isConnecting = false
            runCatching(onUnavailable)
        }
    }

    private fun queryProductDetails(onResult: (ProductDetails?) -> Unit = {}) {
        val params = QueryProductDetailsParams.newBuilder()
            .setProductList(
                listOf(
                    QueryProductDetailsParams.Product.newBuilder()
                        .setProductId(PRO_PRODUCT_ID)
                        .setProductType(BillingClient.ProductType.INAPP)
                        .build()
                )
            )
            .build()

        runCatching {
            client.queryProductDetailsAsync(params) { result, details ->
                val found = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    details.productDetailsList.firstOrNull { it.productId == PRO_PRODUCT_ID }
                } else {
                    Log.w(TAG, "商品情報を取れず: ${result.responseCode} ${result.debugMessage}")
                    null
                }
                productDetails = found
                _priceText.value = found?.oneTimePurchaseOfferDetails?.formattedPrice
                runCatching { onResult(found) }
            }
        }.onFailure { runCatching { onResult(null) } }
    }

    /**
     * Play に購入状態を聞く。
     *
     * @param reportResult 「復元しました／購入は見つかりません」を画面に出すか
     */
    private fun queryPurchases(reportResult: Boolean) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()

        runCatching {
            client.queryPurchasesAsync(params) { result, purchases ->
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    // 問い合わせ自体が失敗したときは、いまの Pro 状態を**落とさない**。
                    if (reportResult) {
                        _isBusy.value = false
                        _messageRes.value = R.string.pro_error_unavailable
                    }
                    return@queryPurchasesAsync
                }

                val owned = purchases.filter { it.isProUnlock() }
                owned.forEach { acknowledgeIfNeeded(it) }

                val hasEntitlement = owned.any {
                    it.purchaseState == Purchase.PurchaseState.PURCHASED
                }
                entitlement.applyPlayQuery(hasEntitlement)

                if (reportResult) {
                    _isBusy.value = false
                    _messageRes.value = when {
                        hasEntitlement -> R.string.pro_restore_done
                        owned.any { it.purchaseState == Purchase.PurchaseState.PENDING } ->
                            R.string.pro_pending
                        else -> R.string.pro_restore_none
                    }
                }
            }
        }.onFailure {
            if (reportResult) {
                _isBusy.value = false
                _messageRes.value = R.string.pro_error_unavailable
            }
        }
    }

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        _isBusy.value = false
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val owned = purchases.orEmpty().filter { it.isProUnlock() }
                owned.forEach { acknowledgeIfNeeded(it) }
                when {
                    owned.any { it.purchaseState == Purchase.PurchaseState.PURCHASED } -> {
                        entitlement.grant()
                        _messageRes.value = R.string.pro_owned
                    }
                    owned.any { it.purchaseState == Purchase.PurchaseState.PENDING } ->
                        _messageRes.value = R.string.pro_pending
                }
            }

            BillingClient.BillingResponseCode.USER_CANCELED -> {
                // 本人がやめただけなので何も出さない。
            }

            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                // 復元し損ねている状態。問い合わせ直せば持ち主だと分かる。
                queryPurchases(reportResult = false)
                _messageRes.value = R.string.pro_owned
            }

            BillingClient.BillingResponseCode.SERVICE_DISCONNECTED,
            BillingClient.BillingResponseCode.SERVICE_UNAVAILABLE,
            BillingClient.BillingResponseCode.BILLING_UNAVAILABLE ->
                _messageRes.value = R.string.pro_error_unavailable

            else -> {
                Log.w(TAG, "購入できず: ${result.responseCode} ${result.debugMessage}")
                _messageRes.value = R.string.pro_error_failed
            }
        }
    }

    /**
     * 確認（acknowledge）は**必ず**行う。3日以内に確認しないと Google が自動で返金し、
     * 購入が取り消されてしまう。消費（consume）はしない＝買い切りとして残す。
     */
    private fun acknowledgeIfNeeded(purchase: Purchase) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED) return
        if (purchase.isAcknowledged) return
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        runCatching {
            client.acknowledgePurchase(params) { result ->
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    Log.w(TAG, "確認できず: ${result.responseCode} ${result.debugMessage}")
                }
            }
        }
    }

    private fun Purchase.isProUnlock(): Boolean = PRO_PRODUCT_ID in products

    companion object {
        /** Play Console のアプリ内アイテム（One-time product）のID。 */
        const val PRO_PRODUCT_ID = "pro_unlock"
        private const val TAG = "ProBilling"
    }
}
