import SwiftUI
import WebKit

/// YouTube プレイヤーの状態。
enum YouTubePlayerState: Int {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5
}

/// YouTube 公式の埋め込みプレイヤー（IFrame Player）を WKWebView で表示する。
/// 動画ファイルの直接再生・ダウンロードは行わず、公式プレイヤーをそのまま埋め込む。
///
/// ## なぜ自前のページ（GitHub Pages）を経由するのか
///
/// YouTube は 2025 年後半以降、埋め込みプレイヤーのホストを HTTP Referer で厳格に検証する。
/// iOS の WKWebView は、
///   - 自前 HTML を `loadHTMLString(_:baseURL:)` で読み込む方式
///   - `https://www.youtube.com/embed/<id>` を直接開く方式
/// のどちらでも YouTube が要求する形の Referer を送らないため、
///   「この動画は再生できません（エラーコード 152-4）」
///   「Error 153 - Video player configuration error」
/// となって再生できない。実際に本アプリでも両方式で再現し、対象動画は Data API で
/// embeddable=true / public / 地域・年齢制限なしであることを確認している
/// （＝動画側の制限ではない）。Capacitor / React Native など他の WebView でも同じ事象が
/// 報告されており、確立した回避策は「実在する HTTPS オリジンに置いた中継ページから埋め込む」。
///
/// 本アプリは GitHub Pages（プライバシーポリシー等の公開に既に使用）に
/// `player.html` を置き、それを WKWebView で開く。Referer が実在オリジンになるため
/// 検証を通る。表示されるのは変わらず公式プレイヤーで、ダウンロード・独自再生・
/// 広告回避は一切行わない。
struct YouTubePlayerWebView: UIViewRepresentable {
    /// 中継ページの URL。GitHub Pages（docs/player.html）で公開している。
    static let playerPageURL = "https://kataming.github.io/ChannelTimelineViewer/player.html"

    let videoId: String
    /// 初回読み込み後に自動再生するか。
    var autoplayOnLoad: Bool = false
    var onStateChange: ((YouTubePlayerState) -> Void)? = nil
    /// 再生できなかった場合に呼ばれる（IFrame API のエラーコード）。
    var onError: ((Int) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ytHandler")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.webView = webView
        context.coordinator.load(videoId: videoId)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // videoId が変わったときだけ差し替える。ページ再読み込みは不要。
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.change(videoId: videoId, autoplay: autoplayOnLoad)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytHandler")
    }

    /// 中継ページの URL を組み立てる。
    static func pageURL(videoId: String, autoplay: Bool) -> URL? {
        var comps = URLComponents(string: playerPageURL)
        comps?.queryItems = [
            URLQueryItem(name: "v", value: sanitize(videoId)),
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
        ]
        return comps?.url
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let parent: YouTubePlayerWebView
        weak var webView: WKWebView?
        private(set) var loadedVideoId: String?

        init(_ parent: YouTubePlayerWebView) { self.parent = parent }

        func load(videoId: String) {
            loadedVideoId = videoId
            guard let url = YouTubePlayerWebView.pageURL(
                videoId: videoId, autoplay: parent.autoplayOnLoad
            ) else { return }
            webView?.load(URLRequest(url: url))
        }

        /// ページを読み直さずに動画だけ差し替える。
        func change(videoId: String, autoplay: Bool) {
            loadedVideoId = videoId
            let id = YouTubePlayerWebView.sanitize(videoId)
            let fn = autoplay ? "loadVideo" : "cueVideo"
            webView?.evaluateJavaScript("\(fn)('\(id)');") { [weak self] _, error in
                // ページがまだ読めていない等で失敗したら読み直す
                if error != nil { self?.load(videoId: videoId) }
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "ytHandler",
                  let body = message.body as? [String: Any],
                  let event = body["event"] as? String else { return }
            switch event {
            case "state":
                if let raw = body["state"] as? Int,
                   let state = YouTubePlayerState(rawValue: raw) {
                    parent.onStateChange?(state)
                }
            case "ended":
                parent.onStateChange?(.ended)
            case "error":
                parent.onError?(body["code"] as? Int ?? -1)
            default:
                break
            }
        }
    }

    /// videoId に紛れ込みうる記号を取り除く。
    private static func sanitize(_ s: String) -> String {
        s.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
