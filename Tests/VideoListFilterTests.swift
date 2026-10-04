import XCTest
@testable import ChannelTimelineViewer

@MainActor
final class VideoListFilterTests: XCTestCase {

    private func vid(_ id: String, epoch: TimeInterval) -> VideoItem {
        VideoItem(id: id, title: id, description: "",
                  publishedAt: Date(timeIntervalSince1970: epoch),
                  thumbnailURL: nil, channelId: "c")
    }

    private func makeVM(_ videos: [VideoItem]) -> VideoListViewModel {
        VideoListViewModel(
            channel: Channel(id: "c", title: "t", thumbnailURL: nil, uploadsPlaylistId: "u"),
            preloadedVideos: videos
        )
    }

    func testUnwatchedAndWatchedFilters() {
        let vm = makeVM([vid("a", epoch: 100), vid("b", epoch: 200), vid("c", epoch: 300)])
        let watched: Set<String> = ["b"]
        let isWatched: (String) -> Bool = { watched.contains($0) }

        vm.watchFilter = .unwatched
        XCTAssertEqual(vm.visibleVideos(isWatched: isWatched).map(\.id), ["a", "c"])

        vm.watchFilter = .watched
        XCTAssertEqual(vm.visibleVideos(isWatched: isWatched).map(\.id), ["b"])

        vm.watchFilter = .all
        XCTAssertEqual(vm.visibleVideos(isWatched: isWatched).map(\.id), ["a", "b", "c"])
    }

    func testFilterRespectsSortOrder() {
        let vm = makeVM([vid("a", epoch: 100), vid("b", epoch: 200), vid("c", epoch: 300)])
        vm.sortOrder = .newest   // 新しい順
        vm.watchFilter = .all
        XCTAssertEqual(vm.visibleVideos(isWatched: { _ in false }).map(\.id), ["c", "b", "a"])
    }

    func testNextUnwatchedIsOldestUnwatched() {
        let vm = makeVM([vid("a", epoch: 100), vid("b", epoch: 200), vid("c", epoch: 300)])
        let watched: Set<String> = ["a"]    // a視聴済み → 次はb（2本目）
        let isWatched: (String) -> Bool = { watched.contains($0) }
        XCTAssertEqual(vm.nextUnwatched(isWatched: isWatched)?.id, "b")
        XCTAssertEqual(vm.nextUnwatchedPosition(isWatched: isWatched), 2)
    }

    func testNextUnwatchedNilWhenAllWatched() {
        let vm = makeVM([vid("a", epoch: 100)])
        XCTAssertNil(vm.nextUnwatched(isWatched: { _ in true }))
        XCTAssertNil(vm.nextUnwatchedPosition(isWatched: { _ in true }))
    }
}
