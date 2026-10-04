package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.data.storeJson
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.model.VideoSortOrder
import com.deskflowlabs.channeltimelineviewer.model.sortedBy
import com.deskflowlabs.channeltimelineviewer.model.withViewCounts
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 視聴回数と人気順（Android 1.17 / iOS 1.4.1）。iOS `VideoSortTests` / `VideoListCacheTests` と同じ約束。 */
class ViewCountTest {

    private fun video(id: String, epoch: Long, views: Long? = null) =
        VideoItem(id = id, title = id, publishedAtEpochSeconds = epoch, viewCount = views)

    @Test
    fun popularIsMostViewedFirst() {
        val items = listOf(video("a", 100, 10), video("b", 200, 5_000), video("c", 300, 300))
        assertEquals(listOf("b", "c", "a"), items.sortedBy(VideoSortOrder.Popular).map { it.id })
    }

    @Test
    fun popularPutsUnknownCountsLastOldestFirst() {
        val items = listOf(video("x", 300), video("a", 100, 1), video("y", 200))
        assertEquals(listOf("a", "y", "x"), items.sortedBy(VideoSortOrder.Popular).map { it.id })
    }

    @Test
    fun popularTieBreaksByOldest() {
        val items = listOf(video("b", 200, 7), video("a", 100, 7))
        assertEquals(listOf("a", "b"), items.sortedBy(VideoSortOrder.Popular).map { it.id })
    }

    @Test
    fun countsAboveIntMaxAreKept() {
        val items = listOf(video("small", 100, 1), video("huge", 200, 16_000_000_000))
        assertEquals("huge", items.sortedBy(VideoSortOrder.Popular).first().id)
    }

    @Test
    fun oldestAndNewestOrders() {
        val items = listOf(video("c", 300), video("a", 100), video("b", 200))
        assertEquals(listOf("a", "b", "c"), items.sortedBy(VideoSortOrder.Oldest).map { it.id })
        assertEquals(listOf("c", "b", "a"), items.sortedBy(VideoSortOrder.Newest).map { it.id })
    }

    @Test
    fun withViewCountsKeepsUnknownAsBefore() {
        val items = listOf(video("a", 100, 3), video("b", 200))
        assertEquals(listOf(3L, 42L), items.withViewCounts(mapOf("b" to 42L)).map { it.viewCount })
    }

    @Test
    fun parsesStatisticsResponseAndSkipsHiddenCounts() {
        val body = Json.parseToJsonElement(
            """{"items":[{"id":"v1","statistics":{"viewCount":"123456"}},{"id":"v2","statistics":{}}]}""",
        ) as JsonObject
        assertEquals(mapOf("v1" to 123_456L), YouTubeApiClient.viewCounts(body))
    }

    @Test
    fun oldCacheWithoutViewCountStillLoads() {
        // 1.17 より前の保存（viewCount / statsUpdatedAtEpochSeconds が無い）
        val raw = """{"updatedAtEpochSeconds":10,"videos":[{"id":"v1","title":"t","publishedAtEpochSeconds":0}]}"""
        val entry = storeJson.decodeFromString(VideoListCache.Entry.serializer(), raw)
        assertEquals(listOf("v1"), entry.videos.map { it.id })
        assertNull(entry.videos[0].viewCount)
        assertNull("取り直しが必要と判定される", entry.statsUpdatedAtEpochSeconds)
    }
}
