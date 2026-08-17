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
