import XCTest
@testable import ChannelTimelineViewer

/// 動画一覧の読み込みの進み具合（％）の分母。Android の YouTubeApiClient.fetchVideos と同じ考え方。
final class LoadProgressTests: XCTestCase {

    func testTotalComesFromTheApi() {
        XCTAssertEqual(YouTubeAPIClient.progressTotal(2_800, maxPages: 100), 2_800)
    }

    /// 上限（ページ数 × 50）より多いチャンネルでは、上限で頭打ちにする（100% で止まるように）。
    func testTotalIsCappedByThePagesWeRead() {
        XCTAssertEqual(YouTubeAPIClient.progressTotal(12_000, maxPages: 100), 5_000)
    }

    /// 全体の本数が返ってこないときは 0（％を出さず、従来の「読み込み中」を出す）。
    func testUnknownTotalIsZero() {
        XCTAssertEqual(YouTubeAPIClient.progressTotal(nil, maxPages: 100), 0)
    }
}
