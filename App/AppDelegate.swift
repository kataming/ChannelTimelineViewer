import UIKit
import UserNotifications

/// 通知タップを受け取るためだけの AppDelegate。
///
/// 共有シート拡張はローカル通知を出し、その通知をタップするとここに届く。
/// 受け取った URL は `SharedLinkRouter` に渡し、通常の共有経路と同じ流れで
/// チャンネルの動画一覧を開く。リモート通知（プッシュ）は使用しない。
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // 起動直後に設定しないと、通知タップで起動した場合の受け取りに間に合わない。
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// 通知をタップしたとき。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let link = SharedLinkNotifier.link(from: userInfo) {
            Task { @MainActor in
                SharedLinkRouter.shared.handleLink(link)
            }
        }
        completionHandler()
    }

    /// アプリを開いている最中に届いた場合もバナーを出す（共有直後に戻ってきた場合など）。
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
