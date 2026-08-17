import SwiftUI

struct ChannelInputView: View {
    @EnvironmentObject private var favoriteStore: FavoriteChannelStore
    @EnvironmentObject private var sharedLinkRouter: SharedLinkRouter
    @EnvironmentObject private var clipboardDetector: ClipboardLinkDetector
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
                AboutView()
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

    /// クリップボードにある共有URLを開く（ボタンを押したときだけ中身を読む）。
    private func openFromClipboard() {
        clipboardMessage = nil
        guard let link = clipboardDetector.takeYouTubeLink() else {
            clipboardMessage = "クリップボードに YouTube のURLが見つかりませんでした。URLを貼り付けて取得してください。"
            return
        }
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
