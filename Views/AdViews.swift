import GoogleMobileAds
import os
import SwiftUI

/// 画面に置く広告（アンカー型アダプティブバナーと MREC）。Android 版 `ads/AdViews.kt` と同じ作り。
///
/// どちらも**読み込みに成功してから**場所を取る。取得中・失敗・オフライン・Pro のときは
/// 何も描かない（空白の枠を残さない）。広告の読み込みは画面の表示を待たせない。
///
/// 再生画面には、本文の中（移動ボタンと「YouTubeでコメントする」の間）にだけ置く（`PlayerBannerAdView`）。
/// ⚠️ プレイヤーの上・中・重なる位置には置かない（YouTube API 規約 III.G.1.3）。

/// 広告を1つ作って読み込み、成功したら `loadedView` に入れる。
@MainActor
final class BannerAdLoader: NSObject, ObservableObject, BannerViewDelegate {
    @Published private(set) var loadedView: BannerView?
    private var bannerView: BannerView?
    private var placement = ""
    private let log = Logger(subsystem: "com.deskflowlabs.channeltimelineviewer", category: "Ads")

    /// 出してよいなら読み込み、だめなら外して破棄する（Pro になったとき・同意が取り消されたとき）。
    func sync(enabled: Bool, unitID: String, size: AdSize, placement: String) {
        guard enabled else { reset(); return }
        // 同じ大きさで読み込み済み・読み込み中なら作り直さない。
        if let bannerView, CGSizeEqualToSize(bannerView.adSize.size, size.size) { return }
        reset()
        self.placement = placement
        let view = BannerView(adSize: size)
        view.adUnitID = unitID
        view.rootViewController = AdsManager.topViewController()
        view.delegate = self
        bannerView = view
        view.load(Request())
    }

    func reset() {
        bannerView?.delegate = nil
        bannerView = nil
        loadedView = nil
    }

    nonisolated func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        MainActor.assumeIsolated {
            guard bannerView === self.bannerView else { return }
            loadedView = bannerView
        }
    }

    nonisolated func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        MainActor.assumeIsolated {
            // 表示済みの広告の更新に失敗しただけなら、表示中のものはそのまま残す。
            log.info("\(self.placement, privacy: .public) ad failed to load: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// 読み込み済みの BannerView を SwiftUI に貼る。
private struct BannerViewHost: UIViewRepresentable {
    let bannerView: BannerView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        attach(to: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if bannerView.superview !== uiView { attach(to: uiView) }
    }

    private func attach(to container: UIView) {
        // 同じ広告を別の場所へ貼り直すとき（再描画など）に、前の親から外しておく。
        bannerView.removeFromSuperview()
        container.addSubview(bannerView)
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            bannerView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
    }
}

/// 画面下に固定するアンカー型アダプティブバナー。`.safeAreaInset(edge: .bottom)` に入れて使う
/// （ホームインジケーターに重ねず、一覧の最後の行も広告の上までスクロールできる）。
///
/// 大きさは Google が現在推奨している「大きいアンカー型」（高さは画面の20%以内）。
/// このアプリは iPhone の縦向き専用なので、幅は画面の幅で決める。
struct AnchorAdaptiveBannerView: View {
    @EnvironmentObject private var ads: AdsManager
    @StateObject private var loader = BannerAdLoader()

    private var adSize: AdSize {
        largeAnchoredAdaptiveBanner(width: AdsManager.windowWidth())
    }

    var body: some View {
        VStack(spacing: 0) {
            // 広告が無いときも画面に残る高さ0の部品（読み込みの開始・中止をここで受ける）。
            Color.clear.frame(height: 0)
            if ads.canShowAds, let view = loader.loadedView {
                Divider()
                BannerViewHost(bannerView: view)
                    .frame(width: adSize.size.width, height: adSize.size.height)
                    .accessibilityIdentifier("ad.anchor")
            }
        }
        .frame(maxWidth: .infinity)
        // 不透明にする（半透明だと、ホームインジケーターの下に一覧が透けて見える）。
        .background(loader.loadedView == nil ? Color.clear : Color(.systemBackground))
        .task(id: ads.canShowAds) {
            loader.sync(enabled: ads.canShowAds, unitID: ads.config.bannerUnitID,
                        size: adSize, placement: "anchor")
        }
        .onDisappear { loader.reset() }
    }
}

/// 再生画面の本文の中に置くバナー（320×50）。スクロールと一緒に動く（画面に固定しない）。
///
/// 1画面目に収まるよう、高さが一定の標準バナーにしている。「広告」の表示は、一覧のバナーと
/// 同じく付けない（2026-10-09・ユーザー判断）。移動ボタンを押し間違えないように上下に余白を取る。
/// Android の `PlayerBannerAd` と同じ。
struct PlayerBannerAdView: View {
    @EnvironmentObject private var ads: AdsManager
    @StateObject private var loader = BannerAdLoader()

    var body: some View {
        VStack(spacing: 0) {
            // 広告が無いときも画面に残る高さ0の部品（読み込みの開始・中止をここで受ける）。
            Color.clear.frame(height: 0)
            if ads.canShowAds, let view = loader.loadedView {
                BannerViewHost(bannerView: view)
                    .frame(width: 320, height: 50)
                    .padding(.vertical, 4)
                    .accessibilityIdentifier("ad.player")
            }
        }
        .frame(maxWidth: .infinity)
        .task(id: ads.canShowAds) {
            loader.sync(enabled: ads.canShowAds, unitID: ads.config.playerBannerUnit,
                        size: AdSizeBanner, placement: "player")
        }
        .onDisappear { loader.reset() }
    }
}

/// MREC（300×250）の枠。本文と見分けがつくように「広告」の表示と枠線を付け、中央に置く。
/// 動画やチャンネルの行と同じ見た目（サムネイル付きの行）にはしない。
/// 読み込みは画面側で `BannerAdLoader` を持って行い、読めたものだけをここに渡す
/// （一覧の行の中で読み込むと、空の行が出たり、スクロールのたびに作り直したりするため）。
struct MRECAdSlot: View {
    let bannerView: BannerView

    var body: some View {
        VStack(spacing: 4) {
            Text("ads.label")
                .font(.caption2)
                .foregroundStyle(.secondary)
            BannerViewHost(bannerView: bannerView)
                .frame(width: 300, height: 250)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(.separator)))
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ad.mrec")
    }
}
