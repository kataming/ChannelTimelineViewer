import Foundation

/// Watch Queue（V2）を順番に再生するための状態。
///
/// 体験版・チャンネル再生との違い:
/// - **保存に一切触れない**。視聴済み・スキップ・メモ・再生位置・チャンネル進捗のどれも読み書きしない。
/// - 並び順はサーバー（＝拡張で保存した順）そのままで、並び替え・絞り込みはしない。
/// - 自動で次へ進むのは、自動再生スイッチがオンのときだけ（設定は体験版と共有）。
@MainActor
final class WatchQueuePlayerViewModel: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let videoId: String
        let title: String
        let channelName: String
        var id: String { videoId }
    }

    @Published private(set) var entries: [Entry]
    @Published private(set) var currentIndex: Int
    @Published var playerState: YouTubePlayerState = .unstarted
    /// 自動再生がオフで、動画が終わったときに「次の動画を再生」を出すか。
    @Published private(set) var showEndedSuggestion = false
    /// 最後まで再生し終えたか。
    @Published private(set) var isCompleted = false
    /// 再生できなかった動画（非公開・削除済み・埋め込み不可）。
    @Published private(set) var unplayableIds: Set<String> = []
    /// 再生し終えた動画（印は画面の中だけで、保存はしない）。
    @Published private(set) var playedIds: Set<String> = []

    private let settings: PlaybackSettingsStore
    /// 同じ動画の「終了」を二重に処理しないための記録。
    private var endedHandledVideoId: String?
    /// いま表示している動画が実際に再生され始めたか（切り替え直後の遅れた終了通知を無視する）。
    private var hasStartedCurrent = false

    init(queue: WatchQueueDTO, settings: PlaybackSettingsStore) {
        self.entries = queue.items.map {
            Entry(videoId: $0.videoId,
                  title: $0.title ?? "",
                  channelName: $0.channelName ?? "")
        }
        self.currentIndex = 0
        self.settings = settings
    }

    var current: Entry? { entries.indices.contains(currentIndex) ? entries[currentIndex] : nil }
    var canGoPrevious: Bool { currentIndex > 0 }
    var canGoNext: Bool { currentIndex < entries.count - 1 }
    var positionText: String { "\(entries.isEmpty ? 0 : currentIndex + 1) / \(entries.count)" }
    /// 次に再生する動画（再生できないものは飛ばす）。
    var nextEntry: Entry? {
        guard let index = nextPlayableIndex(after: currentIndex) else { return nil }
        return entries[index]
    }

    // MARK: - 移動

    func move(to index: Int) {
        guard entries.indices.contains(index) else { return }
        currentIndex = index
        showEndedSuggestion = false
        isCompleted = false
        endedHandledVideoId = nil
        hasStartedCurrent = false
        playerState = .unstarted
    }

    func goNext() {
        guard let index = nextPlayableIndex(after: currentIndex) else {
            isCompleted = true
            showEndedSuggestion = false
            return
        }
        move(to: index)
    }

    func goPrevious() { move(to: currentIndex - 1) }
    func goFirst() { move(to: 0) }
    func goLast() { move(to: entries.count - 1) }

    func restartQueue() {
        playedIds.removeAll()
        move(to: 0)
    }

    private func nextPlayableIndex(after index: Int) -> Int? {
        var i = index + 1
        while entries.indices.contains(i) {
            if !unplayableIds.contains(entries[i].videoId) { return i }
            i += 1
        }
        return nil
    }

    // MARK: - プレイヤーからの通知

    func handleState(_ state: YouTubePlayerState) {
        playerState = state
        if state == .playing {
            hasStartedCurrent = true
            showEndedSuggestion = false
        }
        guard state == .ended, let videoId = current?.videoId else { return }
        finish(videoId: videoId)
    }

    /// 終わる直前に呼ばれる。全画面のまま次へ移るために、ここで先回りして切り替える。
    func handleNearEnd(videoId: String) {
        guard settings.autoPlayNext, current?.videoId == videoId, hasStartedCurrent else { return }
        finish(videoId: videoId)
    }

    func handleError(_ code: Int, videoId: String) {
        unplayableIds.insert(videoId)
        // 自動再生がオンなら、止まらずに次へ進む。
        if settings.autoPlayNext { goNext() }
    }

    private func finish(videoId: String) {
        guard endedHandledVideoId != videoId else { return }
        endedHandledVideoId = videoId
        playedIds.insert(videoId)

        if settings.autoPlayNext {
            goNext()
        } else if nextPlayableIndex(after: currentIndex) != nil {
            showEndedSuggestion = true
        } else {
            isCompleted = true
        }
    }
}
