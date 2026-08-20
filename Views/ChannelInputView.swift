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
    @StateObject private var viewModel = ChannelInputViewModel()
    @State private var showAbout = false
    @State private var showPro = false
    @State private var showFreeChannelPicker = false
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

                oneTapShareSection

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
            .sheet(isPresented: $showAbout) {
                // シートにも明示的に渡しておく（環境の引き継ぎに依存しない）。
                AboutView()
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

    /// 共有をもっと速く使うための案内（通知の許可と、共有シート先頭への固定）。
    /// 共有を一度でも使った人にだけ出し、「閉じる」で以後は表示しない。
    @ViewBuilder
    private var oneTapShareSection: some View {
        if sharedLinkRouter.hasUsedShareHandoff, !sharedLinkRouter.hasDismissedShareTips {
            Section {
                if notificationPermission.canAsk {
                    Button {
                        Task { await notificationPermission.request() }
                    } label: {
                        Label("shareTips.notify.request", systemImage: "bell.badge")
                    }
                } else if notificationPermission.isDenied {
                    Button {
                        notificationPermission.openSettings()
                    } label: {
                        Label("shareTips.notify.settings", systemImage: "gear")
                    }
                } else {
                    Label("shareTips.notify.granted", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("shareTips.pin.intro")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: String(localized: "shareTips.pin.steps"),
                                    AppInfo.displayName))
                            .font(.caption)
                        Text("shareTips.pin.actionNote")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("shareTips.pin.label", systemImage: "pin")
                }

                Button("shareTips.dismiss") {
                    sharedLinkRouter.dismissShareTips()
                }
                .font(.footnote)
            } header: {
                Text("shareTips.header")
            } footer: {
                Text("shareTips.footer")
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

    /// 共有された YouTube URL があれば取り込んで一覧を開く。
    private func consumeSharedLinkIfNeeded() {
        Task { @MainActor in
            guard let link = sharedLinkRouter.consume() else { return }
            await viewModel.openSharedLink(link, context: context)
        }
    }
}
