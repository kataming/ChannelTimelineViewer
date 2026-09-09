package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import com.deskflowlabs.channeltimelineviewer.data.AnalyticsSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerState
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

/**
 * 利用状況の記録まわり。見るのは次の3点。
 *   1. 送る名前が Firebase の決まり（40文字以内・英数と _・予約語で始まらない）を守っているか
 *   2. **見ているものが漏れていないか**（動画ID・タイトルなどを引数に入れていないか）
 *   3. オプトアウトの設定が保存され、既定はオンか
 */
@RunWith(RobolectricTestRunner::class)
class AnalyticsTest {

    /** 記録された内容を控えるだけの [Analytics]。 */
    private class Recorder : Analytics {
        data class Entry(val name: String, val params: Map<String, Any>)

        val entries = mutableListOf<Entry>()
        var collectionEnabled: Boolean? = null

        override fun setCollectionEnabled(enabled: Boolean) {
            collectionEnabled = enabled
        }

        override fun logScreen(screenName: String) {
            entries += Entry("screen_view", mapOf("screen_name" to screenName))
        }

        override fun log(event: String, vararg params: Pair<String, Any>) {
            entries += Entry(event, params.toMap())
        }

        fun paramsOf(event: String): Map<String, Any> =
            entries.last { it.name == event }.params
    }

    // ---- 1. 名前の決まり ----

    /** Firebase が受け付ける名前か（イベント名・引数名に共通）。 */
    private fun assertValidName(kind: String, name: String) {
        assertTrue(kind + " '" + name + "' は40文字以内にすること", name.length <= 40)
        assertTrue(
            kind + " '" + name + "' は英字で始まり、英数字と _ だけにすること",
            Regex("^[a-zA-Z][a-zA-Z0-9_]*$").matches(name),
        )
        listOf("firebase_", "google_", "ga_").forEach { reserved ->
            assertFalse(
                kind + " '" + name + "' は予約語 '" + reserved + "' で始められない",
                name.startsWith(reserved),
            )
        }
    }

    /** object の中の const val を全部集める（定数を足しても自動で検査される）。 */
    private fun constantsOf(type: Class<*>): List<String> =
        type.declaredFields
            .filter { it.type == String::class.java }
            .map {
                it.isAccessible = true
                it.get(null) as String
            }

    @Test
    fun eventAndParamNamesFollowFirebaseRules() {
        val events = constantsOf(Analytics.Event::class.java)
        assertTrue("イベント名が1つも見つからない", events.isNotEmpty())
        events.forEach { assertValidName("イベント名", it) }
        constantsOf(Analytics.Param::class.java).forEach { assertValidName("引数名", it) }
        assertEquals("イベント名が重複している", events.size, events.toSet().size)
    }

    @Test
    fun paramValuesAreShortEnough() {
        val values = constantsOf(Analytics.Source::class.java) +
            constantsOf(Analytics.Result::class.java) +
            constantsOf(Analytics.Setting::class.java) +
            constantsOf(Analytics.RepeatValue::class.java) +
            constantsOf(Analytics.Screen::class.java)
        assertTrue("引数の値が1つも見つからない", values.isNotEmpty())
        values.forEach {
            assertTrue("引数の値 '" + it + "' は100文字以内にすること", it.length <= 100)
        }
    }

    // ---- 2. 見ているものが漏れていないか ----

    private fun prefs(label: String) =
        ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("test_" + label + "_" + UUID.randomUUID(), Context.MODE_PRIVATE)

    private fun videos(count: Int): List<VideoItem> = (0 until count).map { index ->
        VideoItem(
            id = "secretvideoid" + index,
            title = "秘密のタイトル" + index,
            publishedAtEpochSeconds = index * 86_400L,
            channelId = "UCsecretchannel",
        )
    }

    private fun playerViewModel(
        recorder: Recorder,
        items: List<VideoItem>,
        settings: PlaybackSettingsStore = PlaybackSettingsStore(prefs("settings")),
    ) = PlayerViewModel(
        videos = items,
        startIndex = 0,
        watchStore = WatchHistoryStore(prefs("watch")),
        skipStore = SkippedVideoStore(prefs("skip")),
        positionStore = PlaybackPositionStore(prefs("position")),
        settings = settings,
        analytics = recorder,
    )

    @Test
    fun videoIdsAndTitlesAreNeverRecorded() {
        val recorder = Recorder()
        val items = videos(3)
        val settings = PlaybackSettingsStore(prefs("settings"))
        settings.setAutoPlayNext(true)
        val vm = playerViewModel(recorder, items, settings)

        vm.goNext()
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
        vm.logOpenedInYouTube()

        val forbidden = items.flatMap { listOf(it.id, it.title, it.channelId) }
        val recorded = recorder.entries.flatMap { entry ->
            listOf(entry.name) + entry.params.keys + entry.params.values.map { it.toString() }
        }
        forbidden.forEach { secret ->
            assertFalse(
                "記録に '" + secret + "' が混ざっている",
                recorded.any { it.contains(secret) },
            )
        }
    }

    @Test
    fun firstVideoIsRecordedWithListSizeOnly() {
        val recorder = Recorder()
        playerViewModel(recorder, videos(7))

        val params = recorder.paramsOf(Analytics.Event.VIDEO_OPEN)
        assertEquals(Analytics.Source.LIST, params[Analytics.Param.SOURCE])
        assertEquals(7, params[Analytics.Param.VIDEO_COUNT])
    }

    @Test
    fun autoAdvanceIsRecordedAsAutoNext() {
        val recorder = Recorder()
        val settings = PlaybackSettingsStore(prefs("settings"))
        settings.setAutoPlayNext(true)
        val vm = playerViewModel(recorder, videos(3), settings)
        recorder.entries.clear()

        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)

        assertEquals(
            Analytics.Result.AUTO_NEXT,
            recorder.paramsOf(Analytics.Event.VIDEO_FINISH)[Analytics.Param.RESULT],
        )
        assertEquals(
            Analytics.Source.AUTO_ADVANCE,
            recorder.paramsOf(Analytics.Event.VIDEO_OPEN)[Analytics.Param.SOURCE],
        )
    }

    @Test
    fun repeatModeChangeRecordsOnlyTheMode() {
        val recorder = Recorder()
        val vm = playerViewModel(recorder, videos(2))
        recorder.entries.clear()

        vm.cycleRepeatMode() // Off -> One

        val params = recorder.paramsOf(Analytics.Event.PLAYBACK_SETTING)
        assertEquals(Analytics.Setting.REPEAT, params[Analytics.Param.SETTING])
        assertEquals(Analytics.RepeatValue.ONE, params[Analytics.Param.VALUE])
    }

    @Test
    fun autoPlayStaysOffByDefault() {
        // 記録を足したせいで「勝手にオンになる」ことが起きていないかの念押し。
        val settings = PlaybackSettingsStore(prefs("settings"))
        assertFalse(settings.autoPlayNext.value)
        assertEquals(RepeatMode.Off, settings.repeatMode.value)
    }

    // ---- 3. オプトアウト ----

    @Test
    fun analyticsIsOnByDefaultAndOptOutIsRemembered() {
        val shared = prefs("analytics")
        val store = AnalyticsSettingsStore(shared)
        assertTrue(store.isEnabled.value)

        store.setEnabled(false)
        assertFalse(store.isEnabled.value)
        // 作り直しても切ったままであること（アプリを開き直しても戻らない）。
        assertFalse(AnalyticsSettingsStore(shared).isEnabled.value)
    }

    @Test
    fun noopImplementationDoesNothing() {
        Analytics.Noop.setCollectionEnabled(false)
        Analytics.Noop.logScreen(Analytics.Screen.PLAYER)
        Analytics.Noop.log(Analytics.Event.CHANNEL_OPEN, Analytics.Param.SOURCE to "url")
    }
}
