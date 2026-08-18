import SwiftUI

struct VideoListView: View {
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var skipStore: SkippedVideoStore
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
                        Picker("list.menu.sort", selection: $viewModel.sortAscending) {
                            Text("list.sort.oldest").tag(true)
                            Text("list.sort.newest").tag(false)
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
            ProgressView("list.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Text(video.publishedAt.formatted(date: .abbreviated, time: .omitted))
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
