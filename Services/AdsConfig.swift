import Foundation

/// どの広告ユニットを使うか（テスト広告か本番か）。Android 版 `ads/AdsConfig.kt` と同じ規則。
///
/// - デバッグビルド: **常に Google 公式のテスト広告**。本番 ID が設定されていても使わない
///   （開発中に自分で本番広告を表示・クリックしないため）
/// - リリースビルド: project.yml の `ADMOB_*_UNIT_ID`（Info.plist 経由）が揃っていれば本番。
///   1つでも欠けていれば `isEnabled` が false になり、SDK の初期化も広告リクエストもしない
struct AdsConfig: Equatable {
    let bannerUnitID: String
    let mrecUnitID: String
    let usesTestAds: Bool

    /// 広告ユニットが揃っているか。false なら広告まわりは何もしない。
    var isEnabled: Bool { !bannerUnitID.isEmpty && !mrecUnitID.isEmpty }

    /// Google 公式のテスト用アダプティブバナー（iOS）。
    static let testAdaptiveBannerUnitID = "ca-app-pub-3940256099942544/2435281174"
    /// Google 公式のテスト用バナー（iOS）。MREC（300×250）もこのユニットで出す。
    static let testBannerUnitID = "ca-app-pub-3940256099942544/2934735716"

    static let test = AdsConfig(
        bannerUnitID: testAdaptiveBannerUnitID,
        mrecUnitID: testBannerUnitID,
        usesTestAds: true)

    static func make(isDebug: Bool, bannerUnitID: String?, mrecUnitID: String?) -> AdsConfig {
        if isDebug { return .test }
        return AdsConfig(
            bannerUnitID: (bannerUnitID ?? "").trimmingCharacters(in: .whitespaces),
            mrecUnitID: (mrecUnitID ?? "").trimmingCharacters(in: .whitespaces),
            usesTestAds: false)
    }

    /// このビルドの設定（Info.plist の CTVAdMob*UnitID を読む）。
    static var current: AdsConfig {
        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif
        return make(
            isDebug: isDebug,
            bannerUnitID: Bundle.main.object(forInfoDictionaryKey: "CTVAdMobBannerUnitID") as? String,
            mrecUnitID: Bundle.main.object(forInfoDictionaryKey: "CTVAdMobMRECUnitID") as? String)
    }
}

/// 広告を出してよいか（＝広告リクエストを送ってよいか）の判定。判断はここ1か所だけで行う。
///
/// ⚠️ **Pro は完全に広告なし。** 画面で隠すだけでなく、SDK の初期化・同意フォーム・
/// 広告リクエストのどれも行わない。Pro かどうかの正は既存の `ProEntitlementStore` で、
/// 広告側はそれを読むだけ（課金側のロジックには手を入れない）。
enum AdVisibilityPolicy {
    /// 広告まわりの準備（同意の確認・SDK の初期化）を始めてよいか。
    /// Pro には同意フォームも出さない（広告を出さない人に広告の同意を求めない）。
    static func shouldPrepare(isPro: Bool, isConfigured: Bool) -> Bool {
        !isPro && isConfigured
    }

    /// 広告リクエストを送ってよいか。
    /// - Parameters:
    ///   - canRequestAds: UMP が「広告をリクエストしてよい」と判定したか
    ///   - isSDKReady: MobileAds の初期化が終わったか
    static func canRequestAds(isPro: Bool, isConfigured: Bool,
                              canRequestAds: Bool, isSDKReady: Bool) -> Bool {
        shouldPrepare(isPro: isPro, isConfigured: isConfigured) && canRequestAds && isSDKReady
    }
}
