import XCTest
import UserNotifications
@testable import ChannelTimelineViewer

/// 共有シート → ローカル通知 → タップでアプリを開く経路のテスト。
final class SharedLinkNotifierTests: XCTestCase {

    func testBuildsRequestWithLinkInUserInfo() throws {
        let link = "https://youtu.be/dQw4w9WgXcQ"
        let request = try XCTUnwrap(SharedLinkNotifier.makeRequest(for: link))

        XCTAssertEqual(request.identifier, SharedLinkNotifier.requestIdentifier,
                       "共有のたびに置き換える（通知が積み上がらない）")
        XCTAssertNil(request.trigger, "共有した直後に即時配信する")
        XCTAssertFalse(request.content.body.isEmpty)
        XCTAssertEqual(request.content.userInfo[SharedLinkNotifier.linkUserInfoKey] as? String, link)
    }

    func testNormalizesLinkWithoutScheme() throws {
        let request = try XCTUnwrap(SharedLinkNotifier.makeRequest(for: "youtube.com/@SomeHandle"))
        XCTAssertEqual(request.content.userInfo[SharedLinkNotifier.linkUserInfoKey] as? String,
                       "https://youtube.com/@SomeHandle")
    }

    func testDoesNotBuildRequestForNonYouTubeLink() {
        XCTAssertNil(SharedLinkNotifier.makeRequest(for: "https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(SharedLinkNotifier.makeRequest(for: ""))
    }

    func testReadsLinkFromUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            SharedLinkNotifier.linkUserInfoKey: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        ]
        XCTAssertEqual(SharedLinkNotifier.link(from: userInfo),
                       "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testIgnoresUserInfoWithoutValidLink() {
        XCTAssertNil(SharedLinkNotifier.link(from: [:]))
        XCTAssertNil(SharedLinkNotifier.link(from: ["other": "https://youtu.be/dQw4w9WgXcQ"]))
        XCTAssertNil(SharedLinkNotifier.link(
            from: [SharedLinkNotifier.linkUserInfoKey: "https://example.com/"]),
            "YouTube 以外のURLは受け付けない")
        XCTAssertNil(SharedLinkNotifier.link(from: [SharedLinkNotifier.linkUserInfoKey: 42]))
    }

    /// 通知タップ相当の入力で、共有経路と同じようにチャンネルが解決できること。
    @MainActor
    func testRouterAcceptsLinkFromNotification() {
        let suite = "test.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let router = SharedLinkRouter(defaults: defaults)

        XCTAssertFalse(router.hasUsedShareHandoff)
        XCTAssertTrue(router.handleLink("https://youtu.be/dQw4w9WgXcQ"))
        XCTAssertEqual(router.consume(), "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertTrue(router.hasUsedShareHandoff, "共有経由で開いたことを記録する")
    }

    /// 共有を速くする案内は、共有を使ったあとに出て、閉じたら二度と出ないこと。
    @MainActor
    func testShareTipsAppearAfterFirstHandoffAndCanBeDismissed() {
        let suite = "test.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let router = SharedLinkRouter(defaults: defaults)

        XCTAssertFalse(router.hasUsedShareHandoff, "初回起動では案内を出さない")
        router.markShareHandoffUsed()
        XCTAssertTrue(router.hasUsedShareHandoff)
        XCTAssertFalse(router.hasDismissedShareTips)

        router.dismissShareTips()
        XCTAssertTrue(router.hasDismissedShareTips)

        // アプリを再起動しても状態が残る
        let reloaded = SharedLinkRouter(defaults: defaults)
        XCTAssertTrue(reloaded.hasUsedShareHandoff)
        XCTAssertTrue(reloaded.hasDismissedShareTips)
    }

    @MainActor
    func testRouterRejectsNonYouTubeLink() {
        let suite = "test.router.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let router = SharedLinkRouter(defaults: defaults)

        XCTAssertFalse(router.handleLink("https://example.com/"))
        XCTAssertNil(router.pendingLink)
    }
}
