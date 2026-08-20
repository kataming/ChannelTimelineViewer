import Foundation

/// 「スキップ」状態をローカル（UserDefaults）に保存するストア。
///
/// 視聴済みとは別の状態で、**見るつもりがない動画**に付ける印。
/// 連続再生（自動再生）のときは飛ばし、「次に見る」の候補からも外す。
/// 視聴済みの進捗には数えない（見ていないため）。
@MainActor
final class SkippedVideoStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "skipped_videos_v1"

    /// videoId -> スキップに設定した日時
    @Published private(set) var entries: [String: Date] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isSkipped(_ videoId: String) -> Bool {
        entries[videoId] != nil
    }

    func markSkipped(_ videoId: String, at date: Date = Date()) {
        entries[videoId] = date
        save()
    }

    func unmarkSkipped(_ videoId: String) {
        entries.removeValue(forKey: videoId)
        save()
    }

    func toggleSkipped(_ videoId: String) {
        if isSkipped(videoId) {
            unmarkSkipped(videoId)
        } else {
            markSkipped(videoId)
        }
    }

    /// まとめて消す（チャンネルの記録を捨てるとき）。
    func removeAll(videoIds: [String]) {
        guard !videoIds.isEmpty else { return }
        var changed = false
        for id in videoIds where entries.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    var skippedCount: Int { entries.count }

    /// 指定した videoId 群のうちスキップ指定の本数。
    func skippedVideoCount(in videoIds: [String]) -> Int {
        videoIds.reduce(0) { $0 + (isSkipped($1) ? 1 : 0) }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else {
            entries = [:]
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
