package com.deskflowlabs.channeltimelineviewer.ads

import android.app.Activity
import android.content.Context
import android.util.Log
import com.google.android.gms.ads.MobileAds
import com.google.android.ump.ConsentDebugSettings
import com.google.android.ump.ConsentInformation
import com.google.android.ump.ConsentRequestParameters
import com.google.android.ump.UserMessagingPlatform
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/**
 * AdMob の準備（広告の同意 → SDK の初期化）と、「いま広告を出してよいか」の窓口。
 *
 * 決めごと:
 * - **Pro は何もしない。** 同意フォームも SDK の初期化も広告リクエストも行わない。
 *   起動時に Pro なら [prepare] は何もせず、無料に戻ったとき（返金など）に初めて準備する。
 *   無料 → Pro になった瞬間に [canShowAds] が false になり、画面側は広告を外して破棄する。
 * - **広告はおまけ。** 同意の確認・初期化・読み込みのどれが失敗しても、例外を外へ出さない。
 *   起動・再生・購入を待たせない（すべて非同期で、終わったら [canShowAds] が変わるだけ）。
 * - 同意（UMP）は広告リクエストより先に確認する。EEA・英国・スイスなど同意が要る地域では
 *   Google の同意フォームが出て、その結果で [canShowAds] が決まる。
 */
class AdsManager(
    context: Context,
    val config: AdsConfig,
    private val isPro: StateFlow<Boolean>,
    scope: CoroutineScope = MainScope(),
) {
    private val appContext = context.applicationContext

    private val canRequestByConsent = MutableStateFlow(false)
    private val isSdkReady = MutableStateFlow(false)
    private val _privacyOptionsRequired = MutableStateFlow(false)

    /** 同意の確認を始めたか（二重に始めない）。Pro では false のまま＝テストで確かめる。 */
    internal var consentStarted = false
        private set
    private var sdkStarted = false

    /** 広告を表示・リクエストしてよいか。画面はこれだけを見る。 */
    val canShowAds: StateFlow<Boolean> =
        combine(isPro, canRequestByConsent, isSdkReady) { pro, consent, ready ->
            AdVisibilityPolicy.canRequestAds(
                isPro = pro,
                isConfigured = config.isEnabled,
                canRequestAds = consent,
                isSdkReady = ready,
            )
        }.stateIn(scope, SharingStarted.Eagerly, false)

    /**
     * 「広告のプライバシー設定」をアプリ内に出す必要があるか（同意が要る地域の人だけ true）。
     * Pro には出さない（広告を出さないので同意も使わない）。
     */
    val privacyOptionsRequired: StateFlow<Boolean> =
        combine(isPro, _privacyOptionsRequired) { pro, required -> !pro && required }
            .stateIn(scope, SharingStarted.Eagerly, false)

    /**
     * 広告の準備を始める。Activity の生成時と、Pro でなくなったときに呼ぶ（何度呼んでもよい）。
     *
     * @param debugGeographyEea デバッグビルドで EEA の同意フォームを試すときだけ true
     * @param resetConsent デバッグビルドで同意をやり直すときだけ true
     */
    fun prepare(activity: Activity, debugGeographyEea: Boolean = false, resetConsent: Boolean = false) {
        if (!AdVisibilityPolicy.shouldPrepare(isPro.value, config.isEnabled)) return
        if (consentStarted) return
        consentStarted = true

        val consentInformation = runCatching {
            UserMessagingPlatform.getConsentInformation(activity)
        }.getOrElse {
            Log.w(TAG, "UMP unavailable; ads stay off.", it)
            return
        }
        if (resetConsent) runCatching { consentInformation.reset() }

        val params = ConsentRequestParameters.Builder().apply {
            if (debugGeographyEea) {
                setConsentDebugSettings(
                    ConsentDebugSettings.Builder(activity)
                        .setDebugGeography(ConsentDebugSettings.DebugGeography.DEBUG_GEOGRAPHY_EEA)
                        .build()
                )
            }
        }.build()

        runCatching {
            consentInformation.requestConsentInfoUpdate(
                activity,
                params,
                {
                    UserMessagingPlatform.loadAndShowConsentFormIfRequired(activity) { formError ->
                        if (formError != null) Log.w(TAG, "Consent form: ${formError.message}")
                        applyConsent(consentInformation)
                    }
                },
                { requestError ->
                    // 通信できない等。前回の同意で広告を出せるならそれを使う（出せないなら出さない）。
                    Log.w(TAG, "Consent info update failed: ${requestError.message}")
                    applyConsent(consentInformation)
                },
            )
        }.onFailure { Log.w(TAG, "Consent request failed; ads stay off.", it) }

        // 前回までに同意が済んでいれば、今回の確認を待たずに準備を進めてよい（Google 推奨）。
        applyConsent(consentInformation)
    }

    /** 「広告のプライバシー設定」（同意の見直し）を開く。 */
    fun showPrivacyOptions(activity: Activity) {
        runCatching {
            UserMessagingPlatform.showPrivacyOptionsForm(activity) { formError ->
                if (formError != null) Log.w(TAG, "Privacy options form: ${formError.message}")
                applyConsent(UserMessagingPlatform.getConsentInformation(activity))
            }
        }.onFailure { Log.w(TAG, "Privacy options form failed.", it) }
    }

    private fun applyConsent(consentInformation: ConsentInformation) {
        runCatching {
            _privacyOptionsRequired.value =
                consentInformation.privacyOptionsRequirementStatus ==
                    ConsentInformation.PrivacyOptionsRequirementStatus.REQUIRED
            val canRequest = consentInformation.canRequestAds()
            canRequestByConsent.value = canRequest
            if (canRequest) initializeSdkOnce()
        }.onFailure { Log.w(TAG, "Failed to read consent state; ads stay off.", it) }
    }

    /** SDK の初期化は1回だけ、メインスレッドの外で行う（起動を待たせない）。 */
    private fun initializeSdkOnce() {
        if (sdkStarted || isPro.value) return
        sdkStarted = true
        CoroutineScopeHolder.io.launch {
            runCatching {
                MobileAds.initialize(appContext) { isSdkReady.value = true }
            }.onFailure {
                Log.w(TAG, "MobileAds.initialize failed; ads stay off.", it)
                sdkStarted = false
            }
        }
    }

    private object CoroutineScopeHolder {
        val io = CoroutineScope(Dispatchers.IO)
    }

    private companion object {
        const val TAG = "Ads"
    }
}
