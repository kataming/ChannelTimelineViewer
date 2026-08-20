import Foundation

/// 動画ごとのメモをローカル保存するストア。
@MainActor
final class VideoMemoStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "video_memos_v1"

    @Published private(set) var memos: [String: VideoMemo] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// 指定動画のメモ本文（無ければ空文字）。
    func memo(for videoId: String) -> String {
        memos[videoId]?.memo ?? ""
    }

    func hasMemo(for videoId: String) -> Bool {
        !(memos[videoId]?.memo.isEmpty ?? true)
    }

    /// メモを保存する。空文字なら削除する。
    func setMemo(_ text: String, for videoId: String, at date: Date = Date()) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            memos.removeValue(forKey: videoId)
        } else {
            memos[videoId] = VideoMemo(videoId: videoId, memo: trimmed, updatedAt: date)
        }
        save()
    }

    /// まとめて消す（チャンネルの記録を捨てるとき）。
    func removeAll(videoIds: [String]) {
        guard !videoIds.isEmpty else { return }
        var changed = false
        for id in videoIds where memos.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: VideoMemo].self, from: data) else {
            memos = [:]
            return
        }
        memos = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(memos) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
