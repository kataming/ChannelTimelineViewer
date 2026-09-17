import SwiftUI

struct ChannelInputView: View {
    @EnvironmentObject private var favoriteStore: FavoriteChannelStore
    @EnvironmentObject private var sharedLinkRouter: SharedLinkRouter
    @EnvironmentObject private var clipboardDetector: ClipboardLinkDetector
    @EnvironmentObject private var notificationPermission: NotificationPermission
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var watchHistoryStore: WatchHistoryStore
    @EnvironmentObject private var skippedVideoStore: SkippedVideoStore
    @EnvironmentObject private var memoStore: VideoMemoStore
    @EnvironmentObject private var positionStore: PlaybackPositionStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var activeChannel: ActiveChannelStore
    @EnvironmentObject private var channelTutorial: ChannelTutorialStore
    @StateObject private var viewModel = ChannelInputViewModel()
    @State private var showAbout = false
    @State private var showPro = false
    @State private var showFreeChannelPicker = false
    @State private var showTutorial = false
    /// 案内を自分で開き直したのか（初回の自動表示と区別する）。
    @State private var tutorialWasManual = false
    @State private var clipboardMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    /// 保存件数の制限とロックの判定に要るもの一式。
    private var context: ChannelAccessContext {
        ChannelAccessContext(
            favorites: favoriteStore,
            activeChannel: activeChannel,
            remover: ChannelDataRemover(
                favoriteStore: favoriteStore,
                progressStore: progressStore,
                videoListCache: VideoListCache(),
                watchHistoryStore: watchHistoryStore,
                skippedVideoStore: skippedVideoStore,
                memoStore: memoStore,
                positionStore: positionStore),
            isPro: pro.isPro)
    }

    /// Pro が無効なのに保存が上限を超えている（＝ロックが起きている）状態か。
    private var hasLockedChannels: Bool {
        favoriteStore.favorites.contains { !context.usableChannelIds.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.isAPIConfigured {
                    Section {
                        Label("api.notConfigured.title", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("api.notConfigured.detail")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                // 共有シートから受け取った URL は、iOS の仕様でアプリを直接開けないため
                // クリップボード経由で渡ってくる。ここでワンタップで開けるようにする。
                if clipboardDetector.hasCandidate {
                    Section {
                        Button {
                            openFromClipboard()
                        } label: {
                            Label("share.openSharedURL", systemImage: "doc.on.clipboard")
                                .font(.body.bold())
                        }
                        Text("share.clipboardHint")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let clipboardMessage {
                    Section {
                        Label(clipboardMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                shareNotificationHint

                Section {
                    HStack(spacing: 8) {
                        TextField("https://www.youtube.com/@handle", text: $viewModel.urlText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .submitLabel(.go)
                            .onSubmit { startFetch() }

                        if !viewModel.urlText.isEmpty {
                            Button {
                                viewModel.urlText = ""
                                viewModel.errorMessage = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "input.clear.a11y"))
                        }
                    }

                    Button(action: startFetch) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().padding(.trailing, 4)
                            }
                            Text(viewModel.isLoading ? "input.fetching" : "input.fetch")
                        }
                    }
                    .disabled(viewModel.isLoading ||
                              viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("input.section.header")
                } footer: {
                    // 入力例はプレースホルダで示しているので、ここでは繰り返さない。
                    Text(String(format: String(localized: "input.section.footer"),
                                AppInfo.displayName))
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }

                proSection

                if hasLockedChannels {
                    Section {
                        Text("pro.disabled.title")
                            .font(.headline)
                            .foregroundStyle(.red)
                        Text("pro.disabled.body")
                            .font(.footnote)
                        Button("pro.disabled.choose") { showFreeChannelPicker = true }
                            .font(.body.bold())
                    }
                }

                if !favoriteStore.favorites.isEmpty {
                    Section {
                        FavoriteChannelsView(
                            usableChannelIds: context.usableChannelIds,
                            onSelect: { favorite in viewModel.open(favorite, context: context) },
                            onAskDelete: { favorite in viewModel.askToDelete(favorite) })
                    } header: {
                        HStack {
                            Text("favorites.section.header")
                            Spacer()
                            Label("favorites.swipeHint", systemImage: "arrow.left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    } footer: {
                        Text("favorites.section.footer")
                    }
                }

                Section {
                    Text("disclaimer.short")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Channel Timeline")
            .navigationDestination(item: $viewModel.resolvedChannel) { channel in
                VideoListView(channel: channel)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel(String(localized: "about.open.a11y"))
                }
            }
            .sheet(isPresented: $showPro) {
                ProView().environmentObject(pro)
            }
            .sheet(isPresented: $showFreeChannelPicker) {
                FreeChannelPickerSheet(
                    favorites: favoriteStore.favorites,
                    activeChannelId: activeChannel.activeChannelId,
                    onSelect: { viewModel.chooseFreeChannel($0, context: context) })
            }
            .sheet(item: $viewModel.prompt) { prompt in
                promptSheet(for: prompt)
            }
            // 起動時と前面復帰時に、購入状態（返金・取消を含む）を確認し直す。
            .task { await pro.refresh() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await pro.refreshEntitlement() }
            }
            // 「チャンネルの追加方法」の案内。
            // 出すのは**初めて追加しようとしたとき**だけ（起動のたびには出さない）。
            // 判定: まだ見ていない かつ 保存チャンネルが1件も無い＝まだ1つも追加できていない人。
            .task {
                guard !channelTutorial.isCompleted,
                      favoriteStore.favorites.isEmpty else { return }
                tutorialWasManual = false
                showTutorial = true
            }
            .sheet(isPresented: $showTutorial) {
                ChannelTutorialView(
                    onComplete: { completeTutorialIfFirstTime() },
                    onSkip: { _ in completeTutorialIfFirstTime() })
            }
            .sheet(isPresented: $showAbout) {
                // シートにも明示的に渡しておく（環境の引き継ぎに依存しない）。
                AboutView(onShowTutorial: {
                    showAbout = false
                    tutorialWasManual = true
                    showTutorial = true
                })
                .environmentObject(notificationPermission)
            }
            // 共有シートから起動された場合（コールドスタート／起動済みのどちらも）に処理する。
            .onAppear { consumeSharedLinkIfNeeded() }
            .onChange(of: sharedLinkRouter.receivedCount) { _, _ in
                consumeSharedLinkIfNeeded()
            }
        }
    }

    private func startFetch() {
        Task { await viewModel.fetch(context: context) }
    }

    /// Pro（複数チャンネル保存）への入口。購入後は状態表示になる。
    @ViewBuilder
    private var proSection: some View {
        Section {
            if pro.isPro {
                Button {
                    showPro = true
                } label: {
                    Label("pro.owned", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                .accessibilityIdentifier("proEntry")
            } else {
                Button {
                    showPro = true
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("pro.entry.title").font(.body.bold())
                        Text("pro.entry.body").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityLabel(String(localized: "pro.open.a11y"))
                .accessibilityIdentifier("proEntry")
            }
        }
    }

    /// 「記録が消える」操作の確認と、ロックの案内。
    @ViewBuilder
    private func promptSheet(for prompt: ChannelInputViewModel.Prompt) -> some View {
        switch prompt {
        case .replace(_, let leavingTitles):
            DestructiveConfirmSheet(
                title: "pro.limit.title",
                warning: String(format: String(localized: "pro.limit.warning.format"), leavingTitles),
                note: "pro.limit.replaceHint") {
                    PrimarySheetButton(title: "pro.limit.viewPro") {
                        viewModel.dismissPrompt()
                        showPro = true
                    }
                    DestructiveSheetButton(title: "pro.limit.replace") {
                        viewModel.confirmReplace(context: context)
                    }
                }

        case .delete(let favorite):
            DestructiveConfirmSheet(
                title: "favorites.delete.title",
                warning: String(format: String(localized: "favorites.delete.warning.format"),
                                favorite.title),
                note: pro.isPro ? nil : "pro.limit.replaceHint") {
                    if !pro.isPro {
                        PrimarySheetButton(title: "pro.limit.viewPro") {
                            viewModel.dismissPrompt()
                            showPro = true
                        }
                    }
                    DestructiveSheetButton(title: "favorites.delete.confirm") {
                        viewModel.confirmDelete(context: context)
                    }
                }

        case .locked(let favorite):
            // ここは削除ではないので、記録が消えるかのような見せ方にはしない。
            DestructiveConfirmSheet(
                title: "pro.locked.title",
                warning: String(localized: "pro.locked.open.body"),
                note: nil) {
                    PrimarySheetButton(title: "pro.limit.viewPro") {
                        viewModel.dismissPrompt()
                        showPro = true
                    }
                    Button("pro.locked.useThis") {
                        viewModel.useLockedChannel(context: context)
                    }
                    .font(.body)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    Text(favorite.title)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
        }
    }

    /// 通知がまだ許可されていないときだけ出す、1行の案内。
    ///
    /// ここには以前「共有をもっと速く」という①②付きの案内枠を置いていたが、
    /// **2026-09-18 に取り外した**（ユーザー指摘）。理由は3つ:
    ///
    /// - チャンネルの追加方法は**初回チュートリアル**（`ChannelTutorialView`）が
    ///   画面つきで教えるようになったので、共有シートの手順を二重に説明していた
    /// - 「共有シートの先頭に固定する」手順は**「ⓘ このアプリについて」に同じものがある**
    ///   （`about.pin.*`）。枠の脚注自身が「ⓘ からいつでも確認できます」と書いていた
    /// - ①② と番号が振られていたため、**初回チュートリアルの続きに見えて紛らわしかった**
    ///
    /// 残したのは**通知の許可だけ**。iOS の仕様で共有シートからアプリを直接起動できず、
    /// 共有直後のローカル通知をタップして開く作りなので、許可が無いと共有の流れが成り立たない
    /// （代わりにクリップボードから開くボタンは残っている）。
    /// **許可済みのときは何も出さない** ― 以前は「① 通知は許可済み」という、
    /// 押せもしない行が常に居座っていた。
    @ViewBuilder
    private var shareNotificationHint: some View {
        if sharedLinkRouter.hasUsedShareHandoff,
           notificationPermission.canAsk || notificationPermission.isDenied {
            Section {
                if notificationPermission.canAsk {
                    Button {
                        Task { await notificationPermission.request() }
                    } label: {
                        Label("about.notify.allow", systemImage: "bell.badge")
                    }
                } else {
                    Button {
                        notificationPermission.openSettings()
                    } label: {
                        Label("about.notify.settings", systemImage: "gear")
                    }
                }
            } footer: {
                Text("shareTips.notify.why")
            }
        }
    }

    /// クリップボードにある共有URLを開く（ボタンを押したときだけ中身を読む）。
    private func openFromClipboard() {
        clipboardMessage = nil
        guard let link = clipboardDetector.takeYouTubeLink() else {
            clipboardMessage = String(localized: "clipboard.notFound")
            return
        }
        sharedLinkRouter.markShareHandoffUsed()
        Task { @MainActor in
            await viewModel.openSharedLink(link, context: context)
        }
    }

    /// 案内を閉じたときの後始末。
    ///
    /// 見終わってもスキップしても「見た」扱いにする（同じ案内を二度出さない）。
    /// ただし**自分で開き直したときは印を変えない**。手で見直しただけで状態が変わると、
    /// 説明が要る人かどうかの区別がつかなくなるため。
    private func completeTutorialIfFirstTime() {
        guard !tutorialWasManual else { return }
        channelTutorial.markCompleted()
    }

    /// 共有された YouTube URL があれば取り込んで一覧を開く。
    private func consumeSharedLinkIfNeeded() {
        Task { @MainActor in
            guard let link = sharedLinkRouter.consume() else { return }
            await viewModel.openSharedLink(link, context: context)
        }
    }
}
