import XCTest
@testable import ChannelTimelineViewer

/// 共有シートから渡された URL を、クリップボード経由で拾う処理のテスト。
/// （iOS の仕様で共有拡張はアプリを直接開けないため、この経路が実質の受け渡し口になる）
@MainActor
final class ClipboardLinkDetectorTests: XCTestCase {

    /// テスト用のクリップボード。中身を読んだ回数も記録する。
    private final class FakePasteboard: PasteboardProviding {
        var content: String?
        var looksLikeURL: Bool
        private(set) var readCount = 0

        init(content: String?, looksLikeURL: Bool) {
            self.content = content
            self.looksLikeURL = looksLikeURL
        }

        func containsProbableURL() async -> Bool { looksLikeURL }

        func readString() -> String? {
            readCount += 1
            return content
        }
    }

    func testShowsButtonWhenClipboardLooksLikeURL() async {
        let pasteboard = FakePasteboard(content: "https://youtu.be/dQw4w9WgXcQ", looksLikeURL: true)
        let detector = ClipboardLinkDetector(pasteboard: pasteboard)

        XCTAssertFalse(detector.hasCandidate)
        await detector.refresh()

        XCTAssertTrue(detector.hasCandidate)
        XCTAssertEqual(pasteboard.readCount, 0, "表示判定では中身を読まない（ペースト確認を出さない）")
    }

    func testDoesNotShowButtonWhenClipboardHasNoURL() async {
        let detector = ClipboardLinkDetector(
            pasteboard: FakePasteboard(content: "ただのメモ", looksLikeURL: false))
        await detector.refresh()
        XCTAssertFalse(detector.hasCandidate)
    }

    func testTakesYouTubeLinkFromClipboard() async {
        let pasteboard = FakePasteboard(content: "https://www.youtube.com/@SomeHandle", looksLikeURL: true)
        let detector = ClipboardLinkDetector(pasteboard: pasteboard)
        await detector.refresh()

        XCTAssertEqual(detector.takeYouTubeLink(), "https://www.youtube.com/@SomeHandle")
        XCTAssertEqual(pasteboard.readCount, 1, "ボタンを押したときだけ読む")
        XCTAssertFalse(detector.hasCandidate, "取り込んだらボタンは消える")
    }

    func testExtractsURLFromSharedTextInClipboard() async {
        let pasteboard = FakePasteboard(
            content: "面白い動画\nhttps://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK", looksLikeURL: true)
        let detector = ClipboardLinkDetector(pasteboard: pasteboard)
        await detector.refresh()

        XCTAssertEqual(detector.takeYouTubeLink(), "https://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK")
    }

    func testIgnoresNonYouTubeURL() async {
        let detector = ClipboardLinkDetector(
            pasteboard: FakePasteboard(content: "https://example.com/page", looksLikeURL: true))
        await detector.refresh()

        XCTAssertNil(detector.takeYouTubeLink(), "YouTube 以外は取り込まない")
        XCTAssertFalse(detector.hasCandidate)
    }

    func testDoesNotOfferTheSameLinkTwice() async {
        let pasteboard = FakePasteboard(content: "https://youtu.be/dQw4w9WgXcQ", looksLikeURL: true)
        let detector = ClipboardLinkDetector(pasteboard: pasteboard)

        await detector.refresh()
        XCTAssertNotNil(detector.takeYouTubeLink())

        // クリップボードは変わっていない（同じURLのまま）
        await detector.refresh()
        XCTAssertNil(detector.takeYouTubeLink(), "一度開いたURLは再提示しない")
    }

    func testOffersAgainWhenClipboardChanges() async {
        let pasteboard = FakePasteboard(content: "https://youtu.be/dQw4w9WgXcQ", looksLikeURL: true)
        let detector = ClipboardLinkDetector(pasteboard: pasteboard)
        await detector.refresh()
        _ = detector.takeYouTubeLink()

        pasteboard.content = "https://www.youtube.com/@AnotherChannel"
        await detector.refresh()

        XCTAssertEqual(detector.takeYouTubeLink(), "https://www.youtube.com/@AnotherChannel")
    }
}
