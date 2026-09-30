import XCTest
@testable import ChannelTimelineViewer

/// チャンネル内検索（タイトルの絞り込み・docs/channel-search.md）。
/// ⚠️ 一致の例は Android `ChannelSearchTest.kt` と Web `site/scripts/test-trial.mjs` と同じにしてある。
@MainActor
final class ChannelSearchTests: XCTestCase {

    private func vid(_ id: String, title: String, epoch: TimeInterval) -> VideoItem {
        VideoItem(id: id, title: title, description: "説明文にだけ chatgpt がある",
                  publishedAt: Date(timeIntervalSince1970: epoch),
                  thumbnailURL: nil, channelId: "c")
    }

    private func makeVM(_ videos: [VideoItem], channelId: String = "c") -> VideoListViewModel {
        VideoListViewModel(
            channel: Channel(id: channelId, title: "t", thumbnailURL: nil, uploadsPlaylistId: "u"),
            preloadedVideos: videos
        )
    }

    // ---- 一致の規則（3つで同じ例） ----

    func testSharedMatchCases() {
        let cases: [(String, String, Bool)] = [
            ("How to Use ChatGPT for Work", "chatgpt", true),
            ("How to Use ChatGPT for Work", "CHATGPT", true),
            ("How to Use ChatGPT for Work", "Use Chat", true),
            ("ＣｈａｔＧＰＴ入門", "chatgpt", true),
            ("日本語の動画タイトル", "動画", true),
            ("ｶﾀｶﾅのタイトル", "カタカナ", true),
            ("中文视频标题", "视频", true),
            ("한국어 동영상 제목", "동영상", true),
            ("How to Use ChatGPT for Work", "python", false),
            ("How to Use ChatGPT for Work", "", true),
            ("How to Use ChatGPT for Work", "   ", true),
        ]
        for (title, query, expected) in cases {
            let video = vid("x", title: title, epoch: 0)
            XCTAssertEqual(video.titleMatches(query), expected, "「\(title)」に「\(query)」")
        }
    }

    func testDescriptionIsNotSearched() {
        XCTAssertFalse(vid("x", title: "Cooking basics", epoch: 0).titleMatches("chatgpt"))
    }

    // ---- 一覧への適用 ----

    private var sample: [VideoItem] {
        [
            vid("a", title: "ChatGPT 入門", epoch: 100),
            vid("b", title: "料理の基本", epoch: 200),
            vid("c", title: "chatgpt の使い方", epoch: 300),
        ]
    }

    func testSearchKeepsOldestFirst() {
        let vm = makeVM(sample)
        vm.openSearch()
        vm.searchQuery = "ChatGPT"
        XCTAssertEqual(vm.visibleVideos(isWatched: { _ in false }).map(\.id), ["a", "c"])
        XCTAssertTrue(vm.isFilteringBySearch)
    }

    func testSearchKeepsNewestFirst() {
        let vm = makeVM(sample)
        vm.sortAscending = false
        vm.openSearch()
        vm.searchQuery = "chatgpt"
        XCTAssertEqual(vm.visibleVideos(isWatched: { _ in false }).map(\.id), ["c", "a"])
    }

    func testSearchCombinesWithWatchFilter() {
        let vm = makeVM(sample)
        vm.watchFilter = .unwatched
        vm.openSearch()
        vm.searchQuery = "chatgpt"
        XCTAssertEqual(vm.visibleVideos(isWatched: { $0 == "a" }).map(\.id), ["c"])
    }

    func testNoResultsIsEmpty() {
        let vm = makeVM(sample)
        vm.openSearch()
        vm.searchQuery = "python"
        XCTAssertTrue(vm.visibleVideos(isWatched: { _ in false }).isEmpty)
        XCTAssertTrue(vm.isFilteringBySearch, "0件表示を出す条件")
    }

    func testClearingQueryShowsAll() {
        let vm = makeVM(sample)
        vm.openSearch()
        vm.searchQuery = "chatgpt"
        vm.searchQuery = ""
        XCTAssertEqual(vm.visibleVideos(isWatched: { _ in false }).map(\.id), ["a", "b", "c"])
        XCTAssertFalse(vm.isFilteringBySearch)
    }

    func testClosingSearchShowsAllAndClearsQuery() {
        let vm = makeVM(sample)
        vm.openSearch()
        vm.searchQuery = "chatgpt"
        vm.closeSearch()
        XCTAssertFalse(vm.isSearching)
        XCTAssertEqual(vm.searchQuery, "")
        XCTAssertEqual(vm.visibleVideos(isWatched: { _ in false }).map(\.id), ["a", "b", "c"])
    }

    /// 別チャンネルは別の画面・別の ViewModel（ChannelInputView で .id(channel.id)）なので、検索は持ち越さない。
    func testAnotherChannelStartsWithoutSearch() {
        let first = makeVM(sample, channelId: "A")
        first.openSearch()
        first.searchQuery = "chatgpt"
        let second = makeVM(sample, channelId: "B")
        XCTAssertFalse(second.isSearching)
        XCTAssertEqual(second.searchQuery, "")
        XCTAssertEqual(second.visibleVideos(isWatched: { _ in false }).count, 3)
    }

    /// 検索しても「次に見る」（チャンネル全体の古い順）は変わらない。
    func testNextUnwatchedIgnoresSearch() {
        let vm = makeVM(sample)
        vm.openSearch()
        vm.searchQuery = "料理"
        XCTAssertEqual(vm.nextUnwatched(isWatched: { _ in false }, isSkipped: { _ in false })?.id, "a")
    }
}
