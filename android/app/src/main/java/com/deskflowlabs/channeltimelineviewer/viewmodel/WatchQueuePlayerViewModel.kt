package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.lifecycle.ViewModel
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.network.WatchQueue
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueItem
import com.deskflowlabs.channeltimelineviewer.ui.PlayerState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Watch Queue（V2）を順番に再生するための状態。
 *
 * チャンネル再生（`PlayerViewModel`）との違い:
 * - **保存に一切触れない**。視聴済み・スキップ・メモ・再生位置・チャンネル進捗のどれも読み書きしない。
 * - 並び順はサーバー（＝拡張で保存した順）そのままで、並び替え・絞り込み・繰り返しはしない。
 * - 自動で次へ進むのは、自動再生スイッチがオンのときだけ（設定は通常再生と共有）。
 *
 * ⚠️ Android のプレイヤー部品には再生失敗の通知（iOS の `onError`）が無いため、
 *    再生できない動画を自動で見分けることはできない。利用者が手で次へ進める。
 */
class WatchQueuePlayerViewModel(
    queue: WatchQueue,
    private val settings: PlaybackSettingsStore,
) : ViewModel() {

    val items: List<WatchQueueItem> = queue.items
    val queueName: String = queue.name

    private val _currentIndex = MutableStateFlow(0)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    /** 自動再生がオフで、動画が終わったときに「次の動画を再生」を出すか。 */
    private val _showEndedSuggestion = MutableStateFlow(false)
    val showEndedSuggestion: StateFlow<Boolean> = _showEndedSuggestion.asStateFlow()

    /** 最後まで再生し終えたか。 */
    private val _isCompleted = MutableStateFlow(false)
    val isCompleted: StateFlow<Boolean> = _isCompleted.asStateFlow()

    /** 再生し終えた動画（印は画面の中だけで、保存はしない）。 */
    private val _playedIds = MutableStateFlow<Set<String>>(emptySet())
    val playedIds: StateFlow<Set<String>> = _playedIds.asStateFlow()

    /** 同じ動画の「終了」を二重に処理しないための記録。 */
    private var endedHandledVideoId: String? = null

    /** いま表示している動画が実際に再生され始めたか（切り替え直後の遅れた終了通知を無視する）。 */
    private var hasStartedCurrent = false

    val current: WatchQueueItem? get() = items.getOrNull(_currentIndex.value)
    val canGoPrevious: Boolean get() = _currentIndex.value > 0
    val canGoNext: Boolean get() = _currentIndex.value < items.size - 1
    val nextItem: WatchQueueItem? get() = items.getOrNull(_currentIndex.value + 1)

    fun positionText(): String = "${if (items.isEmpty()) 0 else _currentIndex.value + 1} / ${items.size}"

    fun move(index: Int) {
        if (index !in items.indices) return
        _currentIndex.value = index
        _showEndedSuggestion.value = false
        _isCompleted.value = false
        endedHandledVideoId = null
        hasStartedCurrent = false
    }

    fun goNext() {
        if (!canGoNext) {
            _isCompleted.value = true
            _showEndedSuggestion.value = false
            return
        }
        move(_currentIndex.value + 1)
    }

    fun goPrevious() = move(_currentIndex.value - 1)
    fun goFirst() = move(0)
    fun goLast() = move(items.size - 1)

    fun restartQueue() {
        _playedIds.value = emptySet()
        move(0)
    }

    fun handleState(state: PlayerState) {
        if (state == PlayerState.Playing) {
            hasStartedCurrent = true
            _showEndedSuggestion.value = false
        }
        if (state != PlayerState.Ended) return
        current?.let { finish(it.videoId) }
    }

    /** 終わる直前に呼ばれる。全画面のまま次へ移るために、ここで先回りして切り替える。 */
    fun handleNearEnd(videoId: String) {
        if (!settings.autoPlayNext.value) return
        if (current?.videoId != videoId || !hasStartedCurrent) return
        finish(videoId)
    }

    private fun finish(videoId: String) {
        if (endedHandledVideoId == videoId) return
        endedHandledVideoId = videoId
        _playedIds.value = _playedIds.value + videoId

        when {
            settings.autoPlayNext.value -> goNext()
            canGoNext -> _showEndedSuggestion.value = true
            else -> _isCompleted.value = true
        }
    }
}
