package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.lifecycle.ViewModel
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 公式プレイヤーの再生状態（IFrame Player API の値に対応）。 */
enum class PlayerState { Unstarted, Ended, Playing, Paused, Buffering, Cued }

/** プレイヤーへの操作要求。View が WebView に渡す。 */
sealed interface PlayerCommand {
    val id: Long

    data class Seek(val seconds: Double, override val id: Long) : PlayerCommand
    data class Replay(override val id: Long) : PlayerCommand
    data class SetRate(val rate: Double, override val id: Long) : PlayerCommand
    data class SetCaption(val code: String?, override val id: Long) : PlayerCommand
    data class RefreshOptions(override val id: Long) : PlayerCommand
}

/** プレイヤーから受け取る、設定画面に出す情報。 */
data class PlayerOptions(
    val rate: Double = 1.0,
    val rates: List<Double> = emptyList(),
    val captions: List<Caption> = emptyList(),
    val activeCaption: String? = null,
) {
    data class Caption(val code: String, val name: String)
}

/**
 * 再生画面の状態。iOS 版 `ViewModels/PlayerViewModel.swift` の移植。
 *
 * 自動再生・リピート・スキップ・未視聴のみ再生の判断は、iOS と同じ規則で行う
 * （進む先は開いている一覧の次の動画だけ。関連動画・おすすめには行かない）。
 */
class PlayerViewModel(
    val videos: List<VideoItem>,
    startIndex: Int,
    private val watchStore: WatchHistoryStore,
    private val skipStore: SkippedVideoStore,
    private val positionStore: PlaybackPositionStore,
    private val settings: PlaybackSettingsStore,
) : ViewModel() {

    private val _currentIndex = MutableStateFlow(
        if (videos.isEmpty()) 0 else startIndex.coerceIn(0, videos.size - 1)
    )
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _playerState = MutableStateFlow(PlayerState.Unstarted)
    val playerState: StateFlow<PlayerState> = _playerState.asStateFlow()

    /** 再生終了後に「次の動画」を提示するか（自動再生がオフのとき）。 */
    private val _showEndedSuggestion = MutableStateFlow(false)
    val showEndedSuggestion: StateFlow<Boolean> = _showEndedSuggestion.asStateFlow()

    /** 現在の動画をどの位置から再生し始めたか（秒）。0 なら最初から。 */
    private val _startSecondsForCurrent = MutableStateFlow(0.0)
    val startSecondsForCurrent: StateFlow<Double> = _startSecondsForCurrent.asStateFlow()

    private val _command = MutableStateFlow<PlayerCommand?>(null)
    val command: StateFlow<PlayerCommand?> = _command.asStateFlow()

    private val _options = MutableStateFlow(PlayerOptions())
    val options: StateFlow<PlayerOptions> = _options.asStateFlow()

    /** 自動再生で次の動画へ切り替えた直後かどうか（画面表示用）。 */
    private val _didAutoAdvance = MutableStateFlow(false)
    val didAutoAdvance: StateFlow<Boolean> = _didAutoAdvance.asStateFlow()

    /** 「戻す」（直前の移動を取り消す）が使えるか。 */
    private val _canGoBack = MutableStateFlow(false)
    val canGoBack: StateFlow<Boolean> = _canGoBack.asStateFlow()

    /** 視聴済み・スキップの変化を画面に伝えるための版数。 */
    private val _statusRevision = MutableStateFlow(0)
    val statusRevision: StateFlow<Int> = _statusRevision.asStateFlow()

    /** 同じ動画の「終了」を二重に処理しないための記録。 */
    private var endedHandledVideoId: String? = null

    /**
     * いま表示している動画が実際に再生され始めたか。
     * 動画を切り替えた直後に前の動画の「終了」通知が遅れて届くことがあるため、
     * 再生が始まっていない動画の終了通知は無視する（＝1本飛ばしを防ぐ）。
     */
    private var hasStartedCurrentVideo = false

    /** 移動を取り消すための履歴（「最初へ」などを押し間違えたとき用）。 */
    private data class NavigationSnapshot(val index: Int, val seconds: Double)

    private val history = ArrayDeque<NavigationSnapshot>()
    private var currentPlaybackSeconds = 0.0
    private var commandCounter = 0L

    init {
        val seconds = resumeSeconds(currentVideo)
        _startSecondsForCurrent.value = seconds
        currentPlaybackSeconds = seconds
    }

    val currentVideo: VideoItem? get() = videos.getOrNull(_currentIndex.value)
    val canGoPrevious: Boolean get() = _currentIndex.value > 0
    val canGoNext: Boolean get() = _currentIndex.value < videos.size - 1
    val nextVideo: VideoItem? get() = if (canGoNext) videos[_currentIndex.value + 1] else null

    /** 一覧の中での位置（1始まり）。 */
    val currentPosition: Int get() = if (videos.isEmpty()) 0 else _currentIndex.value + 1
    val totalCount: Int get() = videos.size

    /** 「1,034 / 3,500」のような位置表示。 */
    val positionText: String get() = "${grouped(currentPosition)} / ${grouped(totalCount)}"

    /** 「前回の続き」から再生を開始したか。 */
    val isResumingFromSavedPosition: Boolean get() = _startSecondsForCurrent.value > 0

    // MARK: - 移動

    fun goNext() {
        if (canGoNext) move(_currentIndex.value + 1)
    }

    fun goPrevious() {
        if (canGoPrevious) move(_currentIndex.value - 1)
    }

    /** 一覧の先頭（いちばん古い動画）へ。 */
    fun goFirst() {
        if (canGoPrevious) move(0)
    }

    /** 一覧の末尾（いちばん新しい動画）へ。 */
    fun goLast() {
        if (canGoNext) move(videos.size - 1)
    }

    /** 直前の移動を取り消して、移動前の動画・再生位置へ戻る。 */
    fun goBack() {
        val snapshot = history.removeLastOrNull() ?: return
        _canGoBack.value = history.isNotEmpty()
        move(snapshot.index, recordHistory = false, startSeconds = restoreSeconds(snapshot))
    }

    private fun move(
        index: Int,
        autoAdvanced: Boolean = false,
        recordHistory: Boolean = true,
        startSeconds: Double? = null,
    ) {
        if (recordHistory) {
            history.addLast(NavigationSnapshot(_currentIndex.value, currentPlaybackSeconds))
            while (history.size > HISTORY_LIMIT) history.removeFirst()
            _canGoBack.value = true
        }
        _currentIndex.value = index
        _showEndedSuggestion.value = false
        _didAutoAdvance.value = autoAdvanced
        _command.value = null
        hasStartedCurrentVideo = false
        val seconds = startSeconds ?: resumeSeconds(currentVideo)
        _startSecondsForCurrent.value = seconds
        currentPlaybackSeconds = seconds
    }

    /**
     * 戻り先の再生位置。移動時に控えた位置と、保存済みの位置の新しい方を使う
     * （動画を切り替える直前にプレイヤーが位置を通知してくるため、保存側が新しいことがある）。
     */
    private fun restoreSeconds(snapshot: NavigationSnapshot): Double {
        val video = videos.getOrNull(snapshot.index) ?: return snapshot.seconds
        val stored = positionStore.position(video.id) ?: 0.0
        return maxOf(stored, snapshot.seconds)
    }

    /** 保存された再生位置を捨てて、いま見ている動画を最初から再生する。 */
    fun restartFromBeginning() {
        val video = currentVideo ?: return
        positionStore.clear(video.id)
        _startSecondsForCurrent.value = 0.0
        currentPlaybackSeconds = 0.0
        _didAutoAdvance.value = false
        // 最初から見直した場合は、もう一度終了時の処理を行えるようにする。
        endedHandledVideoId = null
        hasStartedCurrentVideo = true
        _command.value = PlayerCommand.Seek(0.0, nextCommandId())
    }

    // MARK: - 再生設定（プレイヤー外の設定画面から操作する）

    fun handleOptions(options: PlayerOptions) {
        _options.value = options
    }

    fun setPlaybackRate(rate: Double) {
        _options.value = _options.value.copy(rate = rate)
        _command.value = PlayerCommand.SetRate(rate, nextCommandId())
    }

    fun setCaptionTrack(code: String?) {
        _options.value = _options.value.copy(activeCaption = code)
        _command.value = PlayerCommand.SetCaption(code, nextCommandId())
    }

    /** 設定画面を開いたときに、選べる速度・字幕トラックを取り直す。 */
    fun refreshOptions() {
        _command.value = PlayerCommand.RefreshOptions(nextCommandId())
    }

    /** 選べる再生速度。プレイヤーから届く前は一般的な候補を出す。 */
    val availableRates: List<Double>
        get() = _options.value.rates.ifEmpty { listOf(0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0) }

    // MARK: - 視聴済み / スキップ

    fun markCurrentWatched() {
        val video = currentVideo ?: return
        watchStore.markWatched(video.id)
        _statusRevision.value += 1
    }

    fun isCurrentWatched(): Boolean = currentVideo?.let { watchStore.isWatched(it.id) } ?: false

    fun isCurrentSkipped(): Boolean = currentVideo?.let { skipStore.isSkipped(it.id) } ?: false

    fun toggleCurrentWatched() {
        val video = currentVideo ?: return
        watchStore.toggleWatched(video.id)
        _statusRevision.value += 1
    }

    fun toggleCurrentSkipped() {
        val video = currentVideo ?: return
        skipStore.toggleSkipped(video.id)
        _statusRevision.value += 1
    }

    // MARK: - 次に再生する動画の決め方

    /**
     * 自動再生で再生してよい動画か。
     * スキップ指定は常に除外し、「未視聴のみ再生」がオンなら視聴済みも除外する。
     */
    private fun isPlayableForAutoAdvance(video: VideoItem): Boolean {
        if (skipStore.isSkipped(video.id)) return false
        if (settings.playUnwatchedOnly.value && watchStore.isWatched(video.id)) return false
        return true
    }

    /** 自動再生で次に進む先。無ければ null（そこで停止する）。 */
    fun nextIndexForAutoAdvance(): Int? {
        if (videos.isEmpty()) return null

        var index = _currentIndex.value + 1
        while (index < videos.size) {
            if (isPlayableForAutoAdvance(videos[index])) return index
            index += 1
        }

        // 全体リピートなら先頭に戻って探す（いま見ている動画の手前まで）。
        if (settings.repeatMode.value != RepeatMode.All) return null
        index = 0
        while (index < _currentIndex.value) {
            if (isPlayableForAutoAdvance(videos[index])) return index
            index += 1
        }
        return null
    }

    // MARK: - プレイヤーからの通知

    /** IFrame Player の状態変化を受け取る。 */
    fun handleState(state: PlayerState) {
        _playerState.value = state
        if (state == PlayerState.Playing) hasStartedCurrentVideo = true
        if (state != PlayerState.Ended) return

        val video = currentVideo ?: return
        // まだ再生が始まっていない＝前の動画の終了通知が遅れて届いたとみなして無視する。
        if (!hasStartedCurrentVideo) return
        // 同じ動画の終了通知が重複して届くことがあるので一度だけ処理する。
        if (endedHandledVideoId == video.id) return
        endedHandledVideoId = video.id

        // 見終わったので視聴済みにし、再開位置は破棄する。
        markCurrentWatched()
        positionStore.clear(video.id)

        // 1本リピートは自動再生の設定に関わらず、同じ動画を繰り返す。
        if (settings.repeatMode.value == RepeatMode.One) {
            endedHandledVideoId = null      // 次の終了もまた処理する
            hasStartedCurrentVideo = false  // 再生開始の通知を待つ
            _showEndedSuggestion.value = false
            _command.value = PlayerCommand.Replay(nextCommandId())
            return
        }

        val next = if (settings.autoPlayNext.value) nextIndexForAutoAdvance() else null
        if (next != null) {
            // 一覧の次の動画へ続けて再生する（スキップ指定と「未視聴のみ」を考慮）。
            move(next, autoAdvanced = true)
        } else {
            _showEndedSuggestion.value = canGoNext
        }
    }

    /** 公式プレイヤーから通知された再生位置を保存する（続きから再生用）。 */
    fun handleTimeUpdate(videoId: String, seconds: Double, duration: Double) {
        positionStore.record(videoId, seconds, duration)
        // 「戻す」で元の位置に戻れるよう、現在地も控えておく。
        if (videoId == currentVideo?.id && seconds.isFinite() && seconds >= 0) {
            currentPlaybackSeconds = seconds
        }
    }

    /** 保存済みの再生位置（設定がオフなら常に 0）。 */
    private fun resumeSeconds(video: VideoItem?): Double {
        if (!settings.resumeFromLastPosition.value || video == null) return 0.0
        return positionStore.position(video.id) ?: 0.0
    }

    private fun nextCommandId(): Long = ++commandCounter

    companion object {
        private const val HISTORY_LIMIT = 30

        /** 端末の地域設定に関係なく「1,034」の形にする。 */
        fun grouped(value: Int): String = "%,d".format(java.util.Locale.US, value)

        /** 「1.5」のような数値部分（表示は文言側の書式に差し込む）。 */
        fun rateNumber(rate: Double): String =
            if (rate == Math.floor(rate)) rate.toInt().toString()
            else "%.2f".format(rate).trimEnd('0').trimEnd('.')
    }
}
