import Foundation

/// 入力URLから解決したチャンネル識別子。
enum ChannelIdentifier: Equatable {
    case channelId(String)   // UCxxxx
    case handle(String)      // @ を除いたハンドル
    case username(String)    // 旧 /user/ 形式
    case customName(String)  // /c/name または /name のカスタムURL
    case video(String)       // 動画URL（videoId）。channelId は API で解決する
}

/// YouTube チャンネルURL（または handle / channelId）を解析する。
/// ネットワークアクセスを行わない純粋関数なのでテストしやすい。
enum ChannelResolver {

    static func parse(_ rawInput: String) throws -> ChannelIdentifier {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw YouTubeAPIError.invalidChannelURL }

        // 1) 先頭が @ のハンドル単体
        if input.hasPrefix("@") {
            return try makeHandle(String(input.dropFirst()))
        }

        // 2) channelId 単体（UC + 22文字）
        if isChannelId(input) {
            return .channelId(input)
        }

        // 3) URLとして解析（スキーム省略も許容）
        let normalized = input.contains("://") ? input : "https://\(input)"
        guard let comps = URLComponents(string: normalized),
              let host = comps.host?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            throw YouTubeAPIError.invalidChannelURL
        }

        let segments = comps.path.split(separator: "/").map(String.init)

        // 短縮URL（youtu.be/VIDEOID）は常に動画。
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            guard let id = segments.first, isVideoId(id) else {
                throw YouTubeAPIError.invalidVideoURL
            }
            return .video(id)
        }

        guard let first = segments.first else {
            throw YouTubeAPIError.invalidChannelURL
        }

        switch first.lowercased() {
        case "watch":
            // watch?v=VIDEOID（クエリで動画IDを渡す形式）
            guard let v = comps.queryItems?.first(where: { $0.name == "v" })?.value,
                  isVideoId(v) else {
                throw YouTubeAPIError.invalidVideoURL
            }
            return .video(v)
        case "shorts", "live", "embed", "v":
            guard segments.count >= 2, isVideoId(segments[1]) else {
                throw YouTubeAPIError.invalidVideoURL
            }
            return .video(segments[1])
        case "channel":
            guard segments.count >= 2, isChannelId(segments[1]) else {
                throw YouTubeAPIError.invalidChannelURL
            }
            return .channelId(segments[1])
        case "user":
            guard segments.count >= 2 else { throw YouTubeAPIError.invalidChannelURL }
            return .username(segments[1])
        case "c":
            guard segments.count >= 2 else { throw YouTubeAPIError.invalidChannelURL }
            return .customName(segments[1])
        default:
            if first.hasPrefix("@") {
                return try makeHandle(String(first.dropFirst()))
            }
            // youtube.com/SomeName のような旧カスタムURL
            return .customName(first)
        }
    }

    /// UC で始まる24文字の channelId かどうか。
    static func isChannelId(_ s: String) -> Bool {
        guard s.hasPrefix("UC"), s.count == 24 else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
    }

    /// YouTube の videoId（11文字の英数字 + `_` `-`）かどうか。
    static func isVideoId(_ s: String) -> Bool {
        guard s.count == 11 else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }

    /// 動画URL（または videoId 単体）から videoId を取り出す。動画URLでなければ nil。
    /// 共有された URL の種類を判別したい場面（テスト・ログ）のための補助 API。
    static func extractVideoId(from rawInput: String) -> String? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if isVideoId(input), !input.contains("/"), !input.contains(".") {
            return input
        }
        guard let identifier = try? parse(input), case .video(let id) = identifier else {
            return nil
        }
        return id
    }

    private static func makeHandle(_ h: String) throws -> ChannelIdentifier {
        let clean = h.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { throw YouTubeAPIError.invalidChannelURL }
        return .handle(clean)
    }
}
