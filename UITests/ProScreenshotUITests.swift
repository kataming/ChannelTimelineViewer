import XCTest

/// App 内課金の**審査用スクリーンショット**を撮るための UI テスト。
///
/// Apple は「その課金がアプリのどこで提供されるか」が分かる画像を1枚求める。
/// ここでは購入画面（`Views/ProView.swift`）を開いて撮るだけなので、
/// YouTube API もネットワークも使わない（ホーム → Pro の入口 → 購入画面）。
///
/// 価格は StoreKit のテスト設定（`StoreKit/ProStoreKit.storekit`）から出る。
/// 設定が効いていない場合は「価格を確認しています…」の表示になるが、撮影は続ける
/// （購入画面が写っていれば審査の用は足りるため）。
///
/// 実行は `.github/workflows/appstore-iap-screenshot.yml` から。
final class ProScreenshotUITests: XCTestCase {

    private var app: XCUIApplication!

    /// 審査担当者に見せるので英語で撮る。
    private let language = "en"

    private lazy var strings: Bundle = {
        let testBundle = Bundle(for: type(of: self))
        if let path = testBundle.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return testBundle
    }()

    private func L(_ key: String) -> String {
        strings.localizedString(forKey: key, value: key, table: nil)
    }

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testCaptureProScreen() throws {
        // ホームの Pro の入口を押して購入画面へ（表示文字ではなく識別子で探す）。
        let entry = app.buttons["proEntry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 60), "Pro の入口が見つからない")
        entry.tap()

        // 購入画面が出たか（見出しで判定する）。
        let headline = app.staticTexts[L("pro.headline")]
        XCTAssertTrue(headline.waitForExistence(timeout: 30), "購入画面が開かない")

        // 価格の取得（StoreKit テスト設定）を少し待ってから撮る。
        Thread.sleep(forTimeInterval: 3.0)
        capture("iap-review-pro")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
