import SwiftUI

struct PlayerView: View {
    // 視聴済み状態の変化で再描画するため EnvironmentObject でも観測する。
    @EnvironmentObject private var watchStore: WatchHistoryStore
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var memoStore: VideoMemoStore
    @EnvironmentObject private var settings: PlaybackSettingsStore
    @EnvironmentObject private var skipStore: SkippedVideoStore
    @StateObject private var viewModel: PlayerViewModel
    @Environment(\.openURL) private var openURL
    /// 再生設定（速度・字幕）のシートを表示中か。
    @State private var showPlaybackOptions = false
    /// メモ欄を編集中か。TextEditor は自前で閉じる手段を用意しないと入力状態から抜けられない。
    @FocusState private var isMemoFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    /// いま再生しているチャンネル（画面上部に名前を出す）。
    private let channel: Channel
    /// すぐ再生したときに、裏で読み込んでいる一覧（一覧画面と同じもの）。読み込めたら差し込む。
    private let backgroundList: VideoListViewModel?
    /// 裏で読み込み中の一覧の進み具合（読んだ本数, 全体の本数）。
    @State private var listProgress: (loaded: Int, total: Int)?

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
         skipStore: SkippedVideoStore,
         positionStore: PlaybackPositionStore,
         settings: PlaybackSettingsStore,
         channel: Channel,
         backgroundList: VideoListViewModel? = nil) {
        self.channel = channel
        self.backgroundList = backgroundList
        _viewModel = StateObject(
            wrappedValue: PlayerViewModel(videos: videos,
                                          startIndex: startIndex,
                                          watchStore: watchStore,
                                          skipStore: skipStore,
                                          positionStore: positionStore,
                                          settings: settings,
                                          awaitingList: backgroundList != nil)
        )
    }

    /// プレイヤーと本文（型チェックが重くならないよう body から分けている）。
    @ViewBuilder
    private var playerContent: some View {
        if let video = viewModel.currentVideo {
            // プレイヤーは常に 16:9。大きさは変えない（レイアウトが崩れるため）。
            // 公式プレイヤーの設定メニューはプレイヤーの下端から上へ伸びるので、
            // このサイズのままでも「速度／字幕／その他のオプション」は収まる。
            VStack(spacing: 0) {
                YouTubePlayerWebView(
                    videoId: video.id,
                    autoplayOnLoad: true,
                    startSeconds: viewModel.startSecondsForCurrent,
                    command: viewModel.command,
                    onStateChange: { state in viewModel.handleState(state) },
                    onTimeUpdate: { id, seconds, duration in
                        viewModel.handleTimeUpdate(videoId: id, seconds: seconds, duration: duration)
                    },
                    onNearEnd: { id in viewModel.handleNearEnd(videoId: id) },
                    onOptions: { options in viewModel.handleOptions(options) }
                )
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(Color.black)

                ScrollView {
                    details(for: video)
                }
                // 下にスワイプしてもキーボードを下げられるようにする。
                .scrollDismissesKeyboard(.interactively)
            }
        } else {
            ContentUnavailableView("player.noVideos", systemImage: "film")
        }
    }

    var body: some View {
        playerContent
        // いまどのチャンネルを見ているかが分かるように、画面上部にチャンネル名を出す。
        .navigationTitle(channel.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                repeatToggleButton
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPlaybackOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel(String(localized: "player.options.a11y"))
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
        // 再生中だけ画面の自動ロックを止める（置いたまま見ていて消えるのを防ぐ）。
        // バックグラウンド再生ではないので、アプリを離れれば再生は止まる。
        .onChange(of: viewModel.playerState) { _, state in
            updateScreenSleep(for: state)
        }
        .onChange(of: scenePhase) { _, phase in
            // 前面に戻ってきたときだけ点けたままにする。
            updateScreenSleep(for: phase == .active ? viewModel.playerState : .paused)
        }
        .onDisappear {
            ScreenSleepController.shared.setKeepScreenOn(false)
        }
        .background { backgroundListFeed }
    }

    /// すぐ再生した動画の後ろで、チャンネルの一覧を読み込む。読み込めたら古い順の一覧を差し込み、
    /// 自動再生の「次」（1本新しい動画）が決まる。
    @ViewBuilder
    private var backgroundListFeed: some View {
        if let backgroundList, viewModel.isAwaitingList {
            BackgroundListFeed(list: backgroundList, onChange: feed(from:))
        }
    }

    private func feed(from list: VideoListViewModel) {
        listProgress = list.loadProgress
        let playingId = viewModel.currentVideo?.id
        let hasCurrent = list.videos.contains { $0.id == playingId }
        // 保存済みの一覧に今の動画が無い（投稿されたばかり）ときは、新着の確認が終わるまで待つ。
        if !hasCurrent && (list.isLoading || list.isCheckingForNew) { return }
        if !list.videos.isEmpty {
            viewModel.attachList(list.oldestFirst())
            let ids = list.videos.map(\.id)
            // 一覧画面を通らずに再生したので、保存チャンネルの行の本数もここで入れる。
            progressStore.updateCounts(channelId: channel.id,
                                       totalVideoCount: ids.count,
                                       watchedVideoCount: watchStore.watchedVideoCount(in: ids))
        } else if list.errorMessage != nil {
            // 一覧が読めなかった。1本だけの再生のまま続ける（戻れば一覧画面で再試行できる）。
            viewModel.attachList([])
        }
    }

    private func recordOpened() {
        guard let video = viewModel.currentVideo else { return }
        progressStore.recordOpened(channelId: channel.id, videoId: video.id)
    }

    private func updateScreenSleep(for state: YouTubePlayerState) {
        ScreenSleepController.shared.setKeepScreenOn(
            ScreenSleepController.shouldKeepScreenOn(for: state)
        )
    }

    /// リピートの切り替え（オフ → 1本 → 全体 → オフ）。
    /// オフのときもアイコンは出したままにして、いまどの状態かが分かるようにする。
    private var repeatToggleButton: some View {
        Button {
            settings.repeatMode = settings.repeatMode.next
        } label: {
            RepeatModeBadge(mode: settings.repeatMode)
        }
        // バッジの色をツールバーの着色で上書きされないようにする。
        .buttonStyle(.plain)
        .accessibilityLabel(settings.repeatMode.accessibilityDescription)
        .accessibilityHint(String(localized: "player.repeat.hint"))
    }


    @ViewBuilder
    private func details(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(video.title).font(.headline)
            // どのチャンネルを見ているか（上部のタイトルは長いと省略されるため、ここにも出す）
            Label(channel.title, systemImage: "play.square.stack")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            // 公開日・視聴回数と、一覧の中での位置（例: 2026年2月27日 · 10万回視聴（1,034 / 3,500））
            if viewModel.isAwaitingList {
                Text(video.dateAndViews(.long))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // すぐ再生した動画の裏で、チャンネルの一覧を読み込み中（読み込めると次へ・前へが使える）。
                listLoadingText
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: String(localized: "player.publishedWithPosition.format"),
                            video.dateAndViews(.long),
                            viewModel.positionText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.didAutoAdvance {
                Label("player.autoAdvanced", systemImage: "forward.end.alt.fill")
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
        // メモ欄以外（余白を含む）を押したら入力を終える。
        // ボタンやトグルは自分でタップを処理するので、この指定では反応が変わらない。
        .contentShape(Rectangle())
        .onTapGesture { isMemoFocused = false }
    }

    @ViewBuilder
    private func memoSection(for video: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("player.memo.title", systemImage: "note.text")
                .font(.subheadline.bold())
            TextEditor(text: memoBinding(for: video.id))
                .frame(minHeight: 80)
                .padding(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator))
                )
                .scrollContentBackground(.hidden)
                .focused($isMemoFocused)
                // 改行が入力できる欄なので Return では閉じられない。
                // キーボードの上に「完了」を出して、確実に抜けられるようにする。
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("common.done") { isMemoFocused = false }
                    }
                }
            Text("player.memo.autosave")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 「続きから再生中」の案内と、最初から見直すためのボタン。
    @ViewBuilder
    private var resumeNotice: some View {
        if viewModel.isResumingFromSavedPosition {
            HStack(spacing: 8) {
                Label(String(format: String(localized: "player.resume.notice.format"),
                             PlaybackPosition.timeString(viewModel.startSecondsForCurrent)),
                      systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("player.resume.restart") {
                    viewModel.restartFromBeginning()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
    }

    /// 一覧を裏で読み込み中の表示（例: 動画を取得中… 45%（1,250 / 2,800本））。一覧画面と同じ文言。
    @ViewBuilder
    private var listLoadingText: some View {
        if let progress = listProgress, progress.total > 0 {
            let numbers = NumberFormatter.localizedString
            Text(String(format: String(localized: "list.loading.progress"),
                        numbers(NSNumber(value: min(100, progress.loaded * 100 / progress.total)), .none),
                        numbers(NSNumber(value: progress.loaded), .decimal),
                        numbers(NSNumber(value: progress.total), .decimal)))
        } else {
            Text("list.loading")
        }
    }

    /// 主操作：終了後に次へ進むかどうかを、**再生中に**選べるようにする（既定オン）。
    /// 進む先は一覧の次の動画だけで、いつでもオフにできる。
    ///
    /// 2つの見出しは同じ大きさにそろえ、小さい説明文は置かない（2026-10-09・ユーザー判断。
    /// 再生画面の1画面目に広告まで収めるため。Android の PlaybackToggles と同じ）。
    private var autoPlayControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            // ⚠️ 見出しに状態（オン/オフ）を書かないこと。スイッチの入切と
            //    二重否定になり、「『自動再生オフ』がオフ」＝自動再生オン？と
            //    読めてしまう（2026-09-16・ユーザー指摘）。状態はスイッチ本体が表す。
            Toggle(isOn: $settings.autoPlayNext) {
                Text("player.autoPlay.title")
                    .font(.body)
            }
            .tint(.green)
            .accessibilityLabel(String(localized: "player.autoPlay.a11y"))

            Divider()

            // リピートは画面右上のアイコンで切り替える（ここには置かない）。
            Toggle(isOn: $settings.playUnwatchedOnly) {
                Text("player.unwatchedOnly")
                    .font(.body)
            }
            .tint(.green)
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
                    Label(watched ? String(localized: "player.menu.unmarkWatched")
                                : String(localized: "player.menu.markWatched"),
                          systemImage: watched ? "checkmark.circle.fill" : "checkmark.circle")
                }

                let skipped = skipStore.isSkipped(video.id)
                Button {
                    skipStore.toggleSkipped(video.id)
                } label: {
                    Label(skipped ? String(localized: "player.menu.unskip")
                                : String(localized: "player.menu.skip"),
                          systemImage: skipped ? "forward.end.circle.fill" : "forward.end.circle")
                }

                Toggle(isOn: $settings.resumeFromLastPosition) {
                    Label("player.menu.resume", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    viewModel.restartFromBeginning()
                } label: {
                    Label("player.menu.restart", systemImage: "gobackward")
                }

                Button {
                    if let url = video.watchURL { openURL(url) }
                } label: {
                    Label("player.openInYouTube", systemImage: "play.rectangle.fill")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel(String(localized: "player.menu.a11y"))
        }
    }

    private func endedSuggestion(_ next: VideoItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("player.ended.title")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                RemoteThumbnail(url: next.thumbnailURL, width: 88, height: 50)
                Text(next.title).font(.subheadline).lineLimit(2)
            }
            Button {
                viewModel.goNext()
            } label: {
                Label("player.ended.playNext", systemImage: "play.fill")
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
                navButton(String(localized: "player.nav.first"), "backward.end.fill", enabled: viewModel.canGoPrevious) {
                    viewModel.goFirst()
                }
                navButton(String(localized: "player.nav.previous"), "backward.fill", enabled: viewModel.canGoPrevious) {
                    viewModel.goPrevious()
                }
                // 「最初へ」などを押し間違えたとき、移動前の動画・再生位置に戻る。
                navButton(String(localized: "player.nav.undo"), "arrow.uturn.backward", enabled: viewModel.canGoBack) {
                    viewModel.goBack()
                }
                navButton(String(localized: "player.nav.next"), "forward.fill", enabled: viewModel.canGoNext) {
                    viewModel.goNext()
                }
                navButton(String(localized: "player.nav.last"), "forward.end.fill", enabled: viewModel.canGoNext) {
                    viewModel.goLast()
                }
            }

            // 視聴済みは「終了時に自動で付く」ため、ここでは状態表示だけにする。
            // 手動の切り替えは右上の「…」メニュー、または動画一覧のスワイプから行う。
            VStack(alignment: .leading, spacing: 4) {
                if watchStore.isWatched(video.id) {
                    Label("video.watched", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                if skipStore.isSkipped(video.id) {
                    Label("player.status.skipped", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 広告（無料版のみ）。移動ボタンと「YouTubeでコメントする」の間、本文の中にだけ置く。
            // プレイヤーの上・中には置かない（YouTube API の規約 III.G.1.3）。
            PlayerBannerAdView()

            // 再生設定（速度・字幕）は画面右上のアイコンから開く。
            // ここには置かない（上と重複してノイズになるため）。
            // 全幅のボタンは「YouTubeでコメントする」（埋め込みプレイヤーではコメントできないため）。
            // 開く先は同じ YouTube の動画。「…」メニューの「YouTubeで開く」はそのまま残す
            // （再生できない動画の案内は「…」メニュー側を指している）。
            Button {
                if let url = video.watchURL { openURL(url) }
            } label: {
                Label("player.commentOnYouTube", systemImage: "text.bubble")
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

/// 裏で読み込み中の一覧を見張り、変わるたびに知らせる（すぐ再生したときだけ使う）。
private struct BackgroundListFeed: View {
    @ObservedObject var list: VideoListViewModel
    let onChange: (VideoListViewModel) -> Void

    var body: some View {
        Color.clear
            .task { await list.loadIfNeeded() }
            .onAppear { onChange(list) }
            .onChange(of: list.videos.count) { _, _ in onChange(list) }
            .onChange(of: list.isLoading) { _, _ in onChange(list) }
            .onChange(of: list.isCheckingForNew) { _, _ in onChange(list) }
            .onChange(of: list.errorMessage) { _, _ in onChange(list) }
            .onChange(of: list.loadProgress?.loaded) { _, _ in onChange(list) }
    }
}
