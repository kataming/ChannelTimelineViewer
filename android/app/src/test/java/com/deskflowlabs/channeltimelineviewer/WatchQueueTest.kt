package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.WatchQueueStore
import com.deskflowlabs.channeltimelineviewer.network.WatchQueue
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueItem
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerState
import com.deskflowlabs.channeltimelineviewer.viewmodel.WatchQueuePlayerViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Watch Queue（V2）の再生と、接続していないときの振る舞い。
 *
 * 確かめるのは「保存に触れないこと」と「連続再生はユーザーが選んだときだけ働くこと」。
 */
@RunWith(RobolectricTestRunner::class)
class WatchQueueTest {

    private fun context(): Context = ApplicationProvider.getApplicationContext()

    private fun prefs(name: String) =
        context().getSharedPreferences(name, Context.MODE_PRIVATE).also { it.edit().clear().commit() }

    private fun settings(autoPlayNext: Boolean): PlaybackSettingsStore {
        val store = prefs("watch-queue-settings-$autoPlayNext")
        store.edit().putBoolean("setting_autoplay_next_v1", autoPlayNext).commit()
        return PlaybackSettingsStore(store)
    }

    private fun queue(vararg ids: String) = WatchQueue(
        queueId = "11111111-2222-3333-4444-555555555555",
        name = "Watch Queue",
        version = 1,
        items = ids.map { WatchQueueItem(videoId = it, title = "Title $it", channelName = "Ch") },
    )

    @Test
    fun `キューの順番どおりに再生する`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b", "c"), settings(autoPlayNext = true))
        assertEquals("a", vm.current?.videoId)
        assertEquals("1 / 3", vm.positionText())

        vm.goNext()
        assertEquals("b", vm.current?.videoId)
        vm.goLast()
        assertEquals("c", vm.current?.videoId)
        assertFalse(vm.canGoNext)
        vm.goFirst()
        assertEquals("a", vm.current?.videoId)
    }

    @Test
    fun `自動再生がオンなら終了で次へ進む`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b"), settings(autoPlayNext = true))
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
        assertEquals("b", vm.current?.videoId)
        assertFalse(vm.showEndedSuggestion.value)
    }

    @Test
    fun `自動再生がオフなら止まって次の動画を案内する`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b"), settings(autoPlayNext = false))
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
        assertEquals("a", vm.current?.videoId)
        assertTrue(vm.showEndedSuggestion.value)
        assertEquals("b", vm.nextItem?.videoId)

        vm.goNext()
        assertEquals("b", vm.current?.videoId)
        assertFalse(vm.showEndedSuggestion.value)
    }

    @Test
    fun `自動再生がオフのとき先回りの通知では進まない`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b"), settings(autoPlayNext = false))
        vm.handleState(PlayerState.Playing)
        vm.handleNearEnd("a")
        assertEquals("a", vm.current?.videoId)
    }

    @Test
    fun `再生が始まっていない動画の終了通知は無視する`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b", "c"), settings(autoPlayNext = true))
        vm.handleNearEnd("a")
        assertEquals("a", vm.current?.videoId)
    }

    @Test
    fun `最後まで見たら完了になり最初から再生できる`() {
        val vm = WatchQueuePlayerViewModel(queue("a", "b"), settings(autoPlayNext = true))
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
        vm.handleState(PlayerState.Playing)
        vm.handleState(PlayerState.Ended)
        assertTrue(vm.isCompleted.value)
        assertEquals(setOf("a", "b"), vm.playedIds.value)

        vm.restartQueue()
        assertFalse(vm.isCompleted.value)
        assertEquals("a", vm.current?.videoId)
        assertTrue(vm.playedIds.value.isEmpty())
    }

    @Test
    fun `接続していないあいだは何も出さず通信もしない`() {
        val store = WatchQueueStore(prefs("watch-queue-store"))
        assertFalse(store.isAvailable)
        assertFalse(store.isPaired.value)
        assertTrue(store.queues.value.isEmpty())
    }
}
