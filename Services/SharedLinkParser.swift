import Foundation

/// 共有シート（Share Extension）から受け取ったテキスト / URL を解析するユーティリティ。
///
/// - メインアプリと Share Extension の**両方のターゲットに同梱**する（`project.yml` 参照）。
/// - Foundation だけに依存する純粋処理で、ネットワークアクセスも API キーも使わない。
///   Extension 側では「YouTube の URL かどうかの判定」と「カスタム URL の組み立て」だけを行い、
///   API 取得・エラー表示・画面遷移はすべてメインアプリ側で行う。
enum SharedLinkParser {

    /// メインアプリを開くためのカスタム URL スキーム（`Info.plist` の CFBundleURLSchemes と一致させる）。
    static let appURLScheme = "channeltimelineviewer"
    /// カスタム URL のホスト部（`channeltimelineviewer://share?url=...`）。
    static let appURLHost = "share"
    /// 共有された YouTube URL を載せるクエリ名。
    static let appURLQueryName = "url"

    /// YouTube と認識するホスト（完全一致、またはサブドメイン）。
    private static let youTubeHosts = [
        "youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
    ]

    // MARK: - 判定

    /// 文字列が YouTube の URL として解釈できるか。スキーム省略（`youtube.com/@x`）も許容する。
    static func isYouTubeURLString(_ string: String) -> Bool {
        host(of: string) != nil
    }

    // MARK: - 抽出

    /// 共有テキスト（URL 単体・タイトル＋URL の複数行テキストなど）から最初の YouTube URL を取り出す。
    ///
    /// YouTube アプリは共有時に `public.url` ではなく
    /// 「動画タイトル\nhttps://youtu.be/xxxx?si=yyyy」のような**プレーンテキスト**を渡してくることがあるため、
    /// テキストからの抽出に対応する。
    static func extractYouTubeURLString(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) 全体がひとつの URL の場合
        if let normalized = normalizedYouTubeURLString(trimmed) {
            return normalized
        }

        // 2) 空白・改行区切りのトークンから探す
        let separators = CharacterSet.whitespacesAndNewlines
        for rawToken in trimmed.components(separatedBy: separators) {
            for candidate in urlCandidates(in: rawToken) {
                if let normalized = normalizedYouTubeURLString(candidate) {
                    return normalized
                }
            }
        }
        return nil
    }

    /// 1トークンから URL になりうる部分文字列を候補として並べる。
    /// 「これ見て→https://youtu.be/xxx」のように記号が前置きされていても拾えるようにする。
    private static func urlCandidates(in token: String) -> [String] {
        guard !token.isEmpty else { return [] }
        var candidates = [token]
        for marker in ["https://", "http://"] + youTubeHosts {
            if let range = token.range(of: marker, options: .caseInsensitive),
               range.lowerBound != token.startIndex {
                candidates.append(String(token[range.lowerBound...]))
            }
        }
        return candidates
    }

    /// スキームを補い、余分な記号を落とした YouTube URL 文字列。YouTube でなければ nil。
    static func normalizedYouTubeURLString(_ string: String) -> String? {
        let token = trimEdgePunctuation(string.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !token.isEmpty,
              token.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              host(of: token) != nil else { return nil }
        return token.contains("://") ? token : "https://\(token)"
    }

    // MARK: - カスタム URL の組み立て / 取り出し

    /// 共有された YouTube URL を載せた、メインアプリを開くためのカスタム URL を作る。
    static func makeAppURL(for youTubeURLString: String) -> URL? {
        guard let normalized = normalizedYouTubeURLString(youTubeURLString),
              let encoded = normalized.addingPercentEncoding(withAllowedCharacters: valueAllowed) else {
            return nil
        }
        return URL(string: "\(appURLScheme)://\(appURLHost)?\(appURLQueryName)=\(encoded)")
    }

    /// カスタム URL（`channeltimelineviewer://share?url=...`）から YouTube URL を取り出す。
    static func youTubeURLString(fromAppURL url: URL) -> String? {
        guard url.scheme?.lowercased() == appURLScheme else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let value = comps.queryItems?.first(where: { $0.name == appURLQueryName })?.value else {
            return nil
        }
        return normalizedYouTubeURLString(value)
    }

    // MARK: - 内部処理

    /// クエリ値として安全にエンコードするための文字集合（`&` `=` `?` `#` `+` を確実に%エンコードする）。
    private static let valueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=?#+/:")
        return set
    }()

    /// URL 文字列のホストを返す（YouTube でなければ nil）。
    private static func host(of string: String) -> String? {
        let candidate = string.contains("://") ? string : "https://\(string)"
        guard let comps = URLComponents(string: candidate),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased() else {
            return nil
        }
        let matched = youTubeHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        return matched ? host : nil
    }

    /// 前後についてくる引用符・括弧・句読点を取り除く。
    private static func trimEdgePunctuation(_ string: String) -> String {
        let punctuation = CharacterSet(charactersIn: "<>\"'`(){}[]｢｣「」『』（）、。,。;:！？!?…・\u{200B}")
        return string.trimmingCharacters(in: punctuation)
    }
}
