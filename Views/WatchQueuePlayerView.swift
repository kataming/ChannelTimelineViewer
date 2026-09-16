import SwiftUI

/// Watch Queue を順番に再生する画面。
///
/// 公式プレイヤー（`YouTubePlayerWebView`）と自動再生スイッチだけを体験版と共有し、
/// 保存（視聴済み・スキップ・メモ・再生位置・チャンネル進捗）には**一切触れない**。
struct WatchQueuePlayerView: View {
    @EnvironmentObject private var settings: PlaybackSettingsStore
    @StateObject private var viewModel: WatchQueuePlayerViewModel
    private let queueName: String

    init(queue: WatchQueueDTO, settings: PlaybackSettingsStore) {
        self.queueName = queue.name
        _viewModel = StateObject(wrappedValue: WatchQueuePlayerViewModel(queue: queue, settings: settings))
    }

    var body: some View {
        Group {
            if let entry = viewModel.current {
                VStack(spacing: 0) {
                    YouTubePlayerWebView(
                        videoId: entry.videoId,
                        autoplayOnLoad: true,
                        startSeconds: 0,
                        onStateChange: { viewModel.handleState($0) },
                        onNearEnd: { viewModel.handleNearEnd(videoId: $0) },
                        onError: { viewModel.handleError($0, videoId: entry.videoId) }
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .id(entry.videoId)

                    List {
                        Section {
                            Text(entry.title.isEmpty ? String(localized: "watchQueue.untitled") : entry.title)
                                .font(.headline)
                            if !entry.channelName.isEmpty {
                                Text(entry.channelName)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Text(viewModel.positionText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.isCompleted {
                            Section {
                                Text("watchQueue.completed").font(.headline)
                                Text("watchQueue.completed.detail")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("watchQueue.restart") { viewModel.restartQueue() }
                            }
                        } else if viewModel.showEndedSuggestion, let next = viewModel.nextEntry {
                            Section {
                                Text(next.title.isEmpty ? String(localized: "watchQueue.untitled") : next.title)
                                    .font(.footnote)
                                Button("watchQueue.playNext") { viewModel.goNext() }
                                    .font(.body.bold())
                            }
                        }

                        Section {
                            // 連続再生はユーザーが自分で選んだときだけ働く（体験版と同じ設定）。
                            Toggle("watchQueue.autoplay", isOn: $settings.autoPlayNext)
                        }

                        Section {
                            navigationButtons
                        }

                        Section("watchQueue.list.header") {
                            ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, item in
                                Button {
                                    viewModel.move(to: index)
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(index + 1)")
                                            .font(.footnote.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title.isEmpty
                                                 ? String(localized: "watchQueue.untitled") : item.title)
                                                .lineLimit(2)
                                            if viewModel.unplayableIds.contains(item.videoId) {
                                                Text("watchQueue.unplayable")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if item.videoId == viewModel.current?.videoId {
                                            Image(systemName: "play.fill").foregroundStyle(.tint)
                                        } else if viewModel.playedIds.contains(item.videoId) {
                                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else {
                ContentUnavailableView("watchQueue.empty.title", systemImage: "list.and.film",
                                       description: Text("watchQueue.empty.detail"))
            }
        }
        .navigationTitle(queueName.isEmpty ? String(localized: "watchQueue.title") : queueName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var navigationButtons: some View {
        HStack {
            Button { viewModel.goFirst() } label: { Image(systemName: "backward.end.fill") }
                .disabled(!viewModel.canGoPrevious)
                .accessibilityLabel(String(localized: "player.nav.first"))
            Spacer()
            Button { viewModel.goPrevious() } label: { Image(systemName: "backward.fill") }
                .disabled(!viewModel.canGoPrevious)
                .accessibilityLabel(String(localized: "player.nav.previous"))
            Spacer()
            Button { viewModel.goNext() } label: { Image(systemName: "forward.fill") }
                .disabled(!viewModel.canGoNext)
                .accessibilityLabel(String(localized: "player.nav.next"))
            Spacer()
            Button { viewModel.goLast() } label: { Image(systemName: "forward.end.fill") }
                .disabled(!viewModel.canGoNext)
                .accessibilityLabel(String(localized: "player.nav.last"))
        }
        .buttonStyle(.borderless)
    }
}
