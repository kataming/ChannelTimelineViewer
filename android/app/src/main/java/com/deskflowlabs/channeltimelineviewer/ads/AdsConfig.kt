package com.deskflowlabs.channeltimelineviewer.ads

import com.deskflowlabs.channeltimelineviewer.BuildConfig

/**
 * どの広告ユニットを使うか（テスト広告か本番か）。
 *
 * - デバッグビルド: **常に Google 公式のテスト広告**。本番 ID が設定されていても使わない
 *   （開発中に自分で本番広告を表示・クリックしないため）
 * - リリースビルド: build.gradle.kts の `ADMOB_*` が揃っていれば本番。
 *   1つでも欠けていれば [isEnabled] が false になり、SDK の初期化も広告リクエストもしない
 *
 * アプリ ID（AndroidManifest の APPLICATION_ID）は build.gradle.kts 側で同じ規則で切り替えている。
 */
data class AdsConfig(
    val bannerUnitId: String,
    val mrecUnitId: String,
    val useTestAds: Boolean,
) {
    /** 広告ユニットが揃っているか。false なら広告まわりは何もしない。 */
    val isEnabled: Boolean get() = bannerUnitId.isNotBlank() && mrecUnitId.isNotBlank()

    companion object {
        /** Google 公式のテスト用アダプティブバナー（Android）。 */
        const val TEST_ADAPTIVE_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/9214589741"

        /** Google 公式のテスト用バナー（Android）。MREC（300×250）もこのユニットで出す。 */
        const val TEST_BANNER_UNIT_ID = "ca-app-pub-3940256099942544/6300978111"

        val TEST = AdsConfig(
            bannerUnitId = TEST_ADAPTIVE_BANNER_UNIT_ID,
            mrecUnitId = TEST_BANNER_UNIT_ID,
            useTestAds = true,
        )

        fun from(
            isDebug: Boolean = BuildConfig.DEBUG,
            bannerUnitId: String = BuildConfig.ADMOB_BANNER_UNIT_ID,
            mrecUnitId: String = BuildConfig.ADMOB_MREC_UNIT_ID,
        ): AdsConfig =
            if (isDebug) {
                TEST
            } else {
                AdsConfig(
                    bannerUnitId = bannerUnitId.trim(),
                    mrecUnitId = mrecUnitId.trim(),
                    useTestAds = false,
                )
            }
    }
}
