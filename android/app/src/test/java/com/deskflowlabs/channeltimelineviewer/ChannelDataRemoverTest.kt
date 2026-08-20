package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.data.ChannelDataRemover
import com.deskflowlabs.channeltimelineviewer.data.ChannelProgressStore
import com.deskflowlabs.channeltimelineviewer.data.FavoriteChannelStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.data.VideoMemoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * 「入れ替える」を選んだら、外したチャンネルの記録は**消える**。
 * これが Pro を選ぶ理由になっているので、消え方も、他のチャンネルに波及しないことも確かめる。
 */
@RunWith(RobolectricTestRunner::class)
class ChannelDataRemoverTest {

    private val prefs = ApplicationProvider.getApplicationContext<Context>()
        .getSharedPreferences("remover_test", Context.MODE_PRIVATE)

    private val favorites = FavoriteChannelStore(prefs)
    private val progress = ChannelProgressStore(prefs)
    private val cache = VideoListCache(prefs)
    private val watch = WatchHistoryStore(prefs)
    private val skip = SkippedVideoStore(prefs)
    private val memo = VideoMemoStore(prefs)
    private val position = PlaybackPositionStore(prefs)

    private val remover = ChannelDataRemover(
        favorites, progress, cache, watch, skip, memo, position)

    private fun video(id: String, channelId: String) = VideoItem(
        id = id, title = "動画 $id", publishedAtEpochSeconds = 1_700_000_000, channelId = channelId)

    private fun setUpChannel(channelId: String, videoIds: List<String>) {
        favorites.touch(Channel(id = channelId, title = "チャンネル $channelId"))
        cache.store(channelId, videoIds.map { video(it, channelId) })
        videoIds.forEach { id ->
            watch.markWatched(id)
            skip.markSkipped(id)
            memo.setMemo("メモ $id", id)
            position.record(id, seconds = 120.0, duration = 600.0)
        }
        progress.updateCounts(channelId, totalCount = videoIds.size, watchedCount = videoIds.size)
    }

    @Test
    fun `入れ替えで外したチャンネルの記録は消える`() {
        setUpChannel("UC_old", listOf("v1", "v2"))

        val erased = remover.removeChannel("UC_old")

        assertEquals(2, erased)
        assertFalse(watch.isWatched("v1"))
        assertFalse(watch.isWatched("v2"))
        assertFalse(skip.isSkipped("v1"))
        assertEquals("", memo.memo("v1"))
        assertNull(position.position("v1"))
        assertNull(progress.progress("UC_old"))
        assertNull(cache.load("UC_old"))
        assertTrue(favorites.favorites.value.none { it.id == "UC_old" })
    }

    @Test
    fun `他のチャンネルの記録は巻き込まれない`() {
        setUpChannel("UC_old", listOf("v1"))
        setUpChannel("UC_keep", listOf("v9"))

        remover.removeChannel("UC_old")

        assertTrue(watch.isWatched("v9"))
        assertTrue(skip.isSkipped("v9"))
        assertEquals("メモ v9", memo.memo("v9"))
        assertEquals(120.0, position.position("v9")!!, 0.001)
        assertTrue(favorites.favorites.value.any { it.id == "UC_keep" })
    }

    @Test
    fun `一覧をまだ開いていないチャンネルでも落ちない`() {
        favorites.touch(Channel(id = "UC_never_opened", title = "未取得"))

        val erased = remover.removeChannel("UC_never_opened")

        assertEquals(0, erased)
        assertTrue(favorites.favorites.value.none { it.id == "UC_never_opened" })
    }
}
