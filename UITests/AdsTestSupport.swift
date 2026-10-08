import XCTest

/// 広告の見え方を確かめる UI テストで使う下ごしらえ（AdsPreviewUITests / ProScreenshotUITests）。
///
/// 保存チャンネルは起動引数（UserDefaults の引数ドメイン）で入れる。アプリのコードには手を入れない。
/// 形はアプリの `FavoriteChannel` と同じ JSON。データは古い形式のプロパティリスト `<16進>` で渡す。
enum AdsTestSupport {

    struct SeedChannel: Encodable {
        let id: String
        let title: String
        let thumbnailURL: URL?
        let uploadsPlaylistId: String?
        let lastOpenedAt: Date
    }

    static let nasa = SeedChannel(
        id: "UCLA_DiR1FfKNvjuUpBHmylQ", title: "NASA", thumbnailURL: nil,
        uploadsPlaylistId: "UULA_DiR1FfKNvjuUpBHmylQ", lastOpenedAt: Date())
    static let spacex = SeedChannel(
        id: "UCtI0Hodo5o5dUb67FeUjDeA", title: "SpaceX", thumbnailURL: nil,
        uploadsPlaylistId: "UUtI0Hodo5o5dUb67FeUjDeA", lastOpenedAt: Date(timeIntervalSinceNow: -3600))
    static let veritasium = SeedChannel(
        id: "UCHnyfMqiRRG1u-2MsSQLbXA", title: "Veritasium", thumbnailURL: nil,
        uploadsPlaylistId: "UUHnyfMqiRRG1u-2MsSQLbXA", lastOpenedAt: Date(timeIntervalSinceNow: -7200))

    static func seedArguments(channels: [SeedChannel], active: String, proCached: Bool) -> [String] {
        let data = (try? JSONEncoder().encode(channels)) ?? Data()
        let hex = data.map { String(format: "%02x", $0) }.joined()
        return ["-favorite_channels_v1", "<\(hex)>",
                "-active_channel_v1", active,
                "-pro_unlocked_v1", proCached ? "YES" : "NO"]
    }

    /// 広告の部品（`Views/AdViews.swift` の accessibilityIdentifier）。
    static func anchor(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["ad.anchor"]
    }

    static func mrec(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["ad.mrec"]
    }

    static func player(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["ad.player"]
    }

    static func capture(_ name: String, in test: XCTestCase) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        test.add(attachment)
    }
}
