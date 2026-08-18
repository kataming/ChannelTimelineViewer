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

                if !favoriteStore.favorites.isEmpty {
                    Section {
                        FavoriteChannelsView { favorite in
                            viewModel.open(favorite, favoriteStore: favoriteStore)
                        }
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
