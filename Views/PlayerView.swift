import SwiftUI

struct PlayerView: View {
    // 視聴済み状態の変化で再描画するため EnvironmentObject でも観測する。
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var memoStore: VideoMemoStore
    @EnvironmentObject private var settings: PlaybackSettingsStore
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.openURL) private var openURL
    private let channelId: String

    /// 動画ごとのメモを直接読み書きする Binding（入力即保存・日本語OK）。
    private func memoBinding(for videoId: String) -> Binding<String> {
        Binding(
            get: { memoStore.memo(for: videoId) },
            set: { memoStore.setMemo($0, for: videoId) }
        )
    }

    init(videos: [VideoItem],
         startIndex: Int,
         watchStore: WatchHistoryStore,
         positionStore: PlaybackPositionStore,
         settings: PlaybackSettingsStore,
         channelId: String) {
        self.channelId = channelId
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(videos: videos,
                                          startIndex: startIndex,
                                          watchStore: watchStore,
                                          positionStore: positionStore,
                                          settings: settings)
        )
    }

    var body: some View {
        Group {
            if let video = viewModel.currentVideo {
                VStack(spacing: 0) {
                    YouTubePlayerWebView(
                        videoId: video.id,
                        autoplayOnLoad: true,
                        startSeconds: viewModel.startSecondsForCurrent,
                        seekRequest: viewModel.seekRequest,
                        onStateChange: { state in viewModel.handleState(state) },
                        onTimeUpdate: { id, seconds, duration in
                            viewModel.handleTimeUpdate(videoId: id, seconds: seconds, duration: duration)
                        }
                    )
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)

                    ScrollView {
                        details(for: video)
                    }
                }
            } else {
                ContentUnavailableView("動画がありません", systemImage: "film")
            }
        }
        .navigationTitle("再生")
        .navigationBarTitleDisplayMode(.inline)
        // 「最後に開いた動画」を記録（続きから見る用）。
        .task { recordOpened() }
        .onChange(of: viewModel.currentIndex) { _, _ in recordOpened() }
    }

    private func recordOpened() {
        guard let video = viewModel.currentVideo else { return }
        progressStore.recordOpened(channelId: channelId, videoId: video.id)
    }

    @ViewBuilder
    private func details(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.title).font(.headline)
            Text(video.publishedAt.formatted(date: .long, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.didAutoAdvance {
                Label("自動再生で次の動画に進みました", systemImage: "forward.end.alt.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            resumeNotice

            if viewModel.showEndedSuggestion, let next = viewModel.nextVideo {
                endedSuggestion(next)
            }

            playbackSettings

            controls(for: video)

            memoSection(for: video)

            if !video.description.isEmpty {
                Divider()
                Text(video.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private func memoSection(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("メモ（シリーズ視聴・学習用）", systemImage: "note.text")
                .font(.subheadline.bold())
            TextEditor(text: memoBinding(for: video.id))
                .frame(minHeight: 80)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator))
                )
                .scrollContentBackground(.hidden)
            Text("入力すると自動保存されます。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 「続きから再生中」の案内と、最初から見直すためのボタン。
    @ViewBuilder
    private var resumeNotice: some View {
        if viewModel.isResumingFromSavedPosition {
            HStack(spacing: 8) {
                Label("前回の続き（\(PlaybackPosition.timeString(viewModel.startSecondsForCurrent))）から再生中",
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("最初から") {
                    viewModel.restartFromBeginning()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    /// 再生の挙動（自動再生・続きから）の切り替え。
    private var playbackSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $settings.autoPlayNext) {
                Label("終了したら次を自動再生", systemImage: "forward.end.alt.fill")
                    .font(.subheadline)
            }
            Toggle(isOn: $settings.resumeFromLastPosition) {
                Label("続きから再生する", systemImage: "clock.arrow.circlepath")
                    .font(.subheadline)
            }
            Text("自動再生をオフにすると、終了時に「次の動画を再生」ボタンを表示します。"
                 + "どちらの設定でもバックグラウンド再生は行いません（アプリを閉じると停止します）。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func endedSuggestion(_ next: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("再生が終了しました。次の動画:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                RemoteThumbnail(url: next.thumbnailURL, width: 88, height: 50)
                Text(next.title).font(.subheadline).lineLimit(2)
            }
            HStack(spacing: 12) {
                Button {
                    viewModel.goNext()
                } label: {
                    Label("次の動画を再生", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    settings.autoPlayNext = true
                    viewModel.goNext()
                } label: {
                    Label("自動再生をオン", systemImage: "forward.end.alt.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func controls(for video: VideoItem) -> some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    viewModel.goPrevious()
                } label: {
                    Label("前へ", systemImage: "backward.fill")
                }
                .disabled(!viewModel.canGoPrevious)

                Spacer()

                Button {
                    viewModel.goNext()
                } label: {
                    Label("次へ", systemImage: "forward.fill")
                }
                .disabled(!viewModel.canGoNext)
            }
            .buttonStyle(.bordered)

            let watched = watchStore.isWatched(video.id)
            Button {
                watchStore.toggleWatched(video.id)
            } label: {
                Label(watched ? "視聴済みを解除" : "視聴済みにする",
                      systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(watched ? .green : .accentColor)

            Button {
                if let url = video.watchURL { openURL(url) }
            } label: {
                Label("YouTubeで開く", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}
