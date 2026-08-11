import SwiftUI
import WebKit

/// 埋め込みページのオリジン。
private let embedOrigin = "https://www.youtube.com"

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
/// ## なぜ公式の埋め込みURLを直接開くのか
///
/// 以前は自前の HTML を `loadHTMLString(_:baseURL:)` で読み込み、その中で IFrame Player API
/// (`YT.Player`) を使っていた。しかしこの方法では WKWebView が持つページのオリジンが
/// YouTube 側に正しく伝わらず、
///   「この動画は再生できません（エラーコード 152-4）」
///   「Error 153 - Video player configuration error」
/// で再生を拒否された（動画側は embeddable=true で制限なしであることを Data API で確認済み）。
/// `origin` パラメータを足しても、宣言したオリジンと実際のオリジンが食い違うだけで解決しない。
///
/// そこで `https://www.youtube.com/embed/<videoId>` を **そのまま開く**方式にした。
/// ページ自体が youtube.com なのでオリジンの問題が原理的に発生しない。
/// 表示されるのは変わらず公式プレイヤーで、ダウンロード・独自再生・広告回避は一切行わない。
///
/// 再生終了の検知だけは IFrame API のコールバックが使えないため、埋め込みページ内の
/// 再生要素の `ended` イベントを購読して代替する（再生の制御・改変はしない）。
struct YouTubePlayerWebView: UIViewRepresentable {
    let videoId: String
    /// 初回読み込み後に自動再生するか。
    var autoplayOnLoad: Bool = false
    var onStateChange: ((YouTubePlayerState) -> Void)? = nil

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
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.load(videoId: videoId)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // videoId が変わったときだけ読み直す。
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.load(videoId: videoId)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytHandler")
    }

    /// 埋め込みURLを組み立てる。
    static func embedURL(videoId: String, autoplay: Bool) -> URL? {
        var comps = URLComponents(string: "\(embedOrigin)/embed/\(escape(videoId))")
        comps?.queryItems = [
            URLQueryItem(name: "playsinline", value: "1"),   // 全画面に飛ばさず埋め込みのまま再生
            URLQueryItem(name: "rel", value: "0"),           // 関連動画を同チャンネルに限定
            URLQueryItem(name: "modestbranding", value: "1"),
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
        ]
        return comps?.url
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: YouTubePlayerWebView
        weak var webView: WKWebView?
        private(set) var loadedVideoId: String?

        init(_ parent: YouTubePlayerWebView) { self.parent = parent }

        func load(videoId: String) {
            loadedVideoId = videoId
            guard let url = YouTubePlayerWebView.embedURL(
                videoId: videoId, autoplay: parent.autoplayOnLoad
            ) else { return }
            webView?.load(URLRequest(url: url))
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
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(Self.stateHookJS, completionHandler: nil)
        }

        /// 埋め込みページ内の再生要素の状態を Swift 側へ通知するスクリプト。
        /// 再生の制御・改変はせず、イベントを購読するだけ。
        private static let stateHookJS = """
        (function () {
          function post(msg) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ytHandler) {
              window.webkit.messageHandlers.ytHandler.postMessage(msg);
            }
          }
          function hook() {
            var v = document.querySelector('video');
            if (v && !v.__ctvHooked) {
              v.__ctvHooked = true;
              v.addEventListener('ended', function () { post({ event: 'ended' }); });
              v.addEventListener('playing', function () { post({ event: 'state', state: 1 }); });
              v.addEventListener('pause', function () { post({ event: 'state', state: 2 }); });
            }
          }
          hook();
          setInterval(hook, 1500);
        })();
        """
    }

    /// videoId に紛れ込みうる記号を最低限取り除く。
    private static func escape(_ s: String) -> String {
        s.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
