import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 再生中だけ画面の自動ロック（自動消灯）を止めるための小さな制御。
///
/// 置いたまま見ているときに画面が消えて再生が止まってしまうのを防ぐためのもの。
/// **バックグラウンド再生ではない**（アプリを離れれば再生は止まる）。
/// 一時停止・停止中や再生画面を離れたときは、通常どおり自動ロックする。
@MainActor
final class ScreenSleepController {
    static let shared = ScreenSleepController()

    private(set) var isKeepingScreenOn = false

    /// この再生状態のときだけ画面を点けたままにする。
    /// 一時停止・終了では通常どおり消えるようにして、電池を無駄にしない。
    static func shouldKeepScreenOn(for state: YouTubePlayerState) -> Bool {
        state == .playing || state == .buffering
    }

    func setKeepScreenOn(_ on: Bool) {
        guard on != isKeepingScreenOn else { return }
        isKeepingScreenOn = on
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }
}
