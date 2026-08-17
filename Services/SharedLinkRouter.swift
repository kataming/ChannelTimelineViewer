import Foundation

/// 共有シート（Share Extension）から渡されたリンクを、メインアプリ内で受け渡すためのストア。
///
/// Share Extension は `channeltimelineviewer://share?url=...` でメインアプリを開くだけで、
/// API 取得・エラー処理・画面遷移はすべてメインアプリ（この経路の先）で行う。
@MainActor
final class SharedLinkRouter: ObservableObject {
    /// 通知タップ（`UNUserNotificationCenterDelegate`）からも渡せるよう、共有インスタンスを持つ。
    static let shared = SharedLinkRouter()

    /// 未処理の共有リンク（YouTube の URL 文字列）。
    @Published private(set) var pendingLink: String?
    /// 直近に共有リンクを受け取った回数。同じ URL を続けて共有した場合も検知できるようにする。
    @Published private(set) var receivedCount: Int = 0

    /// 共有シートからの受け渡しを一度でも使ったか（案内を出すかの判断に使う）。
    @Published private(set) var hasUsedShareHandoff: Bool
    /// 共有を速くする案内を閉じたか。
    @Published private(set) var hasDismissedShareTips: Bool

    private static let usedHandoffKey = "has_used_share_handoff_v1"
    private static let dismissedTipsKey = "share_tips_dismissed_v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasUsedShareHandoff = defaults.bool(forKey: Self.usedHandoffKey)
        self.hasDismissedShareTips = defaults.bool(forKey: Self.dismissedTipsKey)
    }

    /// 案内を閉じる（次からは表示しない）。
    func dismissShareTips() {
        hasDismissedShareTips = true
        defaults.set(true, forKey: Self.dismissedTipsKey)
    }

    /// カスタム URL を受け取る（`onOpenURL` から呼ぶ）。処理できた場合のみ true。
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = SharedLinkParser.youTubeURLString(fromAppURL: url) else {
            return false
        }
        accept(link)
        return true
    }

    /// 通知タップ・クリップボードなど、URL 文字列で受け取る経路。
    @discardableResult
    func handleLink(_ rawLink: String) -> Bool {
        guard let link = SharedLinkParser.normalizedYouTubeURLString(rawLink) else { return false }
        accept(link)
        return true
    }

    private func accept(_ link: String) {
        pendingLink = link
        receivedCount += 1
        markShareHandoffUsed()
    }

    /// 共有経由で開いたことを記録する（クリップボードから開いた場合など）。
    func markShareHandoffUsed() {
        guard !hasUsedShareHandoff else { return }
        hasUsedShareHandoff = true
        defaults.set(true, forKey: Self.usedHandoffKey)
    }

    /// 保留中のリンクを取り出して消費する（二重処理を防ぐ）。
    func consume() -> String? {
        defer { pendingLink = nil }
        return pendingLink
    }
}
