import Foundation

/// 視聴状態によるフィルター。
enum WatchFilter: String, CaseIterable, Identifiable {
    case all
    case unwatched
    case watched

    var id: String { rawValue }

    /// 画面に出す名前（多言語）。
    var label: String {
        switch self {
        case .all: return String(localized: "filter.all")
        case .unwatched: return String(localized: "filter.unwatched")
        case .watched: return String(localized: "filter.watched")
        }
    }
}

@MainActor
final class VideoListViewModel: ObservableObject {
    @Published private(set) var videos: [VideoItem] = []
    /// true = 古い順（publishedAt 昇順）。デフォルトは古い順。
    @Published var sortAscending = true
    @Published var watchFilter: WatchFilter = .all
    @Published var isLoading = false
    /// 保存済みの一覧を表示したまま、新着だけを確認している最中か。
    @Published private(set) var isCheckingForNew = false
    /// 一覧を最後に取得・更新した日時（保存済みを使ったときはその日時）。
    @Published private(set) var lastUpdatedAt: Date?
    @Published var errorMessage: String?

    let channel: Channel
    private let api: YouTubeAPIClient
    private let cache: VideoListCache

    init(channel: Channel,
         api: YouTubeAPIClient = YouTubeAPIClient(),
         cache: VideoListCache = VideoListCache(),
         preloadedVideos: [VideoItem] = []) {
        self.channel = channel
        self.api = api
        self.cache = cache
        self.videos = preloadedVideos
    }

    /// 並び替えのみ反映した表示用リスト。
    var displayedVideos: [VideoItem] {
        videos.sortedByPublishedDate(ascending: sortAscending)
    }
    var count: Int { videos.count }

    /// 並び替え＋視聴フィルターを適用した最終リスト。
    /// isWatched で視聴判定を注入するためテストしやすい（View からは watchStore.isWatched を渡す）。
    func visibleVideos(isWatched: (String) -> Bool) -> [VideoItem] {
        let sorted = videos.sortedByPublishedDate(ascending: sortAscending)
        switch watchFilter {
        case .all:
            return sorted
        case .unwatched:
            return sorted.filter { !isWatched($0.id) }
        case .watched:
            return sorted.filter { isWatched($0.id) }
        }
    }

    /// 「次に見る」動画：公開日が最も古い未視聴動画。
    /// スキップ指定の動画は「見るつもりがない」ものなので候補から外す。
    func nextUnwatched(isWatched: (String) -> Bool,
                       isSkipped: (String) -> Bool = { _ in false }) -> VideoItem? {
        videos.sortedByPublishedDate(ascending: true)
            .first { !isWatched($0.id) && !isSkipped($0.id) }
    }

    /// 「次に見る」動画が、古い順全体で何本目か（1始まり）。表示用。
    func nextUnwatchedPosition(isWatched: (String) -> Bool,
                               isSkipped: (String) -> Bool = { _ in false }) -> Int? {
        let ascending = videos.sortedByPublishedDate(ascending: true)
        guard let idx = ascending.firstIndex(where: { !isWatched($0.id) && !isSkipped($0.id) }) else {
            return nil
        }
        return idx + 1
    }

    /// 古い順全体での動画リスト（再生画面に渡す基準リスト）と、その中での index。
    func oldestFirst() -> [VideoItem] {
        videos.sortedByPublishedDate(ascending: true)
    }

    func loadIfNeeded() async {
        guard videos.isEmpty, !isLoading else { return }

        // 2回目以降は保存済みの一覧をすぐ表示し、新着だけを確認する。
        if let entry = cache.entry(for: channel.id), !entry.videos.isEmpty,
           entry.uploadsPlaylistId == nil || entry.uploadsPlaylistId == channel.uploadsPlaylistId {
            videos = entry.videos
            lastUpdatedAt = entry.updatedAt
            errorMessage = nil
            await checkForNewVideos()
            return
        }

        await load()
    }

    /// 全件を取得し直す（初回、または差分が大きすぎる場合）。
    func load() async {
        guard let playlistId = channel.uploadsPlaylistId else {
            errorMessage = YouTubeAPIError.uploadsPlaylistNotFound.errorDescription
            return
        }
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }

        do {
            videos = try await api.fetchVideos(playlistId: playlistId)
            if videos.isEmpty {
                errorMessage = String(localized: "list.empty")
            } else {
                storeCache()
            }
        } catch let error as YouTubeAPIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = YouTubeAPIError.unknown.errorDescription
        }
    }

    /// 保存済みの一覧はそのままに、新着だけを取りに行く。
    /// 既知の動画に当たるまでしかページを取らないので、通常は1ページ（quota 1）で済む。
    func checkForNewVideos() async {
        guard let playlistId = channel.uploadsPlaylistId, !isLoading, !isCheckingForNew else { return }
        guard !videos.isEmpty else {
            await load()
            return
        }

        isCheckingForNew = true
        defer { isCheckingForNew = false }

        do {
            let known = Set(videos.map(\.id))
            let result = try await api.fetchNewVideos(playlistId: playlistId, knownVideoIds: known)
            guard result.reachedKnown else {
                // 差分が大きい（久しぶりに開いた等）ので全件取り直す。
                await load()
                return
            }
            if !result.videos.isEmpty {
                videos = (videos + result.videos).uniquedById()
                storeCache()
            } else {
                // 新着なしでも「確認した日時」は更新しておく。
                lastUpdatedAt = Date()
                storeCache()
            }
        } catch {
            // 保存済みの一覧は表示できているので、ここでは失敗を前面に出さない。
        }
    }

    /// 保存済みを捨てて全件取り直す（一覧がおかしくなった時の手動操作用）。
    func reloadAll() async {
        cache.remove(channel.id)
        videos = []
        lastUpdatedAt = nil
        await load()
    }

    private func storeCache() {
        let now = Date()
        cache.save(videos, for: channel.id, uploadsPlaylistId: channel.uploadsPlaylistId, at: now)
        lastUpdatedAt = now
    }

    func toggleSort() { sortAscending.toggle() }

    /// 指定動画の表示リスト上のインデックス（再生画面の開始位置に使う）。
    func displayIndex(of video: VideoItem) -> Int {
        displayedVideos.firstIndex(of: video) ?? 0
    }
}
