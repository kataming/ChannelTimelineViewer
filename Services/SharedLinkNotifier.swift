import Foundation
import UserNotifications

/// 共有シートで受け取った URL を「タップ1回でアプリを開く」ために使うローカル通知。
///
/// iOS の仕様で、共有シート拡張から含有アプリを直接起動することはできない
/// （`NSExtensionContext.open` が使えるのは Today / iMessage 拡張のみ）。
/// そこで **Apple が想定している手段であるローカル通知**を使い、通知のタップで
/// アプリを開いて該当チャンネルを表示する。
///
/// - 通知はユーザーが共有した直後にだけ出す（定期通知・宣伝通知は一切出さない）。
/// - 通知を許可していない場合は何も出さず、クリップボード経由の受け渡しにフォールバックする。
/// - 送信するのはローカル通知のみで、サーバーへの送信（プッシュ通知）は行わない。
enum SharedLinkNotifier {
    /// 共有ごとに置き換える（通知が積み上がらないようにする）。
    static let requestIdentifier = "shared-youtube-link"
    static let categoryIdentifier = "SHARED_YOUTUBE_LINK"
    static let linkUserInfoKey = "sharedYouTubeURL"

    /// 通知の中身を組み立てる。YouTube の URL でなければ nil。
    static func makeRequest(for rawLink: String) -> UNNotificationRequest? {
        guard let link = SharedLinkParser.normalizedYouTubeURLString(rawLink) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "Channel Timeline Viewer"
        content.body = String(localized: "notification.sharedLink.body")
        content.userInfo = [linkUserInfoKey: link]
        content.categoryIdentifier = categoryIdentifier
        content.sound = nil          // 音は鳴らさない（受け渡しの案内なので静かに出す）
        content.interruptionLevel = .active

        // trigger = nil で即時配信。
        return UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
    }

    /// 通知の userInfo から共有された YouTube URL を取り出す。
    /// 想定外の値が入っていても YouTube 以外は受け付けない。
    static func link(from userInfo: [AnyHashable: Any]) -> String? {
        guard let raw = userInfo[linkUserInfoKey] as? String else { return nil }
        return SharedLinkParser.normalizedYouTubeURLString(raw)
    }
}
