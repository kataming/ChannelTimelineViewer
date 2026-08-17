import SwiftUI

struct PlayerView: View {
    // 視聴済み状態の変化で再描画するため EnvironmentObject でも観測する。
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var memoStore: VideoMemoStore
    @EnvironmentObject private var settings: PlaybackSettingsStore
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.openURL) private var openURL
    /// 再生設定（画質・速度・字幕）のシートを表示中か。
    @State private var showPlaybackOptions = false
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
                    // プレイヤーの大きさは変えない（UI が崩れるため）。
                    // 画質・速度・字幕はプレイヤー外の設定画面から操作する。
                    YouTubePlayerWebView(
                        videoId: video.id,
                        autoplayOnLoad: true,
                        startSeconds: viewModel.startSecondsForCurrent,
                        command: viewModel.command,
                        onStateChange: { state in viewModel.handleState(state) },
                        onTimeUpdate: { id, seconds, duration in
                            viewModel.handleTimeUpdate(videoId: id, seconds: seconds, duration: duration)
                        },
                        onOptions: { options in viewModel.handleOptions(options) }
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPlaybackOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("再生設定")
            }
            ToolbarItem(placement: .topBarTrailing) {
                moreMenu
            }
        }
        .sheet(isPresented: $showPlaybackOptions) {
            PlaybackOptionsSheet(viewModel: viewModel)
        }
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
            // 公開日と、一覧の中での位置（例: 2026年2月27日（1,034 / 3,500））
            Text("\(video.publishedAt.formatted(date: .long, time: .omitted))"
                 + "（\(viewModel.positionText)）")
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

            // 主操作：再生中に「このまま次へ進むか」を選べるようにする（常時表示）。
            autoPlayControl

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

    /// 主操作：終了後に次へ進むかどうかを、**再生中に**選べるようにする（既定オフ）。
    /// ユーザーが明示的にオンにした場合だけ、一覧の次の動画へ進む。
    private var autoPlayControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $settings.autoPlayNext) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.autoPlayNext ? "自動再生オン：終了後に次の動画へ"
                                               : "自動再生オフ：終了後に停止")
                        .font(.subheadline.bold())
                    Text(settings.autoPlayNext
                         ? "この一覧の次の動画だけを続けて再生します"
                         : "終了したら「次の動画を再生」ボタンを表示します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.green)
            .accessibilityLabel("終了したら次を自動再生")
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// 補助操作（詳細メニュー）。視聴済みの手動切り替えや「続きから再生」の設定はここに置く。
    @ViewBuilder
    private var moreMenu: some View {
        if let video = viewModel.currentVideo {
            Menu {
                let watched = watchStore.isWatched(video.id)
                Button {
                    watchStore.toggleWatched(video.id)
                } label: {
                    Label(watched ? "視聴済みを解除" : "視聴済みにする",
                          systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
                }

                Toggle(isOn: $settings.resumeFromLastPosition) {
                    Label("続きから再生する", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    viewModel.restartFromBeginning()
                } label: {
                    Label("最初から再生", systemImage: "gobackward")
                }

                Button {
                    if let url = video.watchURL { openURL(url) }
                } label: {
                    Label("YouTubeで開く", systemImage: "play.rectangle.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("その他の操作")
        }
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
            Button {
                viewModel.goNext()
            } label: {
                Label("次の動画を再生", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func controls(for video: VideoItem) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 6) {
                navButton("最初へ", "backward.end.fill", enabled: viewModel.canGoPrevious) {
                    viewModel.goFirst()
                }
                navButton("前へ", "backward.fill", enabled: viewModel.canGoPrevious) {
                    viewModel.goPrevious()
                }
                // 「最初へ」などを押し間違えたとき、移動前の動画・再生位置に戻る。
                navButton("戻る", "arrow.uturn.backward", enabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }
                navButton("次へ", "forward.fill", enabled: viewModel.canGoNext) {
                    viewModel.goNext()
                }
                navButton("最後へ", "forward.end.fill", enabled: viewModel.canGoNext) {
                    viewModel.goLast()
                }
            }

            // 視聴済みは「終了時に自動で付く」ため、ここでは状態表示だけにする。
            // 手動の切り替えは右上の「…」メニュー、または動画一覧のスワイプから行う。
            if watchStore.isWatched(video.id) {
                Label("視聴済み", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 公式プレイヤーの設定メニューはプレイヤー内に開いて枠で切れてしまうため、
            // 同じ操作をアプリ側の画面（プレイヤー外）から行えるようにしている。
            Button {
                showPlaybackOptions = true
            } label: {
                Label("再生設定（速度・字幕）", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                if let url = video.watchURL { openURL(url) }
            } label: {
                Label("YouTubeで開く", systemImage: "play.rectangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    /// 移動ボタン（5つ並べるのでアイコン＋小さな文字で幅を揃える）。
    private func navButton(_ title: String,
                           _ systemImage: String,
                           enabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.body)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }
}
