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
}

extension Array where Element == VideoItem {
    /// publishedAt で並び替える。ascending=true で古い順。
    func sortedByPublishedDate(ascending: Bool) -> [VideoItem] {
        sorted { lhs, rhs in
            ascending ? lhs.publishedAt < rhs.publishedAt : lhs.publishedAt > rhs.publishedAt
        }
    }

    /// videoId の重複を取り除く（先に現れた方を残す）。
    /// 保存済みの一覧に新着を足すときに使う。
    func uniquedById() -> [VideoItem] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
