package com.deskflowlabs.channeltimelineviewer.billing

import android.app.Activity
import android.content.Context
import android.os.Handler
import android.os.Looper
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
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
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
    analytics: Analytics = Analytics.Noop,
    reportedPurchases: ReportedPurchaseStore,
    private val cancelSurvey: CancelSurveyStore? = null,
) {

    private val appContext = context.applicationContext

    /**
     * 「何を実売として数えるか」の判断はすべて [ProPurchaseReporter] に置いてある。
     * この manager は Play とのやり取りに集中し、数え方の分岐は持たない。
     */
    private val reporter = ProPurchaseReporter(analytics, reportedPurchases)

    private val _priceText = MutableStateFlow<String?>(null)
    /** 「¥700」のような Play が返す表示用の価格。取れていなければ null。 */
    val priceText: StateFlow<String?> = _priceText.asStateFlow()

    private val _isBusy = MutableStateFlow(false)
    /** 購入・復元の処理中。ボタンの二度押しを止めるために使う。 */
    val isBusy: StateFlow<Boolean> = _isBusy.asStateFlow()

    private val _messageRes = MutableStateFlow<Int?>(null)
    /** 画面に出す一言（購入できた・保留・失敗など）。表示したら [clearMessage]。 */
    val messageRes: StateFlow<Int?> = _messageRes.asStateFlow()

    private val _cancelSurveyVisible = MutableStateFlow(false)
    /** 購入をやめた直後の一問アンケートを出すか（7 日に 1 回まで）。 */
    val cancelSurveyVisible: StateFlow<Boolean> = _cancelSurveyVisible.asStateFlow()

    private var productDetails: ProductDetails? = null

    /** 直近の接続の応答コード。購入時に繋がらなかった理由を記録するためだけに使う。 */
    @Volatile
    private var lastConnectCode: Int? = null

    /**
     * いま表示していて、購入にも使うオファー。**表示と購入で必ず同じものを使う**ため、
     * 価格・通貨・offerToken をひとつにまとめて持つ（[OfferSelection]）。
     */
    private var selectedOffer: OfferSelection.SelectedOffer? = null

    private val client: BillingClient = BillingClient.newBuilder(appContext)
        .setListener { result, purchases -> onPurchasesUpdated(result, purchases) }
        .enablePendingPurchases(
            // 買い切りのみ。コンビニ払いなどの「保留中の購入」を受け取れるようにする。
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        )
        .enableAutoServiceReconnection()
        .build()

    /**
     * 接続待ちの受け付け口。預けた依頼は必ず実行か [ConnectionGate] の onUnavailable に行き着く。
     * （接続中に購入ボタンを押すと何も起きず `isBusy` が戻らなかった不具合の対策）
     */
    private val mainHandler = Handler(Looper.getMainLooper())

    private val gate = ConnectionGate(
        isReady = { client.isReady },
        startConnection = { onFinished ->
            // 前回の接続の応答コードを、今回繋がらなかった理由として使わないように消しておく。
            lastConnectCode = null
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(billingResult: BillingResult) {
                    val ok = billingResult.responseCode == BillingClient.BillingResponseCode.OK
                    lastConnectCode = billingResult.responseCode
                    if (!ok) {
                        Log.w(TAG, "接続できず: ${billingResult.responseCode} ${billingResult.debugMessage}")
                    }
                    reporter.billingResult(
                        Analytics.Stage.CONNECT,
                        reporter.outcomeFor(billingResult.responseCode),
                        billingResult.responseCode,
                    )
                    onFinished(ok)
                }

                override fun onBillingServiceDisconnected() {
                    // 再接続は enableAutoServiceReconnection() に任せる。
                    // ただし**接続の途中で切れた**ときは onBillingSetupFinished が来ないことがあるので、
                    // 待っている依頼を「繋がらなかった」として片付ける。接続済みのあとで切れた場合は
                    // ConnectionGate が古い接続の結果として捨てる（依頼が二重に実行されない）。
                    onFinished(false)
                }
            })
        },
        // 接続の返事がいつまでも来ないときも、並んでいる購入依頼を片付ける（isBusy を残さない）。
        scheduleTimeout = { delay, block -> mainHandler.postDelayed(block, delay) },
        onTimeout = {
            Log.w(TAG, "接続の返事が時間内に来なかった")
            reporter.billingResult(Analytics.Stage.CONNECT, Analytics.BillingOutcome.TIMEOUT)
        },
    )

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
        reporter.restoreRequested()
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
        reporter.purchaseStarted()
        _isBusy.value = true
        connectThen(
            onUnavailable = {
                _isBusy.value = false
                // 購入ボタンを押したのに Play へ繋がらなかった＝購入の失敗として数える。
                // 理由は接続の応答コードから決める（以前は常に service_unavailable で、
                // 「その端末では課金が使えない」なども区別できなかった）。
                val code = lastConnectCode?.takeIf { it != BillingClient.BillingResponseCode.OK }
                reporter.purchaseFailedBeforeFlow(
                    code?.let(reporter::reasonFor) ?: Analytics.ErrorReason.SERVICE_UNAVAILABLE,
                    Analytics.ErrorStage.BILLING_CONNECT,
                    code,
                )
                _messageRes.value = R.string.pro_error_unavailable
            },
        ) {
            // ここで何が起きても `isBusy` を残さない（残すと画面が操作できなくなる）。
            val started = runCatching {
                val details = productDetails
                if (details == null) {
                    // 価格が取れていない＝商品が Play Console 側で未公開のことが多い。
                    queryProductDetails { fetched, code ->
                        if (fetched == null) {
                            _isBusy.value = false
                            // 応答が OK なのに商品が無い＝未公開など（item_unavailable）。
                            // 応答自体が失敗なら、そのコードの理由にする（以前は常に item_unavailable だった）。
                            val failed = code?.takeIf { it != BillingClient.BillingResponseCode.OK }
                            reporter.purchaseFailedBeforeFlow(
                                failed?.let(reporter::reasonFor) ?: Analytics.ErrorReason.ITEM_UNAVAILABLE,
                                Analytics.ErrorStage.PRODUCT_QUERY,
                                code,
                            )
                            _messageRes.value = R.string.pro_error_unavailable
                        } else {
                            // ⚠️ ここは Play からの呼び戻しの中なので、外側の runCatching では拾えない。
                            //    例外を握りつぶすと isBusy が戻らず、どのイベントも出ない（2026-10-02 修正）。
                            runCatching { launchFlow(activity, fetched) }
                                .onFailure { failBeforeLaunch() }
                        }
                    }
                } else {
                    launchFlow(activity, details)
                }
            }
            if (started.isFailure) failBeforeLaunch()
        }
    }

    /** 購入画面を開く前に例外で止まった。応答コードは無いので送らない。 */
    private fun failBeforeLaunch() {
        _isBusy.value = false
        reporter.purchaseFailedBeforeFlow(Analytics.ErrorReason.GENERIC_ERROR, Analytics.ErrorStage.LAUNCH_BILLING)
        reporter.billingResult(Analytics.Stage.LAUNCH, Analytics.BillingOutcome.EXCEPTION)
        _messageRes.value = R.string.pro_error_failed
    }

    fun clearMessage() {
        _messageRes.value = null
    }

    /** アンケートに答えた（閉じたときは [Analytics.CancelReason.DISMISSED]）。 */
    fun answerCancelSurvey(choice: String) {
        _cancelSurveyVisible.value = false
        reporter.cancelReason(choice)
    }

    fun dispose() {
        runCatching { client.endConnection() }
    }

    // ---- 以下、内部 ----

    private fun launchFlow(activity: Activity, details: ProductDetails) {
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .apply {
                // 割引特典（1回限りのアイテムのオファー）は、**選んだオファーのトークンを
                // 渡したときだけ**適用される。渡さないと通常価格での購入になる。
                // 旧環境（オファー一覧が無い）ではトークンが null なので、従来どおり渡さない。
                selectedOffer?.offerToken?.takeIf { it.isNotBlank() }?.let { setOfferToken(it) }
            }
            .build()
        val params = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
            .build()
        val result = runCatching { client.launchBillingFlow(activity, params) }.getOrNull()
        if (result == null) {
            // launchBillingFlow 自体が例外を投げた。応答コードは無い。
            failBeforeLaunch()
            return
        }
        val code = result.responseCode
        reporter.billingResult(Analytics.Stage.LAUNCH, reporter.outcomeFor(code), code)
        if (code == BillingClient.BillingResponseCode.OK) return // isBusy は onPurchasesUpdated 側で戻す。

        // 画面が開けなかった。この先 onPurchasesUpdated は呼ばれないので、ここで片付けて数える。
        _isBusy.value = false
        Log.w(TAG, "購入画面を開けず: $code ${result.debugMessage}")
        // USER_CANCELED は cancel だけ、ITEM_ALREADY_OWNED は item_already_owned のエラー（判断は reporter）。
        reporter.launchNotStarted(code)
        _messageRes.value = when (code) {
            BillingClient.BillingResponseCode.USER_CANCELED -> null
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                // 復元し損ねている状態（購入画面のあとに届く場合と同じ扱い）。問い直せば権限が戻る。
                // 以前はここで「購入できませんでした」を出していた。
                queryPurchases(reportResult = false, logDiagnostics = true)
                R.string.pro_owned
            }
            else -> R.string.pro_error_failed
        }
    }

    /**
     * 接続できていれば [action]、まだなら繋いでから [action]。
     * 繋がらなければ [onUnavailable]（既定では何もしない）。
     *
     * ⚠️ 接続中に来た依頼も**必ずどちらかが呼ばれる**（[ConnectionGate]）。
     *    ここで黙って帰ると `isBusy` が戻らず、画面が操作できなくなる。
     */
    private fun connectThen(onUnavailable: () -> Unit = {}, action: () -> Unit) {
        gate.run(onUnavailable = onUnavailable, action = action)
    }

    /** [onResult] は (商品, Play の応答コード)。例外で問い合わせられなかったときはコードが null。 */
    private fun queryProductDetails(onResult: (ProductDetails?, Int?) -> Unit = { _, _ -> }) {
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
                // ⚠️ ここで例外が出ても onResult は必ず呼ぶ（呼ばないと購入中の isBusy が戻らない）。
                val handled = runCatching {
                    val found = if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                        details.productDetailsList.firstOrNull { it.productId == PRO_PRODUCT_ID }
                    } else {
                        Log.w(TAG, "商品情報を取れず: ${result.responseCode} ${result.debugMessage}")
                        null
                    }
                    productDetails = found
                    // 表示する価格は、このあと購入に使うオファーそのものの価格にする。
                    selectedOffer = found?.selectOffer()
                    _priceText.value = selectedOffer?.formattedPrice
                    found
                }
                val found = handled.getOrNull()
                reporter.billingResult(
                    Analytics.Stage.QUERY_PRODUCT,
                    when {
                        handled.isFailure -> Analytics.BillingOutcome.EXCEPTION
                        result.responseCode != BillingClient.BillingResponseCode.OK ->
                            reporter.outcomeFor(result.responseCode)
                        // 応答は OK なのに商品が入っていない＝Play Console 側で未公開など。
                        found == null -> Analytics.BillingOutcome.ITEM_UNAVAILABLE
                        else -> Analytics.BillingOutcome.OK
                    },
                    result.responseCode,
                )
                runCatching { onResult(found, result.responseCode) }
            }
        }.onFailure {
            reporter.billingResult(Analytics.Stage.QUERY_PRODUCT, Analytics.BillingOutcome.EXCEPTION)
            runCatching { onResult(null, null) }
        }
    }

    /**
     * Play に購入状態を聞く。
     *
     * @param reportResult 「復元しました／購入は見つかりません」を画面に出すか
     * @param logDiagnostics 成功も `pro_billing_result` に残すか。起動・前面復帰のたびに
     *   記録しないよう、既定は「復元のときだけ」。失敗はいつでも残す
     */
    private fun queryPurchases(reportResult: Boolean, logDiagnostics: Boolean = reportResult) {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.INAPP)
            .build()

        runCatching {
            client.queryPurchasesAsync(params) { result, purchases ->
                if (result.responseCode != BillingClient.BillingResponseCode.OK) {
                    reporter.billingResult(
                        Analytics.Stage.QUERY_PURCHASES,
                        reporter.outcomeFor(result.responseCode),
                        result.responseCode,
                    )
                    // 問い合わせ自体が失敗したときは、いまの Pro 状態を**落とさない**。
                    if (reportResult) failQueryPurchases()
                    return@queryPurchasesAsync
                }
                // ⚠️ 中で例外が出ても、復元中の isBusy は必ず戻す。
                runCatching { applyQueriedPurchases(purchases, reportResult, logDiagnostics) }
                    .onFailure {
                        reporter.billingResult(Analytics.Stage.QUERY_PURCHASES, Analytics.BillingOutcome.EXCEPTION)
                        if (reportResult) failQueryPurchases()
                    }
            }
        }.onFailure {
            reporter.billingResult(Analytics.Stage.QUERY_PURCHASES, Analytics.BillingOutcome.EXCEPTION)
            if (reportResult) failQueryPurchases()
        }
    }

    private fun failQueryPurchases() {
        _isBusy.value = false
        _messageRes.value = R.string.pro_error_unavailable
    }

    private fun applyQueriedPurchases(purchases: List<Purchase>, reportResult: Boolean, logDiagnostics: Boolean) {
        val owned = purchases.filter { it.isProUnlock() }
        owned.forEach { acknowledgeIfNeeded(it) }

        val hasEntitlement = owned.any {
            it.purchaseState == Purchase.PurchaseState.PURCHASED
        }
        entitlement.applyPlayQuery(hasEntitlement)

        // ここは復元・起動時の問い合わせ。**実売としては数えない。**
        // ただし「数えた印」だけは付けておく。そうしないと、アプリを閉じている間に
        // 成立した購入を、次に Play が再通知したときへ持ち越して二重に数えてしまう。
        reporter.markSeenWithoutCounting(owned.map { it.toSnapshot() })

        if (logDiagnostics) {
            reporter.billingResult(
                Analytics.Stage.QUERY_PURCHASES,
                reporter.purchaseCallbackOutcome(
                    BillingClient.BillingResponseCode.OK,
                    purchases.map { it.toSnapshot() },
                ),
                BillingClient.BillingResponseCode.OK,
            )
        }

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

    private fun onPurchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        _isBusy.value = false

        // 診断用。成功も失敗も、購入が空で戻ってきた場合も同じ形で残す。
        // 一覧は null と空を区別して渡す（OK なのに null／空、を見分けるため）。
        reporter.billingResult(
            Analytics.Stage.PURCHASE_CALLBACK,
            runCatching {
                reporter.purchaseCallbackOutcome(
                    responseCode = result.responseCode,
                    purchases = purchases?.map { it.toSnapshot() },
                )
            }.getOrDefault(Analytics.BillingOutcome.EXCEPTION),
            result.responseCode,
        )

        // 先に権限とメッセージ（＝利用者にとっての本筋）を確定させ、記録はそのあと。
        // こうしておけば記録側で何が起きても購入の扱いは変わらない。
        var entitlementGranted = false
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> {
                val owned = purchases.orEmpty().filter { it.isProUnlock() }
                owned.forEach { acknowledgeIfNeeded(it) }
                when {
                    owned.any { it.purchaseState == Purchase.PurchaseState.PURCHASED } -> {
                        entitlement.grant()
                        entitlementGranted = true
                        _messageRes.value = R.string.pro_owned
                    }
                    owned.any { it.purchaseState == Purchase.PurchaseState.PENDING } ->
                        _messageRes.value = R.string.pro_pending
                }
            }

            BillingClient.BillingResponseCode.USER_CANCELED -> {
                // 本人がやめただけなのでエラーは出さない。理由だけ一度聞く（7 日に 1 回まで）。
                if (runCatching { cancelSurvey?.tryAsk() == true }.getOrDefault(false)) {
                    _cancelSurveyVisible.value = true
                }
            }

            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                // 復元し損ねている状態。問い合わせ直せば持ち主だと分かる。
                // 問い直しの結果も診断に残す（所有が本当に見つかった＝ok か、見つからない＝empty 等か）。
                queryPurchases(reportResult = false, logDiagnostics = true)
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

        reporter.purchasesUpdated(
            responseCode = result.responseCode,
            purchases = purchases.orEmpty().map { it.toSnapshot() },
            entitlementGranted = entitlementGranted,
            price = currentPrice(),
        )
    }

    /**
     * Play が返した値段。取れていなければ null（GA4 標準の購入イベントは送られない）。
     *
     * **実際に購入したオファーの金額**を使う。割引で買われたときに通常価格を記録すると、
     * 売上が実際より高く出てしまうため。
     */
    private fun currentPrice(): ProPurchaseReporter.PriceInfo? =
        selectedOffer?.let {
            ProPurchaseReporter.PriceInfo(
                amountMicros = it.priceAmountMicros,
                currencyCode = it.priceCurrencyCode,
            )
        }

    /**
     * Play が返したオファーの中から、表示と購入に使う1つを選ぶ。
     *
     * 割引特典（1回限りのアイテムのオファー）は `getOneTimePurchaseOfferDetailsList()` にしか
     * 現れない。**対象かどうかの判断は Play 側**で、対象の人にだけ割引オファーが返る
     * （アプリに国コードを持たない）。判断そのものは [OfferSelection]。
     */
    private fun ProductDetails.selectOffer(): OfferSelection.SelectedOffer? = OfferSelection.select(
        candidates = oneTimePurchaseOfferDetailsList?.map { it.toCandidate() }.orEmpty(),
        fallback = oneTimePurchaseOfferDetails?.toCandidate(),
    )

    private fun ProductDetails.OneTimePurchaseOfferDetails.toCandidate() = OfferSelection.Candidate(
        offerToken = offerToken,
        formattedPrice = formattedPrice,
        priceAmountMicros = priceAmountMicros,
        priceCurrencyCode = priceCurrencyCode,
        offerId = offerId,
        purchaseOptionId = purchaseOptionId,
        // 割引特典かどうかは「割引の表示情報があるか」で見分ける。
        isDiscount = discountDisplayInfo != null,
        // レンタル・予約は pro_unlock では使わない。間違って選ばないよう印を付ける。
        isRental = rentalDetails != null,
        isPreorder = preorderDetails != null,
    )

    private fun Purchase.toSnapshot() = ProPurchaseReporter.PurchaseSnapshot(
        isProUnlock = isProUnlock(),
        state = purchaseState,
        purchaseToken = purchaseToken,
    )

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
                reporter.billingResult(
                    Analytics.Stage.ACKNOWLEDGE,
                    reporter.outcomeFor(result.responseCode),
                    result.responseCode,
                )
            }
        }.onFailure {
            reporter.billingResult(Analytics.Stage.ACKNOWLEDGE, Analytics.BillingOutcome.EXCEPTION)
        }
    }

    private fun Purchase.isProUnlock(): Boolean = PRO_PRODUCT_ID in products

    companion object {
        /** Play Console のアプリ内アイテム（One-time product）のID。 */
        const val PRO_PRODUCT_ID = "pro_unlock"
        private const val TAG = "ProBilling"
    }
}
