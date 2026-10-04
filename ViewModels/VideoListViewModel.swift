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
    /// 並び順。既定は古い順。人気順は視聴回数の多い順（docs/view-count.md）。
    @Published var sortOrder: VideoSortOrder = .oldest
    @Published var watchFilter: WatchFilter = .all
    /// チャンネル内検索（タイトルの絞り込み）。この画面（＝このチャンネル）の間だけ持つ。保存しない・送らない。
    @Published var isSearching = false
    @Published var searchQuery = ""
    @Published var isLoading = false
    /// 保存済みの一覧を表示したまま、新着だけを確認している最中か。
    @Published private(set) var isCheckingForNew = false
    /// 一覧を最後に取得・更新した日時（保存済みを使ったときはその日時）。
    @Published private(set) var lastUpdatedAt: Date?
    @Published var errorMessage: String?

    let channel: Channel
    private let api: YouTubeAPIClient
    private let cache: VideoListCache
    /// 視聴回数をまとめて取り直した日時（保存済みの一覧に入っている）。
    private var statsUpdatedAt: Date?
    /// 視聴回数をまとめて取り直す間隔。YouTube の規約で、保存した API のデータは
    /// 30 日以内に取り直す必要がある。quota を抑えるため、それより短い 7 日にしておく。
    static let viewCountRefreshInterval: TimeInterval = 7 * 24 * 3600

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
        videos.sorted(by: sortOrder)
    }
    var count: Int { videos.count }

    /// 並び替え＋視聴フィルター＋タイトル検索を適用した最終リスト。
    /// isWatched で視聴判定を注入するためテストしやすい（View からは watchStore.isWatched を渡す）。
    func visibleVideos(isWatched: (String) -> Bool) -> [VideoItem] {
        let sorted = videos.sorted(by: sortOrder)
        let filtered: [VideoItem]
        switch watchFilter {
        case .all:
            filtered = sorted
        case .unwatched:
            filtered = sorted.filter { !isWatched($0.id) }
        case .watched:
            filtered = sorted.filter { isWatched($0.id) }
        }
        // 並び順は変えずに絞るだけ（検索を閉じていれば何もしない）。
        guard isSearching, !searchQuery.isEmpty else { return filtered }
        return filtered.filter { $0.titleMatches(searchQuery) }
    }

    /// 検索語が入っていて、絞り込みが効いているか。
    var isFilteringBySearch: Bool {
        isSearching && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func openSearch() { isSearching = true }

    /// 検索を閉じて全件に戻す（検索語も消す）。
    func closeSearch() {
        isSearching = false
        searchQuery = ""
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
            statsUpdatedAt = entry.statsUpdatedAt
            errorMessage = nil
            await checkForNewVideos()
            await refreshViewCountsIfStale()
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
                statsUpdatedAt = nil
                storeCache()
                // 一覧は先に出し、視聴回数はあとから埋める（取れなくても一覧は使える）
                await refreshViewCounts(for: videos.map(\.id), markRefreshed: true)
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
                await refreshViewCounts(for: result.videos.map(\.id), markRefreshed: false)
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
        statsUpdatedAt = nil
        await load()
    }

    /// 視聴回数の取り直しが要るか（一度も取っていない、または 7 日以上たった）。
    func needsViewCountRefresh(now: Date = Date()) -> Bool {
        guard let statsUpdatedAt else { return true }
        return now.timeIntervalSince(statsUpdatedAt) >= Self.viewCountRefreshInterval
    }

    /// 保存済みの視聴回数が古ければ、全件まとめて取り直す。
    func refreshViewCountsIfStale(now: Date = Date()) async {
        guard !videos.isEmpty, needsViewCountRefresh(now: now) else { return }
        await refreshViewCounts(for: videos.map(\.id), markRefreshed: true)
    }

    /// 視聴回数を取って反映する。失敗しても一覧はそのまま使えるので、表に出さない。
    private func refreshViewCounts(for ids: [String], markRefreshed: Bool) async {
        guard !ids.isEmpty,
              let counts = try? await api.fetchViewCounts(videoIds: ids) else { return }
        videos = videos.applyingViewCounts(counts)
        if markRefreshed { statsUpdatedAt = Date() }
        storeCache()
    }

    private func storeCache() {
        let now = Date()
        cache.save(videos, for: channel.id, uploadsPlaylistId: channel.uploadsPlaylistId, at: now,
                   statsUpdatedAt: statsUpdatedAt)
        lastUpdatedAt = now
    }

    /// 指定動画の表示リスト上のインデックス（再生画面の開始位置に使う）。
    func displayIndex(of video: VideoItem) -> Int {
        displayedVideos.firstIndex(of: video) ?? 0
    }
}
