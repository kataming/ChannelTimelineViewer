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
    /// 「戻る」（直前の移動を取り消す）が使えるか。
    @Published private(set) var canGoBack = false

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

    /// 移動を取り消すための履歴（「最初へ」などを押し間違えたとき用）。
    private struct NavigationSnapshot {
        let index: Int
        /// 移動する直前の再生位置（秒）。
        let seconds: Double
    }
    private var history: [NavigationSnapshot] = []
    private static let historyLimit = 30
    /// いま再生中の動画の再生位置（プレイヤーからの通知で更新）。
    private var currentPlaybackSeconds: Double = 0

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
        self.currentPlaybackSeconds = self.startSecondsForCurrent
    }

    var currentVideo: VideoItem? {
        videos.indices.contains(currentIndex) ? videos[currentIndex] : nil
    }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < videos.count - 1 }
    var nextVideo: VideoItem? { canGoNext ? videos[currentIndex + 1] : nil }

    /// 一覧の中での位置（1始まり）。
    var currentPosition: Int { videos.isEmpty ? 0 : currentIndex + 1 }
    var totalCount: Int { videos.count }

    /// 「1,034 / 3,500」のような位置表示。
    var positionText: String {
        "\(Self.grouped(currentPosition)) / \(Self.grouped(totalCount))"
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // 端末の地域設定に関係なく「1,034」の形にする。
        f.usesGroupingSeparator = true
        f.groupingSeparator = ","
        f.groupingSize = 3
        return f
    }()

    private static func grouped(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

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

    /// 一覧の先頭（いちばん古い動画）へ。
    func goFirst() {
        guard canGoPrevious else { return }
        move(to: 0)
    }

    /// 一覧の末尾（いちばん新しい動画）へ。
    func goLast() {
        guard canGoNext else { return }
        move(to: videos.count - 1)
    }

    /// 直前の移動を取り消して、移動前の動画・再生位置へ戻る。
    /// 「最初へ」「最後へ」などを押し間違えたときの復帰用。
    func goBack() {
        guard let snapshot = history.popLast() else { return }
        canGoBack = !history.isEmpty
        move(to: snapshot.index, recordHistory: false, startSeconds: restoreSeconds(for: snapshot))
    }

    private func move(to index: Int,
                      autoAdvanced: Bool = false,
                      recordHistory: Bool = true,
                      startSeconds: Double? = nil) {
        if recordHistory {
            history.append(NavigationSnapshot(index: currentIndex, seconds: currentPlaybackSeconds))
            if history.count > Self.historyLimit {
                history.removeFirst(history.count - Self.historyLimit)
            }
            canGoBack = true
        }
        currentIndex = index
        showEndedSuggestion = false
        didAutoAdvance = autoAdvanced
        seekRequest = nil
        hasStartedCurrentVideo = false
        startSecondsForCurrent = startSeconds ?? Self.resumeSeconds(
            for: currentVideo, positionStore: positionStore, settings: settings
        )
        currentPlaybackSeconds = startSecondsForCurrent
    }

    /// 戻り先の再生位置。移動時に控えた位置と、保存済みの位置の新しい方を使う。
    /// （動画を切り替える直前にプレイヤーが位置を通知してくるため、保存側の方が新しいことがある）
    private func restoreSeconds(for snapshot: NavigationSnapshot) -> Double {
        guard videos.indices.contains(snapshot.index) else { return snapshot.seconds }
        let stored = positionStore.position(for: videos[snapshot.index].id) ?? 0
        return max(stored, snapshot.seconds)
    }

    /// 保存された再生位置を捨てて、いま見ている動画を最初から再生する。
    func restartFromBeginning() {
        guard let video = currentVideo else { return }
        positionStore.clear(videoId: video.id)
        startSecondsForCurrent = 0
        currentPlaybackSeconds = 0
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
        // 「戻る」で元の位置に戻れるよう、現在地も控えておく。
        if videoId == currentVideo?.id, seconds.isFinite, seconds >= 0 {
            currentPlaybackSeconds = seconds
        }
    }

    /// 保存済みの再生位置（設定がオフなら常に 0）。
    private static func resumeSeconds(for video: VideoItem?,
                                      positionStore: PlaybackPositionStore,
                                      settings: PlaybackSettingsStore) -> Double {
        guard settings.resumeFromLastPosition, let video else { return 0 }
        return positionStore.position(for: video.id) ?? 0
    }
}
