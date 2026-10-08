import XCTest

/// 無料版の広告（AdMob・デバッグなのでテスト広告）の見え方を撮る UI テスト。
/// 実行は `.github/workflows/ios-screenshots.yml`（Screenshots スキームが UITests をすべて走らせる）から。
///
/// 撮る場面（docs/admob-ads.md）:
///   1. 無料・保存チャンネル1件 … 最初の画面の MREC、動画一覧のアンカー型バナー
///   2. Pro から無料に戻った・保存チャンネル3件（2件はロック） … MREC が下にずれる場面
/// Pro（広告が出ないこと）は StoreKit のテスト設定が要るので
/// `ProScreenshotUITests.testZ_Proでは広告が出ない`（appstore-iap-screenshot.yml）で確かめる。
final class AdsPreviewUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-channelTutorialCompleted", "YES"]
    }

    func test1_無料_保存1件() throws {
        app.launchArguments += AdsTestSupport.seedArguments(
            channels: [AdsTestSupport.nasa], active: AdsTestSupport.nasa.id, proCached: false)
        app.launch()
        captureHomeAndList(prefix: "01-free-1ch")
    }

    func test2_Proから無料_保存3件() throws {
        // 端末内の Pro の写しは「持っている」のまま、StoreKit には購入が無い＝起動後に無料へ落ちる。
        app.launchArguments += AdsTestSupport.seedArguments(
            channels: [AdsTestSupport.nasa, AdsTestSupport.spacex, AdsTestSupport.veritasium],
            active: AdsTestSupport.nasa.id, proCached: true)
        app.launch()
        captureHomeAndList(prefix: "02-pro-to-free-3ch")
    }

    private func captureHomeAndList(prefix: String) {
        let title = app.staticTexts["NASA"]
        XCTAssertTrue(title.waitForExistence(timeout: 60), "保存チャンネルが表示されない")

        // 広告の読み込み（同意の確認 → 初期化 → 読み込み）を待つ。画面外でも要素は見つかる。
        XCTAssertTrue(AdsTestSupport.mrec(in: app).waitForExistence(timeout: 60), "MREC が出ない")
        AdsTestSupport.capture("\(prefix)-a-home-top", in: self)
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        AdsTestSupport.capture("\(prefix)-b-home-scrolled", in: self)
        app.swipeDown()

        title.tap()
        XCTAssertTrue(AdsTestSupport.anchor(in: app).waitForExistence(timeout: 60), "アンカー型バナーが出ない")
        Thread.sleep(forTimeInterval: 5)
        AdsTestSupport.capture("\(prefix)-c-videolist", in: self)
    }

    /// 再生画面の本文の中のバナー（移動ボタンと「YouTubeでコメントする」の間・2026-10-09〜）。
    /// 1画面目に広告と「YouTubeでコメントする」まで収まるかを見る。
    func test3_無料_再生画面() throws {
        app.launchArguments += AdsTestSupport.seedArguments(
            channels: [AdsTestSupport.nasa], active: AdsTestSupport.nasa.id, proCached: false)
        app.launch()
        let title = app.staticTexts["NASA"]
        XCTAssertTrue(title.waitForExistence(timeout: 60), "保存チャンネルが表示されない")
        title.tap()
        XCTAssertTrue(AdsTestSupport.anchor(in: app).waitForExistence(timeout: 60), "アンカー型バナーが出ない")
        // 「次に見る」の行（一覧の上のほう）を開く。本数の多いチャンネルでは要素の検索が時間切れに
        // なるので、画面上の位置で押す。
        Thread.sleep(forTimeInterval: 5)
        AdsTestSupport.capture("03-free-list-before-tap", in: self)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.27)).tap()
        XCTAssertTrue(AdsTestSupport.player(in: app).waitForExistence(timeout: 60), "再生画面のバナーが出ない")
        Thread.sleep(forTimeInterval: 5)
        AdsTestSupport.capture("03-free-player", in: self)
    }
}
