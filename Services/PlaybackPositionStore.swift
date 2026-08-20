import Foundation

/// 動画ごとの再生位置（続きから再生用）をローカル保存するストア。
///
/// 位置の取得元は**公式 IFrame Player が通知する再生時間だけ**で、
/// 動画データの取得・保存は一切行わない。保存先は端末内の UserDefaults。
@MainActor
final class PlaybackPositionStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "playback_positions_v1"

    /// videoId -> 再生位置
    ///
    /// ⚠️ あえて `@Published` にしていない。再生中は5秒ごとに位置が更新されるため、
    /// 変更を通知すると動画一覧（数千本を並び替え・絞り込みする画面）が
    /// そのたびに再描画されてしまう。この値を直接表示する画面は無く、
    /// 再開位置は再生画面の ViewModel が保持するので通知は不要。
    private(set) var positions: [String: PlaybackPosition] = [:]

    /// これ未満の位置は「実質最初から」とみなして保存しない（秒）。
    static let minimumResumeSeconds: Double = 10
    /// 終端からこの秒数以内まで見ていたら「見終わった」とみなして保存しない（秒）。
    static let finishedThresholdSeconds: Double = 15

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    /// 保存されている再開位置（秒）。無ければ nil。
    func position(for videoId: String) -> Double? {
        guard let saved = positions[videoId], saved.seconds >= Self.minimumResumeSeconds else {
            return nil
        }
        return saved.seconds
    }

    func hasPosition(for videoId: String) -> Bool {
        position(for: videoId) != nil
    }

    /// 再生位置を記録する。
    /// 冒頭すぎる場合・ほぼ見終わっている場合は「続きから」の意味がないので削除する。
    func record(videoId: String, seconds: Double, duration: Double, at date: Date = Date()) {
        guard !videoId.isEmpty, seconds.isFinite, seconds >= 0 else { return }

        let nearEnd = duration > 0 && seconds >= duration - Self.finishedThresholdSeconds
        guard seconds >= Self.minimumResumeSeconds, !nearEnd else {
            clear(videoId: videoId)
            return
        }

        positions[videoId] = PlaybackPosition(
            videoId: videoId,
            seconds: seconds,
            duration: max(0, duration),
            updatedAt: date
        )
        save()
    }

    /// 記録を消す（最初から見直した・見終わった場合）。
    func clear(videoId: String) {
        guard positions.removeValue(forKey: videoId) != nil else { return }
        save()
    }

    /// まとめて消す（チャンネルの記録を捨てるとき）。
    func removeAll(videoIds: [String]) {
        guard !videoIds.isEmpty else { return }
        var changed = false
        for id in videoIds where positions.removeValue(forKey: id) != nil { changed = true }
        if changed { save() }
    }

    func clearAll() {
        positions = [:]
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: PlaybackPosition].self, from: data) else {
            positions = [:]
            return
        }
        positions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(positions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
