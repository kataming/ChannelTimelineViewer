import SwiftUI

struct ChannelInputView: View {
    @EnvironmentObject private var favoriteStore: FavoriteChannelStore
    @EnvironmentObject private var sharedLinkRouter: SharedLinkRouter
    @EnvironmentObject private var clipboardDetector: ClipboardLinkDetector
    @EnvironmentObject private var notificationPermission: NotificationPermission
    @StateObject private var viewModel = ChannelInputViewModel()
    @State private var showAbout = false
    @State private var clipboardMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if !viewModel.isAPIConfigured {
                    Section {
                        Label("APIキーが設定されていません", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Config.plist に YOUTUBE_API_KEY を設定してください。設定方法は README を参照してください。")
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
                            Label("共有されたURLを開く", systemImage: "doc.on.clipboard")
                                .font(.body.bold())
                        }
                        Text("共有シートで受け取ったURLがクリップボードにあります。")
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
                            .accessibilityLabel("入力を消去")
                        }
                    }

                    Button(action: startFetch) {
                        HStack {
                            if viewModel.isLoading {
                                ProgressView().padding(.trailing, 4)
                            }
                            Text(viewModel.isLoading ? "取得中..." : "動画を取得")
                        }
                    }
                    .disabled(viewModel.isLoading ||
                              viewModel.urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("チャンネルURL")
                } footer: {
                    // 入力例はプレースホルダで示しているので、ここでは繰り返さない。
                    Text("YouTube アプリや Safari で共有 →「Channel Timeline Viewer」を選ぶと、"
                         + "この画面に「共有されたURLを開く」が表示されます。"
                         + "チャンネル・動画のどちらのURLでも開けます。")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                    }
                }

                if !favoriteStore.favorites.isEmpty {
                    Section {
                        FavoriteChannelsView { favorite in
                            viewModel.open(favorite, favoriteStore: favoriteStore)
                        }
                    } header: {
                        HStack {
                            Text("最近使ったチャンネル")
                            Spacer()
                            Label("左スワイプで削除", systemImage: "arrow.left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    } footer: {
                        Text("行を左にスワイプすると、その1件だけを削除できます。"
                             + "視聴済みの記録は残るので、開き直せば進捗も戻ります。")
                    }
                }

                Section {
                    Text("このアプリは YouTube 公式アプリではありません。再生は YouTube 公式の埋め込みプレイヤーを使用し、ダウンロード・広告回避・バックグラウンド再生は行いません。")
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
                    .accessibilityLabel("このアプリについて")
                }
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
        Task { await viewModel.fetch(favoriteStore: favoriteStore) }
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
                        Label("① 通知を許可してワンタップで開く", systemImage: "bell.badge")
                    }
                } else if notificationPermission.isDenied {
                    Button {
                        notificationPermission.openSettings()
                    } label: {
                        Label("① 設定アプリで通知を許可する", systemImage: "gear")
                    }
                } else {
                    Label("① 通知は許可済み（共有すると通知から開けます）", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("共有先の並び順は iOS が決めるため、アプリからは指定できません。"
                             + "次の手順で「よく使う項目」に登録すると、常に先頭付近に出ます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("1. 共有ボタンを押す\n"
                             + "2. アプリのアイコンが並ぶ行を右端までスクロール →「その他」\n"
                             + "3. 右上の「編集」をタップ\n"
                             + "4. 「Channel Timeline Viewer」の左の「＋」を押す\n"
                             + "5. 「よく使う項目」の中でドラッグして一番上へ →「完了」")
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("② 共有シートの先頭に固定する", systemImage: "pin")
                }

                Button("この案内を閉じる") {
                    sharedLinkRouter.dismissShareTips()
                }
                .font(.footnote)
            } header: {
                Text("共有をもっと速く")
            } footer: {
                Text("iOS の仕様で、共有シートからアプリを直接起動することはできません。"
                     + "通知を許可すると、共有した直後に出る通知をタップするだけで開けます。"
                     + "使うのは共有した直後のこの通知だけで、お知らせや宣伝の通知は送りません。"
                     + "（この案内は「ⓘ」からいつでも確認できます）")
            }
        }
    }

    /// クリップボードにある共有URLを開く（ボタンを押したときだけ中身を読む）。
    private func openFromClipboard() {
        clipboardMessage = nil
        guard let link = clipboardDetector.takeYouTubeLink() else {
            clipboardMessage = "クリップボードに YouTube のURLが見つかりませんでした。URLを貼り付けて取得してください。"
            return
        }
        sharedLinkRouter.markShareHandoffUsed()
        Task { @MainActor in
            await viewModel.openSharedLink(link, favoriteStore: favoriteStore)
        }
    }

    /// 共有された YouTube URL があれば取り込んで一覧を開く。
    private func consumeSharedLinkIfNeeded() {
        Task { @MainActor in
            guard let link = sharedLinkRouter.consume() else { return }
            await viewModel.openSharedLink(link, favoriteStore: favoriteStore)
        }
    }
}
