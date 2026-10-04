import XCTest
@testable import ChannelTimelineViewer

final class VideoSortTests: XCTestCase {

    private func video(_ id: String, epoch: TimeInterval) -> VideoItem {
        VideoItem(id: id,
                  title: id,
                  description: "",
                  publishedAt: Date(timeIntervalSince1970: epoch),
                  thumbnailURL: nil,
                  channelId: "channel")
    }

    func testAscendingIsOldestFirst() {
        let items = [video("c", epoch: 300), video("a", epoch: 100), video("b", epoch: 200)]
        let sorted = items.sortedByPublishedDate(ascending: true)
        XCTAssertEqual(sorted.map(\.id), ["a", "b", "c"])
    }

    func testDescendingIsNewestFirst() {
        let items = [video("c", epoch: 300), video("a", epoch: 100), video("b", epoch: 200)]
        let sorted = items.sortedByPublishedDate(ascending: false)
        XCTAssertEqual(sorted.map(\.id), ["c", "b", "a"])
    }

    func testEmptyStaysEmpty() {
        XCTAssertTrue([VideoItem]().sortedByPublishedDate(ascending: true).isEmpty)
    }

    // MARK: - 人気順（視聴回数の多い順）

    private func video(_ id: String, epoch: TimeInterval, views: Int?) -> VideoItem {
        var v = video(id, epoch: epoch)
        v.viewCount = views
        return v
    }

    func testPopularIsMostViewedFirst() {
        let items = [video("a", epoch: 100, views: 10), video("b", epoch: 200, views: 5_000), video("c", epoch: 300, views: 300)]
        XCTAssertEqual(items.sorted(by: .popular).map(\.id), ["b", "c", "a"])
    }

    func testPopularPutsUnknownCountsLastOldestFirst() {
        let items = [video("x", epoch: 300, views: nil), video("a", epoch: 100, views: 1), video("y", epoch: 200, views: nil)]
        XCTAssertEqual(items.sorted(by: .popular).map(\.id), ["a", "y", "x"])
    }

    func testPopularTieBreaksByOldest() {
        let items = [video("b", epoch: 200, views: 7), video("a", epoch: 100, views: 7)]
        XCTAssertEqual(items.sorted(by: .popular).map(\.id), ["a", "b"])
    }

    func testOldestAndNewestOrders() {
        let items = [video("c", epoch: 300), video("a", epoch: 100), video("b", epoch: 200)]
        XCTAssertEqual(items.sorted(by: .oldest).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(items.sorted(by: .newest).map(\.id), ["c", "b", "a"])
    }

    func testApplyingViewCountsKeepsUnknownAsBefore() {
        let items = [video("a", epoch: 100, views: 3), video("b", epoch: 200, views: nil)]
        let updated = items.applyingViewCounts(["b": 42])
        XCTAssertEqual(updated.map(\.viewCount), [3, 42])
    }

    func testDateAndViewsWithoutCountIsDateOnly() {
        let v = video("a", epoch: 100, views: nil)
        XCTAssertEqual(v.dateAndViews(.long), v.publishedAt.formatted(date: .long, time: .omitted))
        XCTAssertNil(v.viewCountText)
    }

    func testDateAndViewsAppendsCount() {
        let v = video("a", epoch: 100, views: 100_000)
        XCTAssertTrue(v.dateAndViews(.long).hasPrefix(v.publishedAt.formatted(date: .long, time: .omitted) + " · "))
        XCTAssertNotNil(v.viewCountText)
    }
}
