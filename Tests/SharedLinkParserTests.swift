import XCTest
@testable import ChannelTimelineViewer

/// 共有シート（Share Extension）から渡されるテキスト / URL の解析テスト。
/// Share Extension 側でも同じ SharedLinkParser を使うため、ここでの検証がそのまま共有機能の検証になる。
final class SharedLinkParserTests: XCTestCase {

    // MARK: - YouTube URL の判定

    func testAcceptsChannelURLs() {
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://www.youtube.com/@handle"))
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv"))
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://www.youtube.com/c/name"))
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://www.youtube.com/user/name"))
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://m.youtube.com/@handle"))
    }

    func testAcceptsVideoURLs() {
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertTrue(SharedLinkParser.isYouTubeURLString("https://youtu.be/dQw4w9WgXcQ"))
    }

    func testRejectsNonYouTubeURLs() {
        XCTAssertFalse(SharedLinkParser.isYouTubeURLString("https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertFalse(SharedLinkParser.isYouTubeURLString("https://notyoutube.com/@handle"))
        XCTAssertFalse(SharedLinkParser.isYouTubeURLString("ふつうのテキスト"))
        XCTAssertFalse(SharedLinkParser.isYouTubeURLString(""))
    }

    // MARK: - テキストからの抽出（YouTube アプリがテキストで共有してくるケース）

    func testExtractsURLFromSharedTextWithTitle() {
        let shared = "すごい動画のタイトル\nhttps://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK"
        XCTAssertEqual(SharedLinkParser.extractYouTubeURLString(from: shared),
                       "https://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK")
    }

    func testExtractsURLFromTextWithTrailingPunctuation() {
        let shared = "これ見て →「https://www.youtube.com/watch?v=dQw4w9WgXcQ」"
        XCTAssertEqual(SharedLinkParser.extractYouTubeURLString(from: shared),
                       "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
    }

    func testExtractsChannelURLFromText() {
        let shared = "チャンネルはこちら https://www.youtube.com/@SomeHandle です"
        XCTAssertEqual(SharedLinkParser.extractYouTubeURLString(from: shared),
                       "https://www.youtube.com/@SomeHandle")
    }

    func testExtractsURLWithoutScheme() {
        XCTAssertEqual(SharedLinkParser.extractYouTubeURLString(from: "youtube.com/@handle"),
                       "https://youtube.com/@handle")
    }

    func testReturnsNilWhenTextHasNoYouTubeURL() {
        XCTAssertNil(SharedLinkParser.extractYouTubeURLString(from: "ただのメモです https://example.com/page"))
        XCTAssertNil(SharedLinkParser.extractYouTubeURLString(from: "   "))
    }

    // MARK: - カスタムURL（Extension → メインアプリ）の往復

    func testAppURLRoundTripKeepsQueryParameters() throws {
        let original = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s"
        let appURL = try XCTUnwrap(SharedLinkParser.makeAppURL(for: original))
        XCTAssertEqual(appURL.scheme, "channeltimelineviewer")
        XCTAssertEqual(SharedLinkParser.youTubeURLString(fromAppURL: appURL), original)
    }

    func testAppURLRoundTripForShortURL() throws {
        let original = "https://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK"
        let appURL = try XCTUnwrap(SharedLinkParser.makeAppURL(for: original))
        XCTAssertEqual(SharedLinkParser.youTubeURLString(fromAppURL: appURL), original)
    }

    func testMakeAppURLRejectsNonYouTubeURL() {
        XCTAssertNil(SharedLinkParser.makeAppURL(for: "https://example.com/watch?v=dQw4w9WgXcQ"))
    }

    func testAppURLParsingRejectsOtherSchemes() throws {
        let other = try XCTUnwrap(URL(string: "otherapp://share?url=https%3A%2F%2Fyoutu.be%2FdQw4w9WgXcQ"))
        XCTAssertNil(SharedLinkParser.youTubeURLString(fromAppURL: other))
    }

    func testAppURLParsingRejectsNonYouTubePayload() throws {
        let evil = try XCTUnwrap(URL(string: "channeltimelineviewer://share?url=https%3A%2F%2Fexample.com%2F"))
        XCTAssertNil(SharedLinkParser.youTubeURLString(fromAppURL: evil))
    }

    // MARK: - ルーター（メインアプリ側の受け口）

    @MainActor
    func testRouterAcceptsSharedLink() throws {
        let router = SharedLinkRouter()
        let appURL = try XCTUnwrap(SharedLinkParser.makeAppURL(for: "https://youtu.be/dQw4w9WgXcQ"))

        XCTAssertTrue(router.handle(appURL))
        XCTAssertEqual(router.pendingLink, "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertEqual(router.consume(), "https://youtu.be/dQw4w9WgXcQ")
        XCTAssertNil(router.pendingLink, "一度取り出したら消費される（二重処理しない）")
    }

    @MainActor
    func testRouterIgnoresUnrelatedURL() throws {
        let router = SharedLinkRouter()
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertFalse(router.handle(url))
        XCTAssertNil(router.pendingLink)
    }
}
