import Foundation

/// 1本の動画を表すモデル。
struct VideoItem: Identifiable, Codable, Hashable {
    /// videoId
    let id: String
    let title: String
    let description: String
    let publishedAt: Date
    let thumbnailURL: URL?
    let channelId: String
    /// 視聴回数（YouTube Data API `videos.list` の statistics.viewCount）。
    /// 取れていない・非公開のときは nil。保存済みの古い一覧（1.4.1 より前）にも無い。
    var viewCount: Int? = nil

    /// YouTube で開くための公式URL。
    var watchURL: URL? {
        URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    /// チャンネル内検索：タイトルが検索語を含むか（docs/channel-search.md）。
    /// NFKC＋小文字にそろえて部分一致。検索語が空（空白だけ）なら常に true。
    /// ⚠️ Android `VideoItem.titleMatches` / Web `titleMatches` と同じ規則にしておく。
    func titleMatches(_ query: String) -> Bool {
        let needle = VideoItem.searchKey(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return needle.isEmpty || VideoItem.searchKey(title).contains(needle)
    }

    static func searchKey(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
    }

    /// 「10万回視聴」「100K views」のような短い表記。視聴回数が無ければ nil。
    var viewCountText: String? {
        viewCount.map {
            String(format: String(localized: "video.viewCount.format"),
                   $0.formatted(.number.notation(.compactName)))
        }
    }

    /// 「2018年4月15日 · 10万回視聴」（視聴回数が無ければ日付だけ）。一覧と再生画面で使う。
    func dateAndViews(_ dateStyle: Date.FormatStyle.DateStyle) -> String {
        let date = publishedAt.formatted(date: dateStyle, time: .omitted)
        guard let views = viewCountText else { return date }
        return "\(date) · \(views)"
    }
}

/// 一覧の並び順（右上のメニュー）。
enum VideoSortOrder: String, CaseIterable, Identifiable {
    /// 公開日の古い順（既定）
    case oldest
    /// 公開日の新しい順
    case newest
    /// 視聴回数の多い順。視聴回数が分からない動画は最後（その中は古い順）
    case popular

    var id: String { rawValue }
}

extension Array where Element == VideoItem {
    /// publishedAt で並び替える。ascending=true で古い順。
    func sortedByPublishedDate(ascending: Bool) -> [VideoItem] {
        sorted { lhs, rhs in
            ascending ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt
        }
    }

    /// 並び順を適用する。⚠️ Android `sortedBy(order)` と同じ規則にしておく。
    func sorted(by order: VideoSortOrder) -> [VideoItem] {
        switch order {
        case .oldest:
            return sortedByPublishedDate(ascending: true)
        case .newest:
            return sortedByPublishedDate(ascending: false)
        case .popular:
            return sorted { lhs, rhs in
                switch (lhs.viewCount, rhs.viewCount) {
                case let (l?, r?) where l != r: return l > r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.publishedAt < rhs.publishedAt
                }
            }
        }
    }

    /// 取得した視聴回数を反映する（取れなかった動画は前の値のまま）。
    func applyingViewCounts(_ counts: [String: Int]) -> [VideoItem] {
        map { video in
            guard let count = counts[video.id] else { return video }
            var updated = video
            updated.viewCount = count
            return updated
        }
    }

    /// videoId の重複を取り除く（先に現れた方を残す）。
    /// 保存済みの一覧に新着を足すときに使う。
    func uniquedById() -> [VideoItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
