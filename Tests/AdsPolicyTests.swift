import Combine
import XCTest
@testable import ChannelTimelineViewer

/// 無料版の広告（AdMob）の約束。Android 版 `AdsPolicyTest.kt` と同じ内容を確かめる。
///   - Pro は完全に広告なし（同意フォーム・SDK の初期化・広告リクエストのどれもしない）
///   - 開発中（デバッグビルド）は必ずテスト広告
///   - 本番 ID が揃っていないリリースは広告を一切出さない
@MainActor
final class AdsPolicyTests: XCTestCase {

    // MARK: - 判定

    func test_Proは広告の準備もリクエストもしない() {
        XCTAssertFalse(AdVisibilityPolicy.shouldPrepare(isPro: true, isConfigured: true))
        XCTAssertFalse(AdVisibilityPolicy.canRequestAds(
            isPro: true, isConfigured: true, canRequestAds: true, isSDKReady: true))
    }

    func test_無料は同意とSDKの準備が済んだときだけリクエストする() {
        XCTAssertTrue(AdVisibilityPolicy.canRequestAds(
            isPro: false, isConfigured: true, canRequestAds: true, isSDKReady: true))
        XCTAssertFalse(AdVisibilityPolicy.canRequestAds(
            isPro: false, isConfigured: true, canRequestAds: false, isSDKReady: true))
        XCTAssertFalse(AdVisibilityPolicy.canRequestAds(
            isPro: false, isConfigured: true, canRequestAds: true, isSDKReady: false))
    }

    func test_広告IDが未設定なら無料でも何もしない() {
        XCTAssertFalse(AdVisibilityPolicy.shouldPrepare(isPro: false, isConfigured: false))
    }

    // MARK: - テスト広告と本番の切り替え

    func test_デバッグビルドは本番IDがあってもテスト広告を使う() {
        let config = AdsConfig.make(isDebug: true,
                                    bannerUnitID: "ca-app-pub-0000000000000000/1111111111",
                                    mrecUnitID: "ca-app-pub-0000000000000000/2222222222")
        XCTAssertEqual(config, .test)
        XCTAssertTrue(config.usesTestAds)
        XCTAssertTrue(config.bannerUnitID.hasPrefix("ca-app-pub-3940256099942544/"))
        XCTAssertTrue(config.mrecUnitID.hasPrefix("ca-app-pub-3940256099942544/"))
    }

    func test_リリースで本番IDが揃っていなければ広告を出さない() {
        XCTAssertFalse(AdsConfig.make(isDebug: false, bannerUnitID: "", mrecUnitID: "").isEnabled)
        XCTAssertFalse(AdsConfig.make(isDebug: false, bannerUnitID: nil, mrecUnitID: nil).isEnabled)
        XCTAssertFalse(AdsConfig.make(isDebug: false, bannerUnitID: "ca-app-pub-1/2", mrecUnitID: " ").isEnabled)
    }

    func test_リリースで本番IDが揃っていれば本番を使う() {
        let config = AdsConfig.make(isDebug: false, bannerUnitID: " ca-app-pub-1/2 ", mrecUnitID: "ca-app-pub-1/3")
        XCTAssertTrue(config.isEnabled)
        XCTAssertFalse(config.usesTestAds)
        XCTAssertEqual(config.bannerUnitID, "ca-app-pub-1/2")
    }

    // MARK: - AdsManager

    func test_Proなら同意フォームの確認すら始めない() {
        let isPro = CurrentValueSubject<Bool, Never>(true)
        let ads = AdsManager(config: .test, isPro: true, isProPublisher: isPro.eraseToAnyPublisher())
        ads.activate()
        XCTAssertFalse(ads.consentStarted)
        XCTAssertFalse(ads.canShowAds)
        XCTAssertFalse(ads.privacyOptionsRequired)
    }

    func test_広告IDが未設定のリリースは同意フォームの確認も始めない() {
        let isPro = CurrentValueSubject<Bool, Never>(false)
        let ads = AdsManager(config: .make(isDebug: false, bannerUnitID: "", mrecUnitID: ""),
                             isPro: false, isProPublisher: isPro.eraseToAnyPublisher())
        ads.activate()
        XCTAssertFalse(ads.consentStarted)
        XCTAssertFalse(ads.canShowAds)
    }

    func test_準備前は広告を出さない() {
        let isPro = CurrentValueSubject<Bool, Never>(false)
        let ads = AdsManager(config: .test, isPro: false, isProPublisher: isPro.eraseToAnyPublisher())
        XCTAssertFalse(ads.canShowAds)
    }

    /// 再生画面のバナーは、専用のユニットが無ければ一覧のバナーと同じユニットを使う（Android と同じ）。
    func testPlayerBannerFallsBackToListBanner() {
        let shared = AdsConfig.make(isDebug: false, bannerUnitID: "ca-app-pub-1/2", mrecUnitID: "ca-app-pub-1/3")
        XCTAssertEqual(shared.playerBannerUnit, "ca-app-pub-1/2")
        let own = AdsConfig.make(isDebug: false, bannerUnitID: "ca-app-pub-1/2", mrecUnitID: "ca-app-pub-1/3",
                                 playerBannerUnitID: "ca-app-pub-1/4")
        XCTAssertEqual(own.playerBannerUnit, "ca-app-pub-1/4")
    }
}
