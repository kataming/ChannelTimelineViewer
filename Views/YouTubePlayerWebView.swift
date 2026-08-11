import SwiftUI
import WebKit

/// 埋め込みページのオリジン。
///
/// YouTube の埋め込みプレイヤーは、読み込み元のオリジン（リファラ）が正しくないと
/// 「この動画は再生できません（エラーコード 152-x / 153-x）」で再生を拒否する。
/// `loadHTMLString(_:baseURL:)` だけではオリジンが伝わらないことがあるため、
/// IFrame API の `origin` パラメータでも明示する。
private let embedOrigin = "https://www.youtube.com"

/// YouTube IFrame Player API のプレイヤー状態。
enum YouTubePlayerState: Int {
    case unstarted = -1
    case ended = 0
    case playing = 1
    case paused = 2
    case buffering = 3
    case cued = 5
}

/// 公式の YouTube IFrame Player API を WKWebView で表示する。
/// 動画ファイルの直接再生・ダウンロードは行わず、公式プレイヤーをそのまま埋め込む。
struct YouTubePlayerWebView: UIViewRepresentable {
    let videoId: String
    /// 初回読み込み後に自動再生するか。false の場合は cue のみ（自動再生しない）。
    var autoplayOnLoad: Bool = false
    var onStateChange: ((YouTubePlayerState) -> Void)? = nil
    /// 埋め込みプレイヤーがエラーを返した時に呼ばれる（IFrame API のエラーコード）。
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
        webView.navigationDelegate = context.coordinator

        context.coordinator.webView = webView
        context.coordinator.loadedVideoId = videoId
        webView.loadHTMLString(Self.html(videoId: videoId),
                               baseURL: URL(string: embedOrigin))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // videoId が変わったときだけ差し替える。
        guard context.coordinator.loadedVideoId != videoId else { return }
        context.coordinator.loadedVideoId = videoId

        if context.coordinator.usesDirectEmbed {
            // フォールバック中は埋め込みURLごと読み直す
            context.coordinator.loadDirectEmbed(videoId: videoId)
            return
        }
        let fn = autoplayOnLoad ? "loadVideo" : "cueVideo"
        webView.evaluateJavaScript("\(fn)('\(Self.escape(videoId))');", completionHandler: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytHandler")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: YouTubePlayerWebView
        weak var webView: WKWebView?
        var loadedVideoId: String?
        /// IFrame API 経由の埋め込みが失敗し、埋め込みURLを直接開く方式に切り替えたか。
        private(set) var usesDirectEmbed = false

        init(_ parent: YouTubePlayerWebView) { self.parent = parent }

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
                let code = body["code"] as? Int ?? -1
                parent.onError?(code)
                // オリジン起因（152/153 系）で再生を拒否されることがあるため、
                // 埋め込みURLを直接開く方式に切り替えて再試行する。
                if !usesDirectEmbed, let id = loadedVideoId {
                    loadDirectEmbed(videoId: id)
                }
            default:
                break
            }
        }

        /// 公式の埋め込みURLをそのまま開く（ページ自体が youtube.com なのでオリジン問題が起きない）。
        /// 再生は変わらず公式プレイヤー。ダウンロードや独自再生は行わない。
        func loadDirectEmbed(videoId: String) {
            usesDirectEmbed = true
            loadedVideoId = videoId
            var comps = URLComponents(string: "\(embedOrigin)/embed/\(videoId)")
            comps?.queryItems = [
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "rel", value: "0"),
                URLQueryItem(name: "modestbranding", value: "1"),
                URLQueryItem(name: "autoplay", value: parent.autoplayOnLoad ? "1" : "0"),
            ]
            guard let url = comps?.url else { return }
            webView?.load(URLRequest(url: url))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // 直接埋め込み方式では IFrame API のコールバックが使えないので、
            // 再生要素の 'ended' を拾って「次の動画」の案内に使う。
            guard usesDirectEmbed else { return }
            webView.evaluateJavaScript(Self.endedHookJS, completionHandler: nil)
        }

        /// 埋め込みページ内の再生要素の終了を検知して Swift 側へ通知するスクリプト。
        /// 再生の制御・改変はしない（終了イベントを購読するだけ）。
        private static let endedHookJS = """
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

    /// videoId に紛れ込みうる引用符等を最低限エスケープする。
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "")
         .replacingOccurrences(of: "'", with: "")
    }

    private static func html(videoId: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="initial-scale=1.0, maximum-scale=1.0, user-scalable=no"/>
        <style>
          * { margin: 0; padding: 0; }
          html, body { background: #000; height: 100%; overflow: hidden; }
          #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          var pendingId = '\(escape(videoId))';
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%', height: '100%',
              videoId: pendingId,
              playerVars: {
                playsinline: 1, rel: 0, modestbranding: 1, fs: 1,
                // オリジンを明示しないと埋め込みが拒否されることがある（エラー 152/153 系）
                origin: '\(embedOrigin)',
                enablejsapi: 1
              },
              events: {
                'onReady': onReady,
                'onStateChange': onStateChange,
                'onError': onError
              }
            });
          }
          var ready = false;
          function onReady() { ready = true; }
          function onStateChange(e) { ready = true; post({ event: 'state', state: e.data }); }
          function onError(e) { post({ event: 'error', code: e.data }); }

          // IFrame API が読み込めない / 埋め込みページ内で拒否された場合、onError すら
          // 呼ばれないことがある。一定時間 ready にならなければ失敗とみなして通知する
          // （Swift 側が埋め込みURL直接読み込みに切り替える）。
          setTimeout(function () {
            if (!ready) { post({ event: 'error', code: -2 }); }
          }, 8000);
          function post(msg) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ytHandler) {
              window.webkit.messageHandlers.ytHandler.postMessage(msg);
            }
          }
          function loadVideo(id) { if (player && player.loadVideoById) { player.loadVideoById(id); } }
          function cueVideo(id) { if (player && player.cueVideoById) { player.cueVideoById(id); } }
          function playVideo() { if (player && player.playVideo) { player.playVideo(); } }
          function pauseVideo() { if (player && player.pauseVideo) { player.pauseVideo(); } }
        </script>
        </body>
        </html>
        """
    }
}
