package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.model.VideoSortOrder
import com.deskflowlabs.channeltimelineviewer.model.titleMatches
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient
import com.deskflowlabs.channeltimelineviewer.viewmodel.VideoListViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.WatchFilter
import com.deskflowlabs.channeltimelineviewer.viewmodel.filterVisibleVideos
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * チャンネル内検索（タイトルの絞り込み・docs/channel-search.md）。
 * ⚠️ 一致の例は iOS `Tests/ChannelSearchTests.swift` と Web `site/scripts/test-trial.mjs` と同じにしてある。
 */
@RunWith(RobolectricTestRunner::class)
class ChannelSearchTest {

    private fun vid(id: String, title: String, epoch: Long) =
        VideoItem(id = id, title = title, description = "説明文にだけ chatgpt がある", publishedAtEpochSeconds = epoch)

    // ---- 一致の規則（3つで同じ例） ----

    @Test
    fun sharedMatchCases() {
        val cases = listOf(
            Triple("How to Use ChatGPT for Work", "chatgpt", true),
            Triple("How to Use ChatGPT for Work", "CHATGPT", true),
            Triple("How to Use ChatGPT for Work", "Use Chat", true),
            Triple("ＣｈａｔＧＰＴ入門", "chatgpt", true),
            Triple("日本語の動画タイトル", "動画", true),
            Triple("ｶﾀｶﾅのタイトル", "カタカナ", true),
            Triple("中文视频标题", "视频", true),
            Triple("한국어 동영상 제목", "동영상", true),
            Triple("How to Use ChatGPT for Work", "python", false),
            Triple("How to Use ChatGPT for Work", "", true),
            Triple("How to Use ChatGPT for Work", "   ", true),
        )
        for ((title, query, expected) in cases) {
            assertEquals("「$title」に「$query」", expected, vid("x", title, 0).titleMatches(query))
        }
    }

    @Test
    fun descriptionIsNotSearched() {
        assertFalse(vid("x", "Cooking basics", 0).titleMatches("chatgpt"))
    }

    // ---- 一覧への適用 ----

    private val sample = listOf(
        vid("a", "ChatGPT 入門", 100),
        vid("b", "料理の基本", 200),
        vid("c", "chatgpt の使い方", 300),
    )

    private fun visible(
        sortOrder: VideoSortOrder = VideoSortOrder.Oldest,
        filter: WatchFilter = WatchFilter.All,
        isWatched: (String) -> Boolean = { false },
        isSearching: Boolean = true,
        query: String,
    ) = filterVisibleVideos(sample, sortOrder, filter, isWatched, isSearching, query).map { it.id }

    @Test
    fun searchKeepsOldestFirst() {
        assertEquals(listOf("a", "c"), visible(query = "ChatGPT"))
    }

    @Test
    fun searchKeepsNewestFirst() {
        assertEquals(listOf("c", "a"), visible(sortOrder = VideoSortOrder.Newest, query = "chatgpt"))
    }

    @Test
    fun searchCombinesWithWatchFilter() {
        assertEquals(listOf("c"), visible(filter = WatchFilter.Unwatched, isWatched = { it == "a" }, query = "chatgpt"))
    }

    @Test
    fun noResultsIsEmpty() {
        assertTrue(visible(query = "python").isEmpty())
    }

    @Test
    fun emptyQueryOrClosedSearchShowsAll() {
        assertEquals(listOf("a", "b", "c"), visible(query = ""))
        assertEquals(listOf("a", "b", "c"), visible(isSearching = false, query = "chatgpt"))
    }

    // ---- ViewModel の開く・消す・閉じる ----

    private fun viewModel(channelId: String = "UCa"): VideoListViewModel {
        val prefs = ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("search-test", Context.MODE_PRIVATE)
        return VideoListViewModel(
            Channel(id = channelId, title = "t", uploadsPlaylistId = "UU$channelId"),
            YouTubeApiClient(apiKey = "test"),
            VideoListCache(prefs),
        )
    }

    @Test
    fun openTypeClearAndClose() {
        val vm = viewModel()
        assertFalse(vm.isSearching.value)

        vm.openSearch()
        vm.setSearchQuery("chatgpt")
        assertTrue(vm.isSearching.value)
        assertTrue(vm.isFilteringBySearch())

        vm.setSearchQuery("")
        assertFalse("検索語を消すと絞り込みは止まる", vm.isFilteringBySearch())
        assertTrue("検索欄は開いたまま", vm.isSearching.value)

        vm.setSearchQuery("chatgpt")
        vm.closeSearch()
        assertFalse(vm.isSearching.value)
        assertEquals("", vm.searchQuery.value)
    }

    /** 別チャンネルは別の ViewModel。開き直すときは MainActivity が closeSearch する（keepSearch=false）。 */
    @Test
    fun anotherChannelStartsWithoutSearch() {
        val first = viewModel("UCa")
        first.openSearch()
        first.setSearchQuery("chatgpt")
        val second = viewModel("UCb")
        assertFalse(second.isSearching.value)
        assertEquals("", second.searchQuery.value)
    }
}
