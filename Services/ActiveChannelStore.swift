import Foundation

/// 無料の枠で「いま使うチャンネル」。
///
/// Pro を持っている間は使わない。Pro が外れて保存済みが上限を超えているとき、
/// どれを開けるようにするかをここで覚える（残りはロックされるが、記録は消さない）。
@MainActor
final class ActiveChannelStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "active_channel_v1"

    @Published private(set) var activeChannelId: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        activeChannelId = defaults.string(forKey: storageKey)
    }

    func set(_ channelId: String) {
        guard activeChannelId != channelId else { return }
        activeChannelId = channelId
        defaults.set(channelId, forKey: storageKey)
    }
}
