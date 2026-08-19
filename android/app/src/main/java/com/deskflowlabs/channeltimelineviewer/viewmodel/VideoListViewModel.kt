package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.data.nowEpochSeconds
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.model.sortedByPublishedDate
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

    /** true = 古い順（publishedAt 昇順）。既定は古い順。 */
    private val _sortAscending = MutableStateFlow(true)
    val sortAscending: StateFlow<Boolean> = _sortAscending.asStateFlow()

    private val _watchFilter = MutableStateFlow(WatchFilter.All)
    val watchFilter: StateFlow<WatchFilter> = _watchFilter.asStateFlow()

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
        _videos.value.sortedByPublishedDate(_sortAscending.value)

    /** 並び替え＋視聴フィルターを適用した最終リスト。 */
    fun visibleVideos(isWatched: (String) -> Boolean): List<VideoItem> {
        val sorted = displayedVideos()
        return when (_watchFilter.value) {
            WatchFilter.All -> sorted
            WatchFilter.Unwatched -> sorted.filterNot { isWatched(it.id) }
            WatchFilter.Watched -> sorted.filter { isWatched(it.id) }
        }
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

    fun setSortAscending(value: Boolean) {
        _sortAscending.value = value
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
                _errorRes.value = null
                checkForNewVideosInternal()
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
                storeCache()
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
        } catch (e: Exception) {
            // 保存済みの一覧は表示できているので、ここでは失敗を前面に出さない。
        } finally {
            _isCheckingForNew.value = false
        }
    }

    private fun storeCache() {
        val now = nowEpochSeconds()
        cache.store(channel.id, _videos.value, now)
        _lastUpdatedAt.value = now
    }
}
