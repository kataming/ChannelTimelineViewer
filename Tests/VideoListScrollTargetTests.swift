import XCTest
@testable import ChannelTimelineViewer

/// 動画一覧のメニュー「一番上へ」「一番下へ」の飛び先。
final class VideoListScrollTargetTests: XCTestCase {

    private let ids = ["v1", "v2", "v3"]

    func testTopIsProgressRowWhenNotSearching() {
        XCTAssertEqual(VideoListScrollTarget.id(for: .top, isSearching: false, hasProgressRow: true,
                                                visibleVideoIds: ids),
                       VideoListScrollTarget.progressRowID)
    }

    func testTopIsSearchRowWhileSearching() {
        XCTAssertEqual(VideoListScrollTarget.id(for: .top, isSearching: true, hasProgressRow: true,
                                                visibleVideoIds: ids),
                       VideoListScrollTarget.searchRowID)
    }

    func testTopFallsBackToFirstVideo() {
        XCTAssertEqual(VideoListScrollTarget.id(for: .top, isSearching: false, hasProgressRow: false,
                                                visibleVideoIds: ids), "v1")
    }

    func testBottomIsLastVisibleVideo() {
        XCTAssertEqual(VideoListScrollTarget.id(for: .bottom, isSearching: false, hasProgressRow: true,
                                                visibleVideoIds: ids), "v3")
    }

    func testBottomOfLargeChannel() {
        let many = (0..<6_000).map { "id\($0)" }
        XCTAssertEqual(VideoListScrollTarget.id(for: .bottom, isSearching: false, hasProgressRow: true,
                                                visibleVideoIds: many), "id5999")
    }

    func testNoTargetWhenNothingIsVisible() {
        XCTAssertNil(VideoListScrollTarget.id(for: .bottom, isSearching: true, hasProgressRow: true,
                                              visibleVideoIds: []))
        XCTAssertNil(VideoListScrollTarget.id(for: .top, isSearching: false, hasProgressRow: false,
                                              visibleVideoIds: []))
    }

    func testAnchorIdsDoNotCollideWithVideoIds() {
        // 動画 ID は 11 文字。行の ID と取り違えないこと。
        XCTAssertNotEqual(VideoListScrollTarget.searchRowID.count, 11)
        XCTAssertNotEqual(VideoListScrollTarget.progressRowID.count, 11)
    }
}
