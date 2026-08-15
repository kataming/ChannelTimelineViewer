import XCTest
@testable import ChannelTimelineViewer

final class ChannelResolverTests: XCTestCase {

    func testChannelIdURL() throws {
        let id = "UC1234567890123456789012" // UC + 22文字 = 24
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/channel/\(id)"),
                       .channelId(id))
    }

    func testBareChannelId() throws {
        let id = "UCabcdefghijklmnopqrstuv"
        XCTAssertEqual(try ChannelResolver.parse(id), .channelId(id))
    }

    func testHandleURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/@SomeHandle"),
                       .handle("SomeHandle"))
    }

    func testBareHandle() throws {
        XCTAssertEqual(try ChannelResolver.parse("@SomeHandle"), .handle("SomeHandle"))
    }

    func testUserURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/user/LegacyName"),
                       .username("LegacyName"))
    }

    func testCustomCURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/c/CustomName"),
                       .customName("CustomName"))
    }

    func testCustomBareNameURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/SomeName"),
                       .customName("SomeName"))
    }

    func testWithoutScheme() throws {
        XCTAssertEqual(try ChannelResolver.parse("youtube.com/@handle"), .handle("handle"))
    }

    // MARK: - 動画URL（共有シートから来るケース）

    func testWatchURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                       .video("dQw4w9WgXcQ"))
    }

    func testWatchURLWithExtraQuery() throws {
        // 共有時に付く feature / t などのパラメータがあっても videoId を取れること
        XCTAssertEqual(
            try ChannelResolver.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&feature=shared&t=42s"),
            .video("dQw4w9WgXcQ"))
    }

    func testMobileWatchURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ"),
                       .video("dQw4w9WgXcQ"))
    }

    func testShortURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://youtu.be/dQw4w9WgXcQ"),
                       .video("dQw4w9WgXcQ"))
    }

    func testShortURLWithShareParameter() throws {
        // YouTube アプリの共有は ?si=... が付く
        XCTAssertEqual(try ChannelResolver.parse("https://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK"),
                       .video("dQw4w9WgXcQ"))
    }

    func testShortsURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/shorts/dQw4w9WgXcQ"),
                       .video("dQw4w9WgXcQ"))
    }

    func testLiveURL() throws {
        XCTAssertEqual(try ChannelResolver.parse("https://www.youtube.com/live/dQw4w9WgXcQ"),
                       .video("dQw4w9WgXcQ"))
    }

    func testInvalidWatchURLWithoutVideoId() {
        XCTAssertThrowsError(try ChannelResolver.parse("https://www.youtube.com/watch"))
    }

    func testInvalidShortURLWithBrokenId() {
        XCTAssertThrowsError(try ChannelResolver.parse("https://youtu.be/short"))
    }

    // MARK: - videoId の抽出

    func testExtractVideoId() {
        XCTAssertEqual(ChannelResolver.extractVideoId(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(ChannelResolver.extractVideoId(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"),
                       "dQw4w9WgXcQ")
        XCTAssertEqual(ChannelResolver.extractVideoId(from: " dQw4w9WgXcQ "), "dQw4w9WgXcQ",
                       "videoId 単体も受け付ける")
        XCTAssertNil(ChannelResolver.extractVideoId(from: "https://www.youtube.com/@handle"),
                     "チャンネルURLからは videoId を取らない")
        XCTAssertNil(ChannelResolver.extractVideoId(from: "https://example.com/watch?v=dQw4w9WgXcQ"))
    }

    func testIsVideoId() {
        XCTAssertTrue(ChannelResolver.isVideoId("dQw4w9WgXcQ"))
        XCTAssertTrue(ChannelResolver.isVideoId("a-b_c1234XY"))
        XCTAssertFalse(ChannelResolver.isVideoId("short"))
        XCTAssertFalse(ChannelResolver.isVideoId("dQw4w9WgXcQTOOLONG"))
        XCTAssertFalse(ChannelResolver.isVideoId("dQw4w9WgXc!"))
    }

    func testInvalidEmpty() {
        XCTAssertThrowsError(try ChannelResolver.parse("   "))
    }

    func testInvalidNonYouTubeHost() {
        XCTAssertThrowsError(try ChannelResolver.parse("https://example.com/@handle"))
    }

    func testInvalidChannelIdInPath() {
        XCTAssertThrowsError(try ChannelResolver.parse("https://www.youtube.com/channel/NOT_AN_ID"))
    }
}
