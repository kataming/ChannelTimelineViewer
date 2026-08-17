import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// 「共有シートからワンタップで開く」ために使う通知の許可状態。
///
/// 通知は**共有した直後の受け渡しにだけ**使う。定期通知・宣伝通知は出さない。
/// 許可しない場合もクリップボード経由で受け取れるので、機能が失われることはない。
@MainActor
final class NotificationPermission: ObservableObject {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    /// 許可を尋ねる価値がある状態か（まだ聞いていない）。
    var canAsk: Bool { status == .notDetermined }
    /// 通知でワンタップ起動できる状態か。
    var isEnabled: Bool { status == .authorized || status == .provisional }
    /// 拒否済み（設定アプリへ案内する）。
    var isDenied: Bool { status == .denied }

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func refresh() async {
        status = await center.notificationSettings().authorizationStatus
    }

    /// 許可を求める（音・バッジは使わないので通知表示のみ）。
    func request() async {
        _ = try? await center.requestAuthorization(options: [.alert])
        await refresh()
    }

    /// 設定アプリのこのアプリのページを開く。
    func openSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
