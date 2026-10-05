import SwiftUI

/// 「チャンネルの追加」のシート（Android の `ChannelTutorialSheet` に当たる）。
///
/// 中身は3ページで、Android と同じ順につながる:
///
/// 1. **人気動画から選ぶ**（`PopularVideoPickerPage`）… 選んだ動画のチャンネルをそのまま開く
/// 2. **YouTube の共有から追加する**（`CopyLinkGuidePage`）… YouTube で［共有］→［コピー］して、
///    iOS が左上に出す「◀ アプリ名」で戻ってもらう。戻ったらコピーしたリンクのチャンネルを開く
/// 3. **共有メニューからこのアプリを選ぶ方法**（`ChannelTutorialView`・従来の5ステップ）
///
/// 初めての人（保存チャンネル0件で自動で出したとき）は、下へのスワイプでは閉じない
/// （閉じても何もできない画面が残るだけなので、選ぶか YouTube から追加する方へ進んでもらう）。
struct ChannelAddGuideView: View {
    enum Start {
        /// 人気動画の一覧から始める（初回・「人気動画から選ぶ」・「このアプリについて」から）。
        case popular
        /// 「YouTube の共有から追加する」から始める（最初の画面の主ボタン）。
        case copyGuide
    }

    enum Page: Hashable {
        case copyGuide
        case steps
    }

    let start: Start
    /// スワイプ・「閉じる」で閉じられるか。初めての人には false。
    let dismissible: Bool
    let loadPopular: () async throws -> [PopularVideo]
    let onPickVideo: (PopularVideo) -> Void
    /// 「YouTube の共有から追加する」の［YouTube を開く］。呼び出し側で待ち状態にし、シートを閉じて YouTube を開く。
    let onGoToYouTube: () -> Void
    /// 従来の手順の最後（YouTube を開いて試す）まで進んだ。
    let onComplete: () -> Void
    /// 途中でやめた。何手順目だったか（人気動画の画面なら 0）。
    let onSkip: (Int) -> Void

    @State private var path: [Page] = []

    var body: some View {
        NavigationStack(path: $path) {
            root
                .navigationDestination(for: Page.self) { page in
                    switch page {
                    case .copyGuide:
                        CopyLinkGuidePage(
                            onGoToYouTube: onGoToYouTube,
                            onShowSteps: { path.append(.steps) },
                            onClose: nil)
                    case .steps:
                        ChannelTutorialView(onComplete: onComplete, onSkip: onSkip)
                    }
                }
        }
        .interactiveDismissDisabled(!dismissible)
    }

    @ViewBuilder
    private var root: some View {
        switch start {
        case .popular:
            PopularVideoPickerPage(
                loadPopular: loadPopular,
                onPickVideo: onPickVideo,
                onShowCopyGuide: { path.append(.copyGuide) },
                onClose: dismissible ? { onSkip(0) } : nil)
        case .copyGuide:
            CopyLinkGuidePage(
                onGoToYouTube: onGoToYouTube,
                onShowSteps: { path.append(.steps) },
                onClose: { onSkip(0) })
        }
    }
}

/// その国でいま人気の動画を並べ、選んだ動画のチャンネルをそのまま開く。
/// URL を持っていない人でも、アプリの中だけで「チャンネルの動画を古い順に見る」まで行けるようにする。
/// 読み込めなかったときは、YouTube から追加する方へ案内する。
private struct PopularVideoPickerPage: View {
    let loadPopular: () async throws -> [PopularVideo]
    let onPickVideo: (PopularVideo) -> Void
    let onShowCopyGuide: () -> Void
    let onClose: (() -> Void)?

    @State private var videos: [PopularVideo]?
    @State private var failed = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("tutorial.pick.body")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if failed {
                    Text("tutorial.pick.error")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let videos {
                    ForEach(videos) { video in
                        Button {
                            onPickVideo(video)
                        } label: {
                            PopularVideoRow(video: video)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("tutorial.pick.loading")
                    }
                    .padding(.vertical, 24)
                }

                Text("tutorial.pick.other")
                    .font(.subheadline.bold())
                    .padding(.top, 8)
                Button(action: onShowCopyGuide) {
                    Text("tutorial.pick.howto")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(20)
        }
        .navigationTitle(Text("tutorial.pick.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("tutorial.close", action: onClose)
                }
            }
        }
        .task {
            guard videos == nil, !failed else { return }
            do {
                let loaded = try await loadPopular()
                videos = loaded
                failed = loaded.isEmpty
            } catch {
                failed = true
            }
        }
    }
}

private struct PopularVideoRow: View {
    let video: PopularVideo

    var body: some View {
        HStack(spacing: 12) {
            RemoteThumbnail(url: video.thumbnailURL, width: 144, height: 81)
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(video.channelTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// 「YouTube の共有から追加する」（iOS 版）。
///
/// Android は通知と画面の端のボタンで戻ってもらうが、iOS はどちらもできない
/// （他のアプリの上に重ねて表示する仕組みが無く、裏でクリップボードも読めない）。
/// 代わりに、アプリから YouTube を開くと iOS が左上に「◀ アプリ名」の戻るリンクを出すので、③はそれで戻ってもらう。
/// 戻ったときの読み取りは `CopyLinkGuideStore`。
private struct CopyLinkGuidePage: View {
    let onGoToYouTube: () -> Void
    let onShowSteps: () -> Void
    let onClose: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("copyguide.ios.title")
                    .font(.title2.bold())
                Text(String(format: String(localized: "copyguide.ios.step1"), AppInfo.displayName))
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("copyguide.ios.pasteNote")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onGoToYouTube) {
                    Text("copyguide.ios.open")
                        .font(.body.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)

                Button(action: onShowSteps) {
                    Text(String(format: String(localized: "copyguide.ios.legacy"), AppInfo.displayName))
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text("tutorial.pick.howto"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("tutorial.close", action: onClose)
                }
            }
        }
    }
}
