import Foundation

/// 共有シート（Share Extension）から渡されたリンクを、メインアプリ内で受け渡すためのストア。
///
/// Share Extension は `channeltimelineviewer://share?url=...` でメインアプリを開くだけで、
/// API 取得・エラー処理・画面遷移はすべてメインアプリ（この経路の先）で行う。
@MainActor
final class SharedLinkRouter: ObservableObject {
    /// 未処理の共有リンク（YouTube の URL 文字列）。
    @Published private(set) var pendingLink: String?
    /// 直近に共有リンクを受け取った回数。同じ URL を続けて共有した場合も検知できるようにする。
    @Published private(set) var receivedCount: Int = 0

    /// カスタム URL を受け取る（`onOpenURL` から呼ぶ）。処理できた場合のみ true。
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let link = SharedLinkParser.youTubeURLString(fromAppURL: url) else {
            return false
        }
        pendingLink = link
        receivedCount += 1
        return true
    }

    /// 保留中のリンクを取り出して消費する（二重処理を防ぐ）。
    func consume() -> String? {
        defer { pendingLink = nil }
        return pendingLink
    }
}
