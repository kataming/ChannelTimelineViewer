package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.data.nowEpochSeconds
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.model.VideoSortOrder
import com.deskflowlabs.channeltimelineviewer.model.sortedBy
import com.deskflowlabs.channeltimelineviewer.model.withViewCounts
import com.deskflowlabs.channeltimelineviewer.model.sortedByPublishedDate
import com.deskflowlabs.channeltimelineviewer.model.titleMatches
import com.deskflowlabs.channeltimelineviewer.model.uniquedById
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiError
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 視聴状態によるフィルター。 */
enum class WatchFilter(@StringRes val labelRes: Int) {
    All(R.string.filter_all),
    Unwatched(R.string.filter_unwatched),
    Watched(R.string.filter_watched),
}

/**
 * 一覧に出す動画：並び替え → 視聴フィルター → タイトル検索（docs/channel-search.md）。
 * 並び順は変えずに絞るだけ。検索を閉じている・検索語が空なら検索では絞らない。
 * （ViewModel から切り離した純粋関数。通信や保存に触れずにテストできる）
 */
fun filterVisibleVideos(
    videos: List<VideoItem>,
    sortOrder: VideoSortOrder,
    watchFilter: WatchFilter,
    isWatched: (String) -> Boolean,
    isSearching: Boolean,
    searchQuery: String,
): List<VideoItem> {
    val sorted = videos.sortedBy(sortOrder)
    val filtered = when (watchFilter) {
        WatchFilter.All -> sorted
        WatchFilter.Unwatched -> sorted.filterNot { isWatched(it.id) }
        WatchFilter.Watched -> sorted.filter { isWatched(it.id) }
    }
    if (!isSearching || searchQuery.isEmpty()) return filtered
    return filtered.filter { it.titleMatches(searchQuery) }
}

/**
 * 動画一覧の状態。iOS 版 `ViewModels/VideoListViewModel.swift` の移植。
 *
 * 一度開いたチャンネルは保存済みの一覧をすぐ出し、新着だけを確認する
 *（既知の動画に当たるまでしかページを取らないので、通常は1ページ＝quota 1 で済む）。
 */
class VideoListViewModel(
    val channel: Channel,
    private val api: YouTubeApiClient,
    private val cache: VideoListCache,
) : ViewModel() {

    private val _videos = MutableStateFlow<List<VideoItem>>(emptyList())
    val videos: StateFlow<List<VideoItem>> = _videos.asStateFlow()

    /** 並び順。既定は古い順。人気順は視聴回数の多い順（docs/view-count.md）。 */
    private val _sortOrder = MutableStateFlow(VideoSortOrder.Oldest)
    val sortOrder: StateFlow<VideoSortOrder> = _sortOrder.asStateFlow()

    /** 視聴回数をまとめて取り直した日時（保存済みの一覧に入っている）。 */
    private var statsUpdatedAt: Long? = null

    private val _watchFilter = MutableStateFlow(WatchFilter.All)
    val watchFilter: StateFlow<WatchFilter> = _watchFilter.asStateFlow()

    /**
     * チャンネル内検索（タイトルの絞り込み・docs/channel-search.md）。保存しない・送らない。
     * ⚠️ この ViewModel は Activity の間チャンネルごとに残るので、**別チャンネルから開き直したときは
     *    MainActivity が [closeSearch] で消す**（再生画面から戻ったときだけ残す）。
     */
    private val _isSearching = MutableStateFlow(false)
    val isSearching: StateFlow<Boolean> = _isSearching.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    /** 保存済みの一覧を表示したまま、新着だけを確認している最中か。 */
    private val _isCheckingForNew = MutableStateFlow(false)
    val isCheckingForNew: StateFlow<Boolean> = _isCheckingForNew.asStateFlow()

    /** 一覧を最後に取得・更新した日時（保存済みを使ったときはその日時）。 */
    private val _lastUpdatedAt = MutableStateFlow<Long?>(null)
    val lastUpdatedAt: StateFlow<Long?> = _lastUpdatedAt.asStateFlow()

    private val _errorRes = MutableStateFlow<Int?>(null)
    val errorRes: StateFlow<Int?> = _errorRes.asStateFlow()

    /** 並び替えのみ反映した表示用リスト。 */
    fun displayedVideos(): List<VideoItem> =
        _videos.value.sortedBy(_sortOrder.value)

    /** 並び替え＋視聴フィルター＋タイトル検索を適用した最終リスト。 */
    fun visibleVideos(isWatched: (String) -> Boolean): List<VideoItem> =
        filterVisibleVideos(
            videos = _videos.value,
            sortOrder = _sortOrder.value,
            watchFilter = _watchFilter.value,
            isWatched = isWatched,
            isSearching = _isSearching.value,
            searchQuery = _searchQuery.value,
        )

    /** 検索語が入っていて、絞り込みが効いているか（0件表示を出す条件）。 */
    fun isFilteringBySearch(): Boolean = _isSearching.value && _searchQuery.value.isNotBlank()

    fun openSearch() {
        _isSearching.value = true
    }

    fun setSearchQuery(value: String) {
        _searchQuery.value = value
    }

    /** 検索を閉じて全件に戻す（検索語も消す）。 */
    fun closeSearch() {
        _isSearching.value = false
        _searchQuery.value = ""
    }

    /**
     * 「次に見る」動画：公開日が最も古い未視聴動画。
     * スキップ指定の動画は「見るつもりがない」ものなので候補から外す。
     */
    fun nextUnwatched(isWatched: (String) -> Boolean, isSkipped: (String) -> Boolean): VideoItem? =
        oldestFirst().firstOrNull { !isWatched(it.id) && !isSkipped(it.id) }

    /** 「次に見る」動画が、古い順全体で何本目か（1始まり）。 */
    fun nextUnwatchedPosition(isWatched: (String) -> Boolean, isSkipped: (String) -> Boolean): Int? {
        val index = oldestFirst().indexOfFirst { !isWatched(it.id) && !isSkipped(it.id) }
        return if (index < 0) null else index + 1
    }

    /** 古い順全体での動画リスト（再生画面に渡す基準リスト）。 */
    fun oldestFirst(): List<VideoItem> = _videos.value.sortedByPublishedDate(ascending = true)

    fun setSortOrder(value: VideoSortOrder) {
        _sortOrder.value = value
    }

    fun setWatchFilter(value: WatchFilter) {
        _watchFilter.value = value
    }

    fun loadIfNeeded() {
        if (_videos.value.isNotEmpty() || _isLoading.value) return
        viewModelScope.launch {
            // 2回目以降は保存済みの一覧をすぐ表示し、新着だけを確認する。
            val entry = cache.load(channel.id)
            if (entry != null && entry.videos.isNotEmpty()) {
                _videos.value = entry.videos
                _lastUpdatedAt.value = entry.updatedAtEpochSeconds
                statsUpdatedAt = entry.statsUpdatedAtEpochSeconds
                _errorRes.value = null
                checkForNewVideosInternal()
                refreshViewCountsIfStale()
                return@launch
            }
            loadInternal()
        }
    }

    /** 全件を取得し直す（初回、または差分が大きすぎる場合）。 */
    fun load() {
        viewModelScope.launch { loadInternal() }
    }

    /** 保存済みの一覧はそのままに、新着だけを取りに行く。 */
    fun checkForNewVideos() {
        viewModelScope.launch { checkForNewVideosInternal() }
    }

    /** 保存済みを捨てて全件取り直す（一覧がおかしくなった時の手動操作用）。 */
    fun reloadAll() {
        viewModelScope.launch {
            cache.remove(channel.id)
            _videos.value = emptyList()
            _lastUpdatedAt.value = null
            statsUpdatedAt = null
            loadInternal()
        }
    }

    private suspend fun loadInternal() {
        val playlistId = channel.uploadsPlaylistId
        if (playlistId == null) {
            _errorRes.value = YouTubeApiError.UploadsPlaylistNotFound.messageRes
            return
        }
        _errorRes.value = null
        _isLoading.value = true
        try {
            val items = api.fetchVideos(playlistId)
            _videos.value = items
            if (items.isEmpty()) {
                _errorRes.value = R.string.list_empty
            } else {
                statsUpdatedAt = null
                storeCache()
                // 一覧は先に出し、視聴回数はあとから埋める（取れなくても一覧は使える）
                refreshViewCounts(items.map { it.id }, markRefreshed = true)
            }
        } catch (e: YouTubeApiException) {
            _errorRes.value = e.error.messageRes
        } catch (e: Exception) {
            _errorRes.value = YouTubeApiError.Unknown.messageRes
        } finally {
            _isLoading.value = false
        }
    }

    private suspend fun checkForNewVideosInternal() {
        val playlistId = channel.uploadsPlaylistId ?: return
        if (_isLoading.value || _isCheckingForNew.value) return
        if (_videos.value.isEmpty()) {
            loadInternal()
            return
        }

        _isCheckingForNew.value = true
        try {
            val known = _videos.value.map { it.id }.toSet()
            val (newItems, reachedKnown) = api.fetchNewVideos(playlistId, known)
            if (!reachedKnown) {
                // 差分が大きい（久しぶりに開いた等）ので全件取り直す。
                loadInternal()
                return
            }
            if (newItems.isNotEmpty()) {
                _videos.value = (_videos.value + newItems).uniquedById()
            }
            // 新着が無くても「確認した日時」は更新しておく。
            storeCache()
            refreshViewCounts(newItems.map { it.id }, markRefreshed = false)
        } catch (e: Exception) {
            // 保存済みの一覧は表示できているので、ここでは失敗を前面に出さない。
        } finally {
            _isCheckingForNew.value = false
        }
    }

    /** 視聴回数の取り直しが要るか（一度も取っていない、または 7 日以上たった）。 */
    fun needsViewCountRefresh(now: Long = nowEpochSeconds()): Boolean {
        val last = statsUpdatedAt ?: return true
        return now - last >= VIEW_COUNT_REFRESH_SECONDS
    }

    /** 保存済みの視聴回数が古ければ、全件まとめて取り直す。 */
    private suspend fun refreshViewCountsIfStale() {
        if (_videos.value.isEmpty() || !needsViewCountRefresh()) return
        refreshViewCounts(_videos.value.map { it.id }, markRefreshed = true)
    }

    /** 視聴回数を取って反映する。失敗しても一覧はそのまま使えるので、表に出さない。 */
    private suspend fun refreshViewCounts(ids: List<String>, markRefreshed: Boolean) {
        if (ids.isEmpty()) return
        val counts = runCatching { api.fetchViewCounts(ids) }.getOrNull() ?: return
        _videos.value = _videos.value.withViewCounts(counts)
        if (markRefreshed) statsUpdatedAt = nowEpochSeconds()
        storeCache()
    }

    private fun storeCache() {
        val now = nowEpochSeconds()
        cache.store(channel.id, _videos.value, now, statsUpdatedAt)
        _lastUpdatedAt.value = now
    }

    companion object {
        /**
         * 視聴回数をまとめて取り直す間隔。YouTube の規約で、保存した API のデータは
         * 30 日以内に取り直す必要がある。quota を抑えるため、それより短い 7 日にしておく（iOS と同じ）。
         */
        const val VIEW_COUNT_REFRESH_SECONDS = 7L * 24 * 3600
    }
}
