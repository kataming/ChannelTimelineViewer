import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var currentIndex: Int
    @Published var playerState: YouTubePlayerState = .unstarted
    /// 再生終了後に「次の動画」を提示するか（自動再生がオフのとき）。
    @Published var showEndedSuggestion = false
    /// 現在の動画をどの位置から再生し始めたか（秒）。0 なら最初から。
    @Published private(set) var startSecondsForCurrent: Double = 0
    /// 「最初から再生」などの位置移動要求。View が WebView に渡す。
    @Published private(set) var seekRequest: YouTubePlayerWebView.SeekRequest?
    /// 自動再生で次の動画へ切り替えた直後かどうか（画面表示用）。
    @Published private(set) var didAutoAdvance = false

    let videos: [VideoItem]
    private let watchStore: WatchHistoryStore
    private let positionStore: PlaybackPositionStore
    private let settings: PlaybackSettingsStore
    /// 同じ動画の「終了」を二重に処理しないための記録。
    private var endedHandledVideoId: String?
    /// いま表示している動画が実際に再生され始めたか。
    /// 動画を切り替えた直後に、前の動画の「終了」通知が遅れて届くことがあるため、
    /// 再生が始まっていない動画の終了通知は無視する（＝1本飛ばしを防ぐ）。
    private var hasStartedCurrentVideo = false

    init(videos: [VideoItem],
         startIndex: Int,
         watchStore: WatchHistoryStore,
         positionStore: PlaybackPositionStore,
         settings: PlaybackSettingsStore) {
        self.videos = videos
        if videos.isEmpty {
            self.currentIndex = 0
        } else {
            self.currentIndex = max(0, min(startIndex, videos.count - 1))
        }
        self.watchStore = watchStore
        self.positionStore = positionStore
        self.settings = settings
        self.startSecondsForCurrent = Self.resumeSeconds(
            for: videos.indices.contains(self.currentIndex) ? videos[self.currentIndex] : nil,
            positionStore: positionStore,
            settings: settings
        )
    }

    var currentVideo: VideoItem? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < videos.count - 1 }
    var nextVideo: VideoItem? { canGoNext ? videos[currentIndex + 1] : nil }

    /// 「前回の続き」から再生を開始したか（画面に案内と「最初から」ボタンを出す判断に使う）。
    var isResumingFromSavedPosition: Bool { startSecondsForCurrent > 0 }

    // MARK: - 移動

    func goNext() {
        guard canGoNext else { return }
        move(to: currentIndex + 1)
    }

    func goPrevious() {
        guard canGoPrevious else { return }
        move(to: currentIndex - 1)
    }

    private func move(to index: Int, autoAdvanced: Bool = false) {
        currentIndex = index
        showEndedSuggestion = false
        didAutoAdvance = autoAdvanced
        seekRequest = nil
        hasStartedCurrentVideo = false
        startSecondsForCurrent = Self.resumeSeconds(
            for: currentVideo, positionStore: positionStore, settings: settings
        )
    }

    /// 保存された再生位置を捨てて、いま見ている動画を最初から再生する。
    func restartFromBeginning() {
        guard let video = currentVideo else { return }
        positionStore.clear(videoId: video.id)
        startSecondsForCurrent = 0
        didAutoAdvance = false
        // 最初から見直した場合は、もう一度終了時の処理を行えるようにする。
        endedHandledVideoId = nil
        hasStartedCurrentVideo = true
        seekRequest = YouTubePlayerWebView.SeekRequest(seconds: 0)
    }

    // MARK: - 視聴済み

    func markCurrentWatched() {
        guard let video = currentVideo else { return }
        watchStore.markWatched(video.id)
    }

    func isCurrentWatched() -> Bool {
        guard let video = currentVideo else { return false }
        return watchStore.isWatched(video.id)
    }

    // MARK: - プレイヤーからの通知

    /// IFrame Player の状態変化を受け取る。
    func handleState(_ state: YouTubePlayerState) {
        playerState = state
        if state == .playing {
            hasStartedCurrentVideo = true
        }
        guard state == .ended, let video = currentVideo else { return }
        // まだ再生が始まっていない＝前の動画の終了通知が遅れて届いたとみなして無視する。
        guard hasStartedCurrentVideo else { return }
        // 同じ動画の終了通知が重複して届くことがあるので一度だけ処理する。
        guard endedHandledVideoId != video.id else { return }
        endedHandledVideoId = video.id

        // 見終わったので視聴済みにし、再開位置は破棄する。
        markCurrentWatched()
        positionStore.clear(videoId: video.id)

        if settings.autoPlayNext, canGoNext {
            // 一覧の次の動画へ続けて再生する（設定でオフにできる）。
            move(to: currentIndex + 1, autoAdvanced: true)
        } else {
            showEndedSuggestion = canGoNext
        }
    }

    /// 公式プレイヤーから通知された再生位置を保存する（続きから再生用）。
    func handleTimeUpdate(videoId: String, seconds: Double, duration: Double) {
        positionStore.record(videoId: videoId, seconds: seconds, duration: duration)
    }

    /// 保存済みの再生位置（設定がオフなら常に 0）。
    private static func resumeSeconds(for video: VideoItem?,
                                      positionStore: PlaybackPositionStore,
                                      settings: PlaybackSettingsStore) -> Double {
        guard settings.resumeFromLastPosition, let video else { return 0 }
        return positionStore.position(for: video.id) ?? 0
    }
}
