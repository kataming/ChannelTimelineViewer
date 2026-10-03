package com.deskflowlabs.channeltimelineviewer.ads

/**
 * 広告を出してよいか（＝広告リクエストを送ってよいか）の判定。判断はここ1か所だけで行う。
 *
 * ⚠️ **Pro は完全に広告なし。** 画面で隠すだけでなく、SDK の初期化・同意フォーム・
 * 広告リクエストのどれも行わない。Pro かどうかの正は既存の ProEntitlementStore で、
 * 広告側はそれを読むだけ（課金側のロジックには手を入れない）。
 */
object AdVisibilityPolicy {

    /**
     * 広告まわりの準備（同意の確認・SDK の初期化）を始めてよいか。
     * Pro には同意フォームも出さない（広告を出さない人に広告の同意を求めない）。
     */
    fun shouldPrepare(isPro: Boolean, isConfigured: Boolean): Boolean =
        !isPro && isConfigured

    /**
     * 広告リクエストを送ってよいか。
     *
     * @param canRequestAds UMP が「広告をリクエストしてよい」と判定したか
     *   （同意が要らない地域なら true、要る地域では同意フォームの結果次第）
     * @param isSdkReady MobileAds の初期化が終わったか
     */
    fun canRequestAds(
        isPro: Boolean,
        isConfigured: Boolean,
        canRequestAds: Boolean,
        isSdkReady: Boolean,
    ): Boolean = shouldPrepare(isPro, isConfigured) && canRequestAds && isSdkReady
}
