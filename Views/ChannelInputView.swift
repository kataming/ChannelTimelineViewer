import GoogleMobileAds
import SwiftUI

struct ChannelInputView: View {
    @EnvironmentObject private var favoriteStore: FavoriteChannelStore
    @EnvironmentObject private var sharedLinkRouter: SharedLinkRouter
    @EnvironmentObject private var notificationPermission: NotificationPermission
    @EnvironmentObject private var progressStore: ChannelProgressStore
    @EnvironmentObject private var watchHistoryStore: WatchHistoryStore
    @EnvironmentObject private var skippedVideoStore: SkippedVideoStore
    @EnvironmentObject private var memoStore: VideoMemoStore
    @EnvironmentObject private var positionStore: PlaybackPositionStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var activeChannel: ActiveChannelStore
    @EnvironmentObject private var channelTutorial: ChannelTutorialStore
    @EnvironmentObject private var ads: AdsManager
    /// MREC は画面単位で読み込む（Form の行の中で読むと、読み込み前に空の行が出るため）。
    @StateObject private var mrecLoader = BannerAdLoader()
    @StateObject private var viewModel = ChannelInputViewModel()
    /// 「YouTube の共有から追加する」で YouTube へ行っているか（戻ったらコピーしたリンクを開く）。
    @StateObject private var copyGuide = CopyLinkGuideStore()
    @State private var showAbout = false
    @State private var showPro = false
    @State private var showFreeChannelPicker = false
    @State private var showTutorial = false
    /// 案内を自分で開き直したのか（初回の自動表示と区別する）。
    @State private var tutorialWasManual = false
    /// 案内をどのページから始めるか（人気動画／YouTube の共有から追加する）。
    @State private var tutorialStart: ChannelAddGuideView.Start = .popular
    @State private var clipboardMessage: String?
    /// 「YouTube の共有から追加する」から戻ったが、ペーストを許可されず読めなかった。
    @State private var pasteDenied = false
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

    /// MREC を出してよいか（無料版で広告が使えて、保存チャンネルが1件以上ある）。
    private var showsMREC: Bool {
        ads.canShowAds && !favoriteStore.favorites.isEmpty
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

                if pasteDenied {
                    Section {
                        Label("copyguide.ios.pasteDenied", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            Task { @MainActor in await retryCopiedLink() }
                        } label: {
                            Label("copyguide.ios.retry", systemImage: "arrow.clockwise")
                                .font(.body.bold())
                        }
                        Text("copyguide.ios.pasteSetting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("copyguide.ios.pasteSetting.open", systemImage: "gearshape")
                                .font(.footnote)
                        }
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

                addButtons

                // チャンネル URL の入力欄は出さない（2026-10-06・ユーザー判断。Android と同じ）。
                // 共有・コピーから戻ったときは openSharedLink が裏で urlText を入れて読み込むので、
                // 欄が無くても動く。読み込み中は上の主ボタンが「取得中」になる。
                // App Store 用スクリーンショットの UI テストだけは欄に URL を打ち込むので、
                // 起動引数 `-ShowURLField YES` のときだけ出す。
                if showsURLField {
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
                    }
                    // 以前の説明文（input.section.footer）は「共有されたURLを開く」に触れていたので出さない
                    // （その入口は 2026-10-06 に廃止）。この欄自体も撮影のときだけ出る。
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

                // 広告（MREC）は保存チャンネルの一覧の「後ろ」にだけ置く。入力欄・取得ボタン・Pro の案内の
                // 間には入れない。まだ1件も保存していない人（初回）には出さない（読み込みもしない）。
                if showsMREC, let mrec = mrecLoader.loadedView {
                    Section {
                        MRECAdSlot(bannerView: mrec)
                    }
                }

                Section {
                    Text("disclaimer.short")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .task(id: showsMREC) {
                mrecLoader.sync(enabled: showsMREC, unitID: ads.config.mrecUnitID,
                                size: AdSizeMediumRectangle, placement: "mrec")
            }
            .navigationTitle("Channel Timeline")
            .navigationDestination(item: $viewModel.resolvedChannel) { channel in
                // チャンネルごとに別の画面として作る（別チャンネルに替わったら、検索・並び替えの状態を持ち越さない）。
                VideoListView(channel: channel)
                    .id(channel.id)
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
                // 「YouTube の共有から追加する」から戻ってきた（◀ アプリ名・アプリの切り替えのどちらでも）。
                Task { @MainActor in await openCopiedLinkIfReturning() }
            }
            // YouTube にいるあいだにアプリが終了していた場合（コールドスタート）も拾う。
            .task { await openCopiedLinkIfReturning() }
            // 「チャンネルの追加方法」の案内。
            // 出すのは**初めて追加しようとしたとき**だけ（起動のたびには出さない）。
            // 判定: まだ見ていない かつ 保存チャンネルが1件も無い＝まだ1つも追加できていない人。
            .task {
                guard !channelTutorial.isCompleted,
                      favoriteStore.favorites.isEmpty else { return }
                tutorialWasManual = false
                // 初めての人には、まず人気動画から選んでもらう（Android と同じ・2026-10-05）。
                tutorialStart = .popular
                showTutorial = true
            }
            .sheet(isPresented: $showTutorial) {
                ChannelAddGuideView(
                    start: tutorialStart,
                    // 初めての人（自動で出したとき）はスワイプで閉じない。
                    dismissible: tutorialWasManual,
                    loadPopular: { try await viewModel.loadPopularVideos() },
                    onPickVideo: { video in
                        closeTutorial()
                        Task { @MainActor in
                            await viewModel.openPopular(video, context: context)
                        }
                    },
                    onGoToYouTube: {
                        copyGuide.startAwaiting()
                        closeTutorial()
                        openYouTube()
                    },
                    onComplete: { closeTutorial() },
                    onSkip: { _ in closeTutorial() })
            }
            .sheet(isPresented: $showAbout) {
                // シートにも明示的に渡しておく（環境の引き継ぎに依存しない）。
                AboutView(onShowTutorial: {
                    showAbout = false
                    tutorialWasManual = true
                    tutorialStart = .popular
                    showTutorial = true
                })
                .environmentObject(notificationPermission)
                .environmentObject(ads)
            }
            // 共有シートから起動された場合（コールドスタート／起動済みのどちらも）に処理する。
            .onAppear { consumeSharedLinkIfNeeded() }
            .onChange(of: sharedLinkRouter.receivedCount) { _, _ in
                consumeSharedLinkIfNeeded()
            }
        }
    }

    /// チャンネル URL の入力欄を出すか（スクリーンショット撮影の UI テストだけ）。
    private var showsURLField: Bool { UserDefaults.standard.bool(forKey: "ShowURLField") }

    private func startFetch() {
        Task { await viewModel.fetch(context: context) }
    }

    /// 追加の入口（Android の最初の画面と同じ並び・2026-10-05）。
    /// 主ボタン「YouTube の共有から追加する」と、その下に白い背景の「人気動画から選ぶ」。
    @ViewBuilder
    private var addButtons: some View {
        Section {
            Button {
                openGuide(.copyGuide)
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView().tint(.white)
                    }
                    Text(viewModel.isLoading ? "input.fetching" : "tutorial.pick.howto")
                        .font(.body.bold())
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isLoading)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("addFromYouTube")

            Button {
                openGuide(.popular)
            } label: {
                Text("tutorial.pick.title")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color(uiColor: .separator), lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(viewModel.isLoading)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("pickFromPopular")
        }
    }

    /// 最初の画面のボタンから案内を開く（自分で開いたので閉じられる・初回の印は変えない）。
    private func openGuide(_ start: ChannelAddGuideView.Start) {
        tutorialWasManual = true
        tutorialStart = start
        showTutorial = true
    }

    /// 案内のシートを閉じる（初回の自動表示なら「見た」印を付ける）。
    private func closeTutorial() {
        completeTutorialIfFirstTime()
        showTutorial = false
    }

    /// YouTube を開く（特定のチャンネルへは飛ばさない）。YouTube アプリが入っていれば
    /// ユニバーサルリンクでそちらが開き、iOS が左上に「◀ アプリ名」の戻るリンクを出す。
    private func openYouTube() {
        guard let url = URL(string: "https://www.youtube.com/") else { return }
        UIApplication.shared.open(url)
    }

    /// 「YouTube の共有から追加する」で YouTube へ行っていた人が戻ってきたら、コピーしたリンクのチャンネルを開く。
    /// 案内から行っていないとき・何もコピーしていないときは何もしない（クリップボードの中身も読まない）。
    @MainActor
    private func openCopiedLinkIfReturning() async {
        await handleCopied(await copyGuide.takeNewlyCopiedLink())
    }

    /// ［もう一度読み込む］（ペーストを許可しなかったあと）。
    @MainActor
    private func retryCopiedLink() async {
        await handleCopied(copyGuide.retryRead())
    }

    @MainActor
    private func handleCopied(_ outcome: CopyLinkGuideStore.Outcome) async {
        switch outcome {
        case .link(let link):
            clipboardMessage = nil
            pasteDenied = false
            await viewModel.openSharedLink(link, context: context)
        case .notYouTube:
            pasteDenied = false
            clipboardMessage = String(localized: "copyguide.ios.notFound")
        case .pasteDenied:
            clipboardMessage = nil
            pasteDenied = true
        case .none:
            break
        }
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
        case .replace:
            // チャンネル名は並べない（複数保存していた人だと名前が5件6件と並んで長くなり、
            // シートのタイトルに重なっていた。2026-10-06・ユーザー指定の文言）。
            DestructiveConfirmSheet(
                title: "pro.limit.title",
                warning: String(localized: "pro.limit.warning"),
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
