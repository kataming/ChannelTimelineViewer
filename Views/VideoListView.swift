import SwiftUI

struct VideoListView: View {
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var skipStore: SkippedVideoStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var positionStore: PlaybackPositionStore
    @EnvironmentObject private var playbackSettings: PlaybackSettingsStore
    @StateObject private var viewModel: VideoListViewModel
    @FocusState private var searchFocused: Bool
    /// メニューの「一番上へ」「一番下へ」。同じ方向を続けて押しても動くよう、押すたびに番号を変える。
    @State private var scrollRequest: ScrollRequest?

    private struct ScrollRequest: Equatable {
        let edge: VideoListScrollTarget.Edge
        let serial: Int
    }

    init(channel: Channel) {
        _viewModel = StateObject(wrappedValue: VideoListViewModel(channel: channel))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.channel.title)
            .navigationBarTitleDisplayMode(.inline)
            // 動画一覧の下に固定するバナー。再生画面には置かない（プレイヤーや操作に重ねない）。
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AnchorAdaptiveBannerView()
            }
            .toolbar {
                // チャンネル内検索（タイトルの絞り込み・docs/channel-search.md）。開いている間は × で閉じる。
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if viewModel.isSearching { viewModel.closeSearch() } else { viewModel.openSearch() }
                    } label: {
                        Image(systemName: viewModel.isSearching ? "xmark" : "magnifyingglass")
                    }
                    .accessibilityLabel(viewModel.isSearching ? String(localized: "list.search.close")
                                                              : String(localized: "list.search.open"))
                    .disabled(viewModel.videos.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("list.menu.sort", selection: $viewModel.sortOrder) {
                            Text("list.sort.oldest").tag(VideoSortOrder.oldest)
                            Text("list.sort.newest").tag(VideoSortOrder.newest)
                            Text("list.sort.popular").tag(VideoSortOrder.popular)
                        }
                        Picker("list.menu.show", selection: $viewModel.watchFilter) {
                            ForEach(WatchFilter.allCases) { f in
                                Text(f.label).tag(f)
                            }
                        }
                        Divider()
                        Button {
                            Task { await viewModel.checkForNewVideos() }
                        } label: {
                            Label("list.menu.checkNew", systemImage: "arrow.clockwise")
                        }
                        Button {
                            Task {
                                await viewModel.reloadAll()
                                updateProgress()
                            }
                        } label: {
                            Label("list.menu.reloadAll", systemImage: "arrow.triangle.2.circlepath")
                        }
                        // 本数の多いチャンネル向け（5,000本超もある）。アニメーションなしで一気に飛ぶ。
                        Divider()
                        Button {
                            requestScroll(.top)
                        } label: {
                            Label("list.menu.top", systemImage: "arrow.up.to.line")
                        }
                        .disabled(viewModel.videos.isEmpty)
                        Button {
                            requestScroll(.bottom)
                        } label: {
                            Label("list.menu.bottom", systemImage: "arrow.down.to.line")
                        }
                        .disabled(viewModel.videos.isEmpty)
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel(String(localized: "list.menu.a11y"))
                }
            }
            .task {
                await viewModel.loadIfNeeded()
                updateProgress()
            }
            // 再生画面で視聴済みにして戻った時などに進捗を更新する。
            .onChange(of: watchStore.watchedCount) { _, _ in updateProgress() }
    }

    private func requestScroll(_ edge: VideoListScrollTarget.Edge) {
        scrollRequest = ScrollRequest(edge: edge, serial: (scrollRequest?.serial ?? 0) + 1)
    }

    /// このチャンネルの進捗（総数・視聴済み数）を ChannelProgressStore に反映する。
    private func updateProgress() {
        guard !viewModel.videos.isEmpty else { return }
        let ids = viewModel.videos.map(\.id)
        progressStore.updateCounts(
            channelId: viewModel.channel.id,
            totalVideoCount: ids.count,
            watchedVideoCount: watchStore.watchedVideoCount(in: ids)
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.videos.isEmpty {
            // 全体の本数が分かったら、何％読んだかを出す（例: 動画を取得中… 45%（1,250 / 2,800本））。
            // Android の VideoListScreen と同じ。
            if let progress = viewModel.loadProgress, progress.total > 0 {
                let numbers = NumberFormatter.localizedString
                ProgressView(value: Double(progress.loaded), total: Double(progress.total)) {
                    Text(String(format: String(localized: "list.loading.progress"),
                                String(progress.loaded * 100 / progress.total),
                                numbers(NSNumber(value: progress.loaded), .decimal),
                                numbers(NSNumber(value: progress.total), .decimal)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("list.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
            ContentUnavailableView {
                Label("list.error.title", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("common.retry") { Task { await viewModel.load() } }
            }
        } else {
            list
        }
    }

    private var visible: [VideoItem] {
        viewModel.visibleVideos(isWatched: watchStore.isWatched)
    }
    private var totalCount: Int { viewModel.videos.count }
    private var watchedCount: Int {
        watchStore.watchedVideoCount(in: viewModel.videos.map(\.id))
    }

    /// 保存済みの一覧を使っていることが分かる小さな表示。
    @ViewBuilder
    private var updateStatusRow: some View {
        if viewModel.isCheckingForNew {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("list.checkingNew")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let updatedAt = viewModel.lastUpdatedAt {
            Text(String(format: String(localized: "list.cached.format"),
                 updatedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 検索欄（検索中だけ一覧の一番上に出る）。
    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("list.search.placeholder", text: $viewModel.searchQuery)
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { searchFocused = false }
            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "list.search.clear"))
            }
        }
        .task { searchFocused = true }
    }

    private var list: some View {
        // 絞り込み（並び替え＋視聴フィルター＋検索）は1回だけ計算して使い回す。
        let visible = self.visible
        return ScrollViewReader { proxy in
        List {
            if viewModel.isSearching {
                Section {
                    searchRow.id(VideoListScrollTarget.searchRowID)
                }
            }

            Section {
                progressHeader
                nextToWatchRow
                updateStatusRow
            }

            Section {
                if visible.isEmpty && viewModel.isFilteringBySearch {
                    Text("list.search.empty")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, video in
                    NavigationLink {
                        PlayerView(videos: visible, startIndex: index,
                                   watchStore: watchStore,
                                   skipStore: skipStore,
                                   positionStore: positionStore,
                                   settings: playbackSettings,
                                   channel: viewModel.channel)
                    } label: {
                        VideoRow(video: video,
                                 watched: watchStore.isWatched(video.id),
                                 skipped: skipStore.isSkipped(video.id))
                    }
                    // 視聴済みの手動切り替えはここ（スワイプ）と再生画面の「…」メニューから行う。
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        let watched = watchStore.isWatched(video.id)
                        Button {
                            watchStore.toggleWatched(video.id)
                        } label: {
                            Label(watched ? String(localized: "video.markUnwatched") : String(localized: "video.watched"),
                                  systemImage: watched ? "arrow.uturn.backward" : "checkmark.circle.fill")
                        }
                        .tint(watched ? .gray : .green)
                    }
                    // スキップ指定（自動再生で飛ばす）。
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        let skipped = skipStore.isSkipped(video.id)
                        Button {
                            skipStore.toggleSkipped(video.id)
                        } label: {
                            Label(skipped ? String(localized: "video.unskip") : String(localized: "video.skip"),
                                  systemImage: skipped ? "arrow.uturn.backward" : "forward.end.circle.fill")
                        }
                        .tint(skipped ? .gray : .orange)
                    }
                }
            } header: {
                Text(String(format: String(localized: "list.count.format"), "\(visible.count)", "\(totalCount)"))
            }
        }
        .listStyle(.plain)
        // 引き下げで新着だけを取りに行く（全件は取り直さない）。
        .refreshable {
            await viewModel.checkForNewVideos()
            updateProgress()
        }
        // メニューの「一番上へ」「一番下へ」。数千本でも待たせないよう、アニメーションなしで飛ぶ。
        .onChange(of: scrollRequest) { _, request in
            guard let request,
                  let target = VideoListScrollTarget.id(
                      for: request.edge,
                      isSearching: viewModel.isSearching,
                      hasProgressRow: totalCount > 0,
                      visibleVideoIds: visible.map(\.id)) else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(target, anchor: request.edge == .top ? .top : .bottom)
            }
        }
        }
    }

    @ViewBuilder
    private var progressHeader: some View {
        if totalCount > 0 {
            let rate = Double(watchedCount) / Double(totalCount)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("progress.title").font(.subheadline.bold())
                    Spacer()
                    Text(String(format: String(localized: "progress.count.format"),
                         "\(watchedCount)", "\(totalCount)", "\(Int((rate * 100).rounded()))"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: rate).tint(.green)
            }
            .padding(.vertical, 2)
            .id(VideoListScrollTarget.progressRowID)
        }
    }

    /// 再開対象：最後に開いた動画が未視聴ならそれ、なければ最も古い未視聴動画。
    private var resumeVideo: VideoItem? {
        if let lastId = progressStore.progress(for: viewModel.channel.id)?.lastOpenedVideoId,
           !watchStore.isWatched(lastId),
           let v = viewModel.videos.first(where: { $0.id == lastId }) {
            return v
        }
        return viewModel.nextUnwatched(isWatched: watchStore.isWatched,
                                       isSkipped: skipStore.isSkipped)
    }

    @ViewBuilder
    private var nextToWatchRow: some View {
        if let target = resumeVideo {
            let oldest = viewModel.oldestFirst()
            let index = oldest.firstIndex(of: target) ?? 0
            let isResume = progressStore.progress(for: viewModel.channel.id)?.lastOpenedVideoId == target.id
            NavigationLink {
                PlayerView(videos: oldest, startIndex: index,
                           watchStore: watchStore,
                           skipStore: skipStore,
                           positionStore: positionStore,
                           settings: playbackSettings,
                           channel: viewModel.channel)
            } label: {
                HStack(spacing: 12) {
                    RemoteThumbnail(url: target.thumbnailURL, width: 88, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(format: String(localized: isResume ? "list.next.resume.format"
                                                                     : "list.next.new.format"),
                                     "\(index + 1)"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text(target.title).font(.subheadline).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.tint)
                }
            }
        } else if totalCount > 0 {
            Label("list.allWatched", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct VideoRow: View {
    let video: VideoItem
    let watched: Bool
    /// 自動再生で飛ばす指定。視聴済みとは別の状態。
    var skipped: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnail(url: video.thumbnailURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(2)
                // 公開日と視聴回数（例: 2018年4月15日 · 10万回視聴）
                Text(video.dateAndViews(.abbreviated))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            // 上が視聴済み（緑）、下がスキップ（オレンジ）。
            VStack(spacing: 4) {
                if watched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel(String(localized: "video.watched"))
                }
                if skipped {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel(String(localized: "video.skip"))
                }
            }
        }
        .padding(.vertical, 4)
        // 1行を1要素にまとめる。VoiceOver が行ごとに読めるようになり、
        // 数千本のチャンネルでもアクセシビリティのツリーが膨らまない。
        .accessibilityElement(children: .combine)
    }
}
