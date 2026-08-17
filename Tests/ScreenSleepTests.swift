import XCTest
@testable import ChannelTimelineViewer

/// 「再生中だけ画面を自動ロックさせない」判定のテスト。
/// （バックグラウンド再生ではなく、前面で再生している間だけ画面を点けたままにする）
@MainActor
final class ScreenSleepTests: XCTestCase {

    func testKeepsScreenOnWhilePlaying() {
        XCTAssertTrue(ScreenSleepController.shouldKeepScreenOn(for: .playing))
        XCTAssertTrue(ScreenSleepController.shouldKeepScreenOn(for: .buffering),
                      "読み込み中もすぐ再生に入るので点けたままにする")
    }

    func testLetsScreenSleepWhenNotPlaying() {
        XCTAssertFalse(ScreenSleepController.shouldKeepScreenOn(for: .paused),
                       "一時停止中は通常どおり画面が消える（電池を無駄にしない）")
        XCTAssertFalse(ScreenSleepController.shouldKeepScreenOn(for: .ended))
        XCTAssertFalse(ScreenSleepController.shouldKeepScreenOn(for: .unstarted))
        XCTAssertFalse(ScreenSleepController.shouldKeepScreenOn(for: .cued))
    }

    func testTracksItsOwnState() {
        let controller = ScreenSleepController.shared
        controller.setKeepScreenOn(false)
        XCTAssertFalse(controller.isKeepingScreenOn)

        controller.setKeepScreenOn(true)
        XCTAssertTrue(controller.isKeepingScreenOn)

        // 後片付け（他のテストに影響させない）
        controller.setKeepScreenOn(false)
        XCTAssertFalse(controller.isKeepingScreenOn)
    }
}
