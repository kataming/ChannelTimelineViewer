import Foundation

/// 視聴済み状態をローカル（UserDefaults）に保存するストア。
@MainActor
final class WatchHistoryStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "watch_history_v1"

    /// videoId -> 視聴日時
    @Published private(set) var entries: [String: Date] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func isWatched(_ videoId: String) -> Bool {
        entries[videoId] != nil
    }

    func markWatched(_ videoId: String, at date: Date = Date()) {
        entries[videoId] = date
        save()
    }

    func unmarkWatched(_ videoId: String) {
        entries.removeValue(forKey: videoId)
        save()
    }

    func toggleWatched(_ videoId: String) {
        if isWatched(videoId) {
            unmarkWatched(videoId)
        } else {
            markWatched(videoId)
        }
    }

    /// まとめて消す（チャンネルの記録を捨てるとき）。保存は一度だけ行う。
    func removeAll(videoIds: [String]) {
        guard !videoIds.isEmpty else { return }
        var changed = false
        for id in videoIds where entries.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    var watchedCount: Int { entries.count }

    /// 指定した videoId 群のうち視聴済みの本数（チャンネル進捗の計算に使う）。
    func watchedVideoCount(in videoIds: [String]) -> Int {
        videoIds.reduce(0) { $0 + (isWatched($1) ? 1 : 0) }
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
