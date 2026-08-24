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
    /// 再生開始位置（秒）。「続きから再生」で使う。0 なら最初から。
    var startSeconds: Double = 0
    /// プレイヤーへの操作要求（頭出し・再生速度・字幕）。id が変わったときだけ実行する。
    var command: PlayerCommand? = nil
    var onStateChange: ((YouTubePlayerState) -> Void)? = nil
    /// 再生位置の通知（videoId, 現在位置秒, 動画の長さ秒）。
    var onTimeUpdate: ((String, Double, Double) -> Void)? = nil
    /// 動画が終わる直前の通知（videoId）。拡大表示（全画面）のまま次へ進むために使う。
    /// 詳しくは PlayerViewModel.handleNearEnd(videoId:) を参照。
    var onNearEnd: ((String) -> Void)? = nil
    /// 選べる再生速度・字幕トラックなどの通知（アプリ側の設定画面で使う）。
    var onOptions: ((PlayerOptions) -> Void)? = nil
    /// 再生できなかった場合に呼ばれる（IFrame API のエラーコード）。
    var onError: ((Int) -> Void)? = nil

    /// プレイヤーへの操作要求。同じ操作を繰り返せるよう毎回新しい id を持つ。
    struct PlayerCommand: Equatable {
        enum Kind: Equatable {
            case seek(Double)
            case playbackRate(Double)
            /// nil で字幕オフ。
            case captionTrack(String?)
            /// 選べる速度・字幕トラックを取り直す（設定画面を開いたとき用）。
            case refreshOptions
            /// 先頭に戻して再生し直す（1本リピート用）。
            case replay
        }
        let id: UUID
        let kind: Kind

        init(_ kind: Kind) {
            self.id = UUID()
            self.kind = kind
        }

        /// 頭出し（0秒へ）。
        static func seek(seconds: Double) -> PlayerCommand { PlayerCommand(.seek(seconds)) }

        /// 中継ページで実行する JavaScript。値は数値・英数字のみに正規化して埋め込む。
        var javaScript: String {
            switch kind {
            case .seek(let seconds):
                return "seekTo(\(Int(max(0, seconds.isFinite ? seconds : 0))));"
            case .playbackRate(let rate):
                let safe = min(max(rate.isFinite ? rate : 1, 0.25), 4)
                return String(format: "setRate(%.2f);", safe)
            case .captionTrack(let code):
                guard let code, !code.isEmpty else { return "setCaptionTrack('');" }
                let safe = code.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
                return "setCaptionTrack('\(safe)');"
            case .refreshOptions:
                return "postOptions();"
            case .replay:
                return "replayVideo();"
            }
        }
    }

    /// プレイヤーから受け取った、アプリ側の設定画面に出す情報。
    struct PlayerOptions: Equatable {
        struct CaptionTrack: Equatable, Identifiable {
            let code: String
            let name: String
            var id: String { code }
        }
        var rates: [Double] = []
        var rate: Double = 1
        var captions: [CaptionTrack] = []
        var activeCaption: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ytHandler")

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // 公式プレイヤーの全画面ボタンを機能させる（既定では WKWebView 内の全画面は無効）。
        // 設定メニューや字幕の表示領域を確保するのにも効く。
        config.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black

        context.coordinator.webView = webView
        context.coordinator.load(videoId: videoId, start: startSeconds)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // 最新のクロージャ・設定値を Coordinator に反映する。
        context.coordinator.parent = self

        // videoId が変わったときだけ差し替える。ページ再読み込みは不要。
        if context.coordinator.loadedVideoId != videoId {
            context.coordinator.change(videoId: videoId, autoplay: autoplayOnLoad, start: startSeconds)
            return
        }
        // 「最初から再生」「再生速度」「字幕」などの操作要求。
        if let command, context.coordinator.handledCommandId != command.id {
            context.coordinator.run(command)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ytHandler")
    }

    /// 中継ページの URL を組み立てる。
    static func pageURL(videoId: String, autoplay: Bool, start: Double = 0) -> URL? {
        var comps = URLComponents(string: playerPageURL)
        var items = [
            URLQueryItem(name: "v", value: sanitize(videoId)),
            URLQueryItem(name: "autoplay", value: autoplay ? "1" : "0"),
        ]
        if let seconds = startQueryValue(start) {
            items.append(URLQueryItem(name: "start", value: seconds))
        }
        comps?.queryItems = items
        return comps?.url
    }

    /// 開始位置を秒（整数）の文字列にする。0 以下・不正値は付けない。
    static func startQueryValue(_ start: Double) -> String? {
        guard start.isFinite, start >= 1 else { return nil }
        return String(Int(start))
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var parent: YouTubePlayerWebView
        weak var webView: WKWebView?
        private(set) var loadedVideoId: String?
        private(set) var handledCommandId: UUID?

        init(_ parent: YouTubePlayerWebView) { self.parent = parent }

        func load(videoId: String, start: Double = 0) {
            loadedVideoId = videoId
            guard let url = YouTubePlayerWebView.pageURL(
                videoId: videoId, autoplay: parent.autoplayOnLoad, start: start
            ) else { return }
            webView?.load(URLRequest(url: url))
        }

        /// ページを読み直さずに動画だけ差し替える。
        func change(videoId: String, autoplay: Bool, start: Double = 0) {
            loadedVideoId = videoId
            let id = YouTubePlayerWebView.sanitize(videoId)
            let fn = autoplay ? "loadVideo" : "cueVideo"
            let seconds = max(0, start.isFinite ? start : 0)
            webView?.evaluateJavaScript("\(fn)('\(id)', \(Int(seconds)));") { [weak self] _, error in
                // ページがまだ読めていない等で失敗したら読み直す
                if error != nil { self?.load(videoId: videoId, start: seconds) }
            }
        }

        /// プレイヤーを操作する（頭出し・再生速度・字幕）。
        func run(_ command: PlayerCommand) {
            handledCommandId = command.id
            webView?.evaluateJavaScript(command.javaScript, completionHandler: nil)
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
            case "time":
                // どの動画の位置かを取り違えないよう、videoId 付きで受け取る。
                if let id = body["v"] as? String,
                   let seconds = (body["t"] as? Double) ?? (body["t"] as? NSNumber)?.doubleValue {
                    let duration = (body["d"] as? Double) ?? (body["d"] as? NSNumber)?.doubleValue ?? 0
                    parent.onTimeUpdate?(id, seconds, duration)
                }
            case "nearEnd":
                if let id = body["v"] as? String, !id.isEmpty {
                    parent.onNearEnd?(id)
                }
            case "options":
                parent.onOptions?(YouTubePlayerWebView.parseOptions(body))
            case "error":
                parent.onError?(body["code"] as? Int ?? -1)
            default:
                break
            }
        }
    }

    /// 中継ページから届いた options メッセージを解釈する（ネットワーク非依存＝テスト可能）。
    static func parseOptions(_ body: [String: Any]) -> PlayerOptions {
        var options = PlayerOptions()
        if let rates = body["rates"] as? [Any] {
            options.rates = rates.compactMap { ($0 as? NSNumber)?.doubleValue ?? $0 as? Double }
                .filter { $0.isFinite && $0 > 0 }
        }
        if let rate = (body["rate"] as? NSNumber)?.doubleValue ?? body["rate"] as? Double,
           rate.isFinite, rate > 0 {
            options.rate = rate
        }
        if let captions = body["captions"] as? [[String: Any]] {
            options.captions = captions.compactMap { item in
                guard let code = item["code"] as? String, !code.isEmpty else { return nil }
                let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? code
                return PlayerOptions.CaptionTrack(code: code, name: name)
            }
        }
        if let active = body["activeCaption"] as? String, !active.isEmpty {
            options.activeCaption = active
        }
        return options
    }

    /// videoId に紛れ込みうる記号を取り除く。
    private static func sanitize(_ s: String) -> String {
        s.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}
