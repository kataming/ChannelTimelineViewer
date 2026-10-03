import StoreKitTest
import XCTest

/// 無料版の広告（AdMob・デバッグなのでテスト広告）の見え方を撮る UI テスト。
/// 実行は `.github/workflows/ios-screenshots.yml`（Screenshots スキームが UITests をすべて走らせる）から。
/// 購入済みの状態は SKTestSession で作る。
///
/// 撮る場面（docs/admob-ads.md）:
///   1. 無料・保存チャンネル1件 … 最初の画面の MREC、動画一覧のアンカー型バナー
///   2. Pro から無料に戻った・保存チャンネル3件（2件はロック） … MREC が下にずれる場面
///   3. Pro・保存チャンネル3件 … どこにも広告が出ないこと
///
/// 保存チャンネルは起動引数（UserDefaults の引数ドメイン）で入れる。アプリのコードには手を入れない。
/// テストは名前順に走るので、購入する 3 を最後にしている。
final class AdsPreviewUITests: XCTestCase {

    private var app: XCUIApplication!
    private var session: SKTestSession!

    private lazy var strings: Bundle = {
        let testBundle = Bundle(for: type(of: self))
        if let path = testBundle.path(forResource: "ja", ofType: "lproj"),
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
        session = try SKTestSession(configurationFileNamed: "ProStoreKit")
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments += ["-channelTutorialCompleted", "YES"]
    }

    // MARK: - 場面

    func test1_無料_保存1件() throws {
        seed(channels: [Self.nasa], active: Self.nasa.id, proCached: false)
        app.launch()
        captureHomeAndList(prefix: "01-free-1ch", expectAds: true)
    }

    func test2_Proから無料_保存3件() throws {
        // 端末内の Pro の写しは「持っている」のまま、StoreKit には購入が無い＝起動後に無料へ落ちる。
        seed(channels: [Self.nasa, Self.spacex, Self.veritasium], active: Self.nasa.id, proCached: true)
        app.launch()
        captureHomeAndList(prefix: "02-pro-to-free-3ch", expectAds: true)
    }

    func test3_Pro_保存3件() throws {
        // StoreKit のテスト環境で購入済みにする（確認ダイアログは出さない）。
        try session.buyProduct(productIdentifier: "pro_unlock")
        seed(channels: [Self.nasa, Self.spacex, Self.veritasium], active: Self.nasa.id, proCached: true)
        app.launch()
        captureHomeAndList(prefix: "03-pro-3ch", expectAds: false)
    }

    // MARK: - 撮影

    private func captureHomeAndList(prefix: String, expectAds: Bool) {
        let title = app.staticTexts["NASA"]
        XCTAssertTrue(title.waitForExistence(timeout: 60), "保存チャンネルが表示されない")

        // 広告の読み込み（同意の確認 → 初期化 → 読み込み）を待つ。
        let adLabel = app.staticTexts[L("ads.label")]
        if expectAds {
            app.swipeUp()
            XCTAssertTrue(adLabel.waitForExistence(timeout: 60), "MREC が出ない")
            app.swipeDown()
        } else {
            Thread.sleep(forTimeInterval: 20)
        }
        capture("\(prefix)-a-home-top")
        app.swipeUp()
        Thread.sleep(forTimeInterval: 2)
        capture("\(prefix)-b-home-scrolled")
        if !expectAds {
            XCTAssertFalse(adLabel.exists, "Pro なのに MREC が出ている")
        }
        app.swipeDown()

        title.tap()
        // 一覧の取得とバナーの読み込みを待つ。
        Thread.sleep(forTimeInterval: 25)
        capture("\(prefix)-c-videolist")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - 保存データ（アプリの FavoriteChannel と同じ形の JSON）

    private struct SeedChannel: Encodable {
        let id: String
        let title: String
        let thumbnailURL: URL?
        let uploadsPlaylistId: String?
        let lastOpenedAt: Date
    }

    private static let nasa = SeedChannel(
        id: "UCLA_DiR1FfKNvjuUpBHmylQ", title: "NASA", thumbnailURL: nil,
        uploadsPlaylistId: "UULA_DiR1FfKNvjuUpBHmylQ", lastOpenedAt: Date())
    private static let spacex = SeedChannel(
        id: "UCtI0Hodo5o5dUb67FeUjDeA", title: "SpaceX", thumbnailURL: nil,
        uploadsPlaylistId: "UUtI0Hodo5o5dUb67FeUjDeA", lastOpenedAt: Date(timeIntervalSinceNow: -3600))
    private static let veritasium = SeedChannel(
        id: "UCHnyfMqiRRG1u-2MsSQLbXA", title: "Veritasium", thumbnailURL: nil,
        uploadsPlaylistId: "UUHnyfMqiRRG1u-2MsSQLbXA", lastOpenedAt: Date(timeIntervalSinceNow: -7200))

    /// 起動引数で UserDefaults に入れる。データは古い形式のプロパティリスト `<16進>` で渡す。
    private func seed(channels: [SeedChannel], active: String, proCached: Bool) {
        let data = (try? JSONEncoder().encode(channels)) ?? Data()
        let hex = data.map { String(format: "%02x", $0) }.joined()
        app.launchArguments += ["-favorite_channels_v1", "<\(hex)>"]
        app.launchArguments += ["-active_channel_v1", active]
        app.launchArguments += ["-pro_unlocked_v1", proCached ? "YES" : "NO"]
    }
}
