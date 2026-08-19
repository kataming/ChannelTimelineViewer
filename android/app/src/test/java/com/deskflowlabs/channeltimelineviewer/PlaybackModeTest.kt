package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerCommand
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerState
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

/**
 * iOS 版 `Tests/PlaybackModeTests.swift` と同じ観点。
 * リピート・スキップ・未視聴のみ再生の判断が2つのアプリでずれないようにする。
 */
@RunWith(RobolectricTestRunner::class)
class PlaybackModeTest {

    private fun prefs(label: String) =
        ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("test_${label}_${UUID.randomUUID()}", Context.MODE_PRIVATE)

    private fun videos(count: Int): List<VideoItem> = (0 until count).map { index ->
        VideoItem(
            id = "video$index",
            title = "第${index + 1}回",
            publishedAtEpochSeconds = index * 86_400L,
            channelId = "UCtest",
        )
    }

    private class Fixture(
        val vm: PlayerViewModel,
        val videos: List<VideoItem>,
        val watch: WatchHistoryStore,
        val skip: SkippedVideoStore,
        val settings: PlaybackSettingsStore,
    )

    private fun fixture(count: Int = 5, startIndex: Int = 0): Fixture {
        val items = videos(count)
        val watch = WatchHistoryStore(prefs("watch"))
        val skip = SkippedVideoStore(prefs("skip"))
        val settings = PlaybackSettingsStore(prefs("settings"))
        val vm = PlayerViewModel(
            videos = items,
            startIndex = startIndex,
            watchStore = watch,
            skipStore = skip,
            positionStore = PlaybackPositionStore(prefs("pos")),
            settings = settings,
        )
        return Fixture(vm, items, watch, skip, settings)
    }

    private fun playThrough(vm: PlayerViewModel) {
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
    }

    // MARK: - 既定値

    @Test
    fun newSettingsDefaults() {
        val settings = PlaybackSettingsStore(prefs("settings"))
        assertEquals(RepeatMode.Off, settings.repeatMode.value)
        assertFalse(settings.playUnwatchedOnly.value)
        assertFalse("自動再生は既定オフ", settings.autoPlayNext.value)
        assertTrue("続きから再生は既定オン", settings.resumeFromLastPosition.value)
    }

    @Test
    fun repeatModeCyclesThroughAllStates() {
        assertEquals(RepeatMode.One, RepeatMode.Off.next)
        assertEquals(RepeatMode.All, RepeatMode.One.next)
        assertEquals(RepeatMode.Off, RepeatMode.All.next)
    }

    @Test
    fun repeatModeBadgeAppearance() {
        assertFalse(RepeatMode.Off.isActive)
        assertTrue(RepeatMode.One.isActive)
        assertTrue(RepeatMode.All.isActive)
        assertNull(RepeatMode.Off.centerLabel)
        assertEquals("1", RepeatMode.One.centerLabel)
        assertEquals("ALL", RepeatMode.All.centerLabel)
    }

    // MARK: - リピート

    @Test
    fun repeatOneReplaysSameVideo() {
        val f = fixture()
        f.settings.setRepeatMode(RepeatMode.One)
        f.settings.setAutoPlayNext(false)

        playThrough(f.vm)

        assertEquals(0, f.vm.currentIndex.value)
        assertTrue(f.vm.command.value is PlayerCommand.Replay)
        assertFalse(f.vm.showEndedSuggestion.value)
    }

    @Test
    fun repeatOneKeepsRepeating() {
        val f = fixture()
        f.settings.setRepeatMode(RepeatMode.One)

        playThrough(f.vm)
        val first = f.vm.command.value?.id
        playThrough(f.vm)

        assertEquals(0, f.vm.currentIndex.value)
        assertTrue(f.vm.command.value is PlayerCommand.Replay)
        assertTrue("毎回あらためて再生し直す", first != f.vm.command.value?.id)
    }

    @Test
    fun repeatAllWrapsToFirstVideo() {
        val f = fixture(count = 3, startIndex = 2)
        f.settings.setAutoPlayNext(true)
        f.settings.setRepeatMode(RepeatMode.All)

        playThrough(f.vm)

        assertEquals(0, f.vm.currentIndex.value)
        assertTrue(f.vm.didAutoAdvance.value)
    }

    @Test
    fun stopsAtLastVideoWithoutRepeat() {
        val f = fixture(count = 3, startIndex = 2)
        f.settings.setAutoPlayNext(true)
        f.settings.setRepeatMode(RepeatMode.Off)

        playThrough(f.vm)

        assertEquals(2, f.vm.currentIndex.value)
        assertFalse(f.vm.showEndedSuggestion.value)
    }

    // MARK: - スキップ

    @Test
    fun skipStoreBasics() {
        val store = SkippedVideoStore(prefs("skip"))
        assertFalse(store.isSkipped("v1"))
        store.toggleSkipped("v1")
        assertTrue(store.isSkipped("v1"))
        assertEquals(1, store.skippedCount)
        store.toggleSkipped("v1")
        assertFalse(store.isSkipped("v1"))
    }

    @Test
    fun autoAdvanceSkipsSkippedVideos() {
        val f = fixture(count = 5)
        f.settings.setAutoPlayNext(true)
        f.skip.markSkipped(f.videos[1].id)
        f.skip.markSkipped(f.videos[2].id)

        playThrough(f.vm)

        assertEquals("スキップ2本を飛ばして4本目へ", 3, f.vm.currentIndex.value)
        assertFalse("飛ばした動画は視聴済みにしない", f.watch.isWatched(f.videos[1].id))
    }

    @Test
    fun stopsWhenOnlySkippedVideosRemain() {
        val f = fixture(count = 3)
        f.settings.setAutoPlayNext(true)
        f.skip.markSkipped(f.videos[1].id)
        f.skip.markSkipped(f.videos[2].id)

        playThrough(f.vm)

        assertEquals(0, f.vm.currentIndex.value)
    }

    @Test
    fun manualNextIgnoresSkipFlag() {
        val f = fixture(count = 3)
        f.skip.markSkipped(f.videos[1].id)

        f.vm.goNext()

        assertEquals(1, f.vm.currentIndex.value)
    }

    // MARK: - 未視聴のみ再生

    @Test
    fun playUnwatchedOnlySkipsWatchedVideos() {
        val f = fixture(count = 5)
        f.settings.setAutoPlayNext(true)
        f.settings.setPlayUnwatchedOnly(true)
        f.watch.markWatched(f.videos[1].id)
        f.watch.markWatched(f.videos[2].id)

        playThrough(f.vm)

        assertEquals(3, f.vm.currentIndex.value)
    }

    @Test
    fun playsWatchedVideosWhenUnwatchedOnlyIsOff() {
        val f = fixture(count = 3)
        f.settings.setAutoPlayNext(true)
        f.settings.setPlayUnwatchedOnly(false)
        f.watch.markWatched(f.videos[1].id)

        playThrough(f.vm)

        assertEquals(1, f.vm.currentIndex.value)
    }

    @Test
    fun doesNotLoopForeverWhenEverythingIsWatched() {
        val f = fixture(count = 3)
        f.settings.setAutoPlayNext(true)
        f.settings.setPlayUnwatchedOnly(true)
        f.settings.setRepeatMode(RepeatMode.All)
        f.videos.forEach { f.watch.markWatched(it.id) }

        assertNull("再生できる動画が無ければ止まる", f.vm.nextIndexForAutoAdvance())
    }

    @Test
    fun wrapsAroundToEarlierUnwatchedVideo() {
        val f = fixture(count = 4, startIndex = 2)
        f.settings.setAutoPlayNext(true)
        f.settings.setPlayUnwatchedOnly(true)
        f.settings.setRepeatMode(RepeatMode.All)
        f.watch.markWatched(f.videos[3].id)  // 後ろは視聴済み
        f.watch.markWatched(f.videos[0].id)  // 先頭も視聴済み

        assertEquals(1, f.vm.nextIndexForAutoAdvance())
    }

    // MARK: - 遅れて届く終了通知

    @Test
    fun ignoresEndedBeforePlaybackStarted() {
        val f = fixture(count = 3)
        f.settings.setAutoPlayNext(true)

        // 再生開始の通知が無いまま終了だけ届いた場合は動かない（1本飛ばしを防ぐ）。
        f.vm.handleState(PlayerState.Ended)

        assertEquals(0, f.vm.currentIndex.value)
        assertFalse(f.watch.isWatched(f.videos[0].id))
    }

    // MARK: - 戻す

    @Test
    fun goBackRestoresPreviousVideo() {
        val f = fixture(count = 5)
        assertFalse(f.vm.canGoBack.value)

        f.vm.goLast()
        assertEquals(4, f.vm.currentIndex.value)
        assertTrue(f.vm.canGoBack.value)

        f.vm.goBack()
        assertEquals(0, f.vm.currentIndex.value)
        assertFalse(f.vm.canGoBack.value)
    }

    @Test
    fun positionTextUsesGrouping() {
        assertEquals("1,034", PlayerViewModel.grouped(1034))
        assertEquals("3,500", PlayerViewModel.grouped(3500))
    }
}
