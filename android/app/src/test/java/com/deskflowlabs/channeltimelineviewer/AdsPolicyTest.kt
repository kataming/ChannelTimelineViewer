package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.activity.ComponentActivity
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.ads.AdVisibilityPolicy
import com.deskflowlabs.channeltimelineviewer.ads.AdsConfig
import com.deskflowlabs.channeltimelineviewer.ads.AdsManager
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner

/**
 * 無料版の広告（AdMob）の約束のテスト。
 *   - Pro は完全に広告なし（同意フォーム・SDK の初期化・広告リクエストのどれもしない）
 *   - 開発中（デバッグビルド）は必ずテスト広告
 *   - 本番 ID が揃っていないリリースは広告を一切出さない
 */
@RunWith(RobolectricTestRunner::class)
class AdsPolicyTest {

    // ---- 判定（AdVisibilityPolicy） ----

    @Test
    fun `Proは広告の準備もリクエストもしない`() {
        assertFalse(AdVisibilityPolicy.shouldPrepare(isPro = true, isConfigured = true))
        assertFalse(
            AdVisibilityPolicy.canRequestAds(
                isPro = true, isConfigured = true, canRequestAds = true, isSdkReady = true,
            )
        )
    }

    @Test
    fun `無料は同意とSDKの準備が済んだときだけリクエストする`() {
        assertTrue(AdVisibilityPolicy.shouldPrepare(isPro = false, isConfigured = true))
        assertTrue(
            AdVisibilityPolicy.canRequestAds(
                isPro = false, isConfigured = true, canRequestAds = true, isSdkReady = true,
            )
        )
        // 同意が得られていない（EEA などで拒否・未回答）
        assertFalse(
            AdVisibilityPolicy.canRequestAds(
                isPro = false, isConfigured = true, canRequestAds = false, isSdkReady = true,
            )
        )
        // SDK の初期化がまだ・失敗した
        assertFalse(
            AdVisibilityPolicy.canRequestAds(
                isPro = false, isConfigured = true, canRequestAds = true, isSdkReady = false,
            )
        )
    }

    @Test
    fun `広告IDが未設定なら無料でも何もしない`() {
        assertFalse(AdVisibilityPolicy.shouldPrepare(isPro = false, isConfigured = false))
        assertFalse(
            AdVisibilityPolicy.canRequestAds(
                isPro = false, isConfigured = false, canRequestAds = true, isSdkReady = true,
            )
        )
    }

    // ---- テスト広告と本番の切り替え（AdsConfig） ----

    @Test
    fun `デバッグビルドは本番IDがあってもテスト広告を使う`() {
        val config = AdsConfig.from(
            isDebug = true,
            bannerUnitId = "ca-app-pub-0000000000000000/1111111111",
            mrecUnitId = "ca-app-pub-0000000000000000/2222222222",
        )
        assertEquals(AdsConfig.TEST, config)
        assertTrue(config.useTestAds)
        assertTrue(config.bannerUnitId.startsWith("ca-app-pub-3940256099942544/"))
        assertTrue(config.mrecUnitId.startsWith("ca-app-pub-3940256099942544/"))
    }

    @Test
    fun `リリースで本番IDが揃っていなければ広告を出さない`() {
        assertFalse(AdsConfig.from(isDebug = false, bannerUnitId = "", mrecUnitId = "").isEnabled)
        assertFalse(
            AdsConfig.from(isDebug = false, bannerUnitId = "ca-app-pub-1/2", mrecUnitId = " ").isEnabled
        )
    }

    @Test
    fun `リリースで本番IDが揃っていれば本番を使う`() {
        val config = AdsConfig.from(
            isDebug = false,
            bannerUnitId = " ca-app-pub-1/2 ",
            mrecUnitId = "ca-app-pub-1/3",
        )
        assertTrue(config.isEnabled)
        assertFalse(config.useTestAds)
        assertEquals("ca-app-pub-1/2", config.bannerUnitId)
    }

    // ---- AdsManager ----

    private fun manager(isPro: MutableStateFlow<Boolean>, config: AdsConfig = AdsConfig.TEST) =
        AdsManager(ApplicationProvider.getApplicationContext<Context>(), config, isPro)

    @Test
    fun `Proなら同意フォームの確認すら始めない`() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        val ads = manager(MutableStateFlow(true))
        ads.prepare(activity)
        assertFalse(ads.consentStarted)
        assertFalse(ads.canShowAds.value)
        assertFalse(ads.privacyOptionsRequired.value)
    }

    @Test
    fun `広告IDが未設定のリリースは同意フォームの確認も始めない`() {
        val activity = Robolectric.buildActivity(ComponentActivity::class.java).setup().get()
        val ads = manager(
            MutableStateFlow(false),
            AdsConfig.from(isDebug = false, bannerUnitId = "", mrecUnitId = ""),
        )
        ads.prepare(activity)
        assertFalse(ads.consentStarted)
        assertFalse(ads.canShowAds.value)
    }

    @Test
    fun `準備前は広告を出さない（読み込みで画面を待たせない）`() {
        assertFalse(manager(MutableStateFlow(false)).canShowAds.value)
    }

    // ---- 計測の区分 ----

    @Test
    fun `無料とProの区分はFirebaseのユーザー属性の決まりを守る`() {
        val name = Analytics.UserProperty.PRO_STATUS
        assertTrue(name.length <= 24)
        assertTrue(Regex("^[a-z][a-z0-9_]*$").matches(name))
        assertEquals("free", Analytics.ProStatus.of(false))
        assertEquals("pro", Analytics.ProStatus.of(true))
    }
}
