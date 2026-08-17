import SwiftUI

struct VideoListView: View {
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var positionStore: PlaybackPositionStore
    @EnvironmentObject private var playbackSettings: PlaybackSettingsStore
    @StateObject private var viewModel: VideoListViewModel

    init(channel: Channel) {
        _viewModel = StateObject(wrappedValue: VideoListViewModel(channel: channel))
    }

    var body: some View {
        content
            .navigationTitle(viewModel.channel.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("並び替え", selection: $viewModel.sortAscending) {
                            Text("古い順").tag(true)
                            Text("新しい順").tag(false)
                        }
                        Picker("表示", selection: $viewModel.watchFilter) {
                            ForEach(WatchFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        Divider()
                        Button {
                            Task { await viewModel.checkForNewVideos() }
                        } label: {
                            Label("新着を確認", systemImage: "arrow.clockwise")
                        }
                        Button {
                            Task {
                                await viewModel.reloadAll()
                                updateProgress()
                            }
                        } label: {
                            Label("すべて再読み込み", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("並び替えと表示")
                }
            }
            .task {
                await viewModel.loadIfNeeded()
                updateProgress()
            }
            // 再生画面で視聴済みにして戻った時などに進捗を更新する。
            .onChange(of: watchStore.watchedCount) { _, _ in updateProgress() }
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
            ProgressView("動画を取得中...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.videos.isEmpty {
            ContentUnavailableView {
                Label("取得できませんでした", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("再試行") { Task { await viewModel.load() } }
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
                Text("新着を確認中…")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if let updatedAt = viewModel.lastUpdatedAt {
            Text("保存済みの一覧を表示中（最終更新 \(updatedAt.formatted(date: .abbreviated, time: .shortened))）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var list: some View {
        List {
            Section {
                progressHeader
                nextToWatchRow
                updateStatusRow
            }

            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, video in
                    NavigationLink {
                        PlayerView(videos: visible, startIndex: index,
                                   watchStore: watchStore,
                                   positionStore: positionStore,
                                   settings: playbackSettings,
                                   channel: viewModel.channel)
                    } label: {
                        VideoRow(video: video, watched: watchStore.isWatched(video.id))
                    }
                    // 視聴済みの手動切り替えはここ（スワイプ）と再生画面の「…」メニューから行う。
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        let watched = watchStore.isWatched(video.id)
                        Button {
                            watchStore.toggleWatched(video.id)
                        } label: {
                            Label(watched ? "未視聴に戻す" : "視聴済み",
                                  systemImage: watched ? "arrow.uturn.backward" : "checkmark.circle.fill")
                        }
                        .tint(watched ? .gray : .green)
                    }
                }
            } header: {
                Text("\(visible.count)本表示 / 全\(totalCount)本")
            }
        }
        .listStyle(.plain)
        // 引き下げで新着だけを取りに行く（全件は取り直さない）。
        .refreshable {
            await viewModel.checkForNewVideos()
            updateProgress()
        }
    }

    @ViewBuilder
    private var progressHeader: some View {
        if totalCount > 0 {
            let rate = Double(watchedCount) / Double(totalCount)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("進捗").font(.subheadline.bold())
                    Spacer()
                    Text("\(watchedCount) / \(totalCount)本（\(Int((rate * 100).rounded()))%）")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: rate).tint(.green)
            }
            .padding(.vertical, 2)
        }
    }

    /// 再開対象：最後に開いた動画が未視聴ならそれ、なければ最も古い未視聴動画。
    private var resumeVideo: VideoItem? {
        if let lastId = progressStore.progress(for: viewModel.channel.id)?.lastOpenedVideoId,
           !watchStore.isWatched(lastId),
           let v = viewModel.videos.first(where: { $0.id == lastId }) {
            return v
        }
        return viewModel.nextUnwatched(isWatched: watchStore.isWatched)
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
                           positionStore: positionStore,
                           settings: playbackSettings,
                           channel: viewModel.channel)
            } label: {
                HStack(spacing: 12) {
                    RemoteThumbnail(url: target.thumbnailURL, width: 88, height: 50)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(isResume ? "続きから" : "次に見る")：第\(index + 1)本目")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(target.title).font(.subheadline).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.tint)
                }
            }
        } else if totalCount > 0 {
            Label("すべて視聴済みです 🎉", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct VideoRow: View {
    let video: VideoItem
    let watched: Bool

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnail(url: video.thumbnailURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(video.publishedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if watched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(.vertical, 4)
    }
}
