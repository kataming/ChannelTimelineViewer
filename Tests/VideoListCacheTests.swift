import XCTest
@testable import ChannelTimelineViewer

/// 動画一覧のキャッシュ（2回目以降は全件取り直さない仕組み）のテスト。
final class VideoListCacheTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoListCacheTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCache() -> VideoListCache {
        VideoListCache(directory: directory)
    }

    private func makeVideos(_ count: Int, prefix: String = "video") -> [VideoItem] {
        (0..<count).map { i in
            VideoItem(id: "\(prefix)\(i)",
                      title: "第\(i + 1)回",
                      description: "説明",
                      publishedAt: Date(timeIntervalSince1970: TimeInterval(i) * 86_400),
                      thumbnailURL: nil,
                      channelId: "UCtest")
        }
    }

    // MARK: - 視聴回数（1.4.1）

    func testOldCacheWithoutViewCountStillLoads() throws {
        // 1.4.1 より前の保存（viewCount / statsUpdatedAt が無い）
        let json = """
        {"videos":[{"id":"v1","title":"t","description":"","publishedAt":0,"channelId":"UCtest"}],
         "updatedAt":0,"uploadsPlaylistId":"UUtest"}
        """
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: directory.appendingPathComponent("UCtest.json"))
        let entry = try XCTUnwrap(makeCache().entry(for: "UCtest"))
        XCTAssertEqual(entry.videos.map(\.id), ["v1"])
        XCTAssertNil(entry.videos[0].viewCount)
        XCTAssertNil(entry.statsUpdatedAt, "取り直しが必要と判定される")
    }

    func testSavesViewCountsAndRefreshDate() throws {
        var videos = makeVideos(2)
        videos[0].viewCount = 123_456
        let refreshed = Date(timeIntervalSince1970: 1_000)
        makeCache().save(videos, for: "UCtest", uploadsPlaylistId: "UUtest", statsUpdatedAt: refreshed)
        let entry = try XCTUnwrap(makeCache().entry(for: "UCtest"))
        XCTAssertEqual(entry.videos.map(\.viewCount), [123_456, nil])
        XCTAssertEqual(entry.statsUpdatedAt, refreshed)
    }

    func testSavesAndLoadsVideos() {
        let cache = makeCache()
        let videos = makeVideos(3)

        cache.save(videos, for: "UCtest", uploadsPlaylistId: "UUtest")

        XCTAssertEqual(cache.videos(for: "UCtest")?.map(\.id), videos.map(\.id))
        XCTAssertEqual(cache.entry(for: "UCtest")?.uploadsPlaylistId, "UUtest")
    }

    func testReturnsNilForUnknownChannel() {
        XCTAssertNil(makeCache().videos(for: "UCnothing"))
    }

    func testKeepsChannelsSeparate() {
        let cache = makeCache()
        cache.save(makeVideos(2, prefix: "a"), for: "UCaaa", uploadsPlaylistId: nil)
        cache.save(makeVideos(3, prefix: "b"), for: "UCbbb", uploadsPlaylistId: nil)

        XCTAssertEqual(cache.videos(for: "UCaaa")?.count, 2)
        XCTAssertEqual(cache.videos(for: "UCbbb")?.count, 3)
    }

    func testRemove() {
        let cache = makeCache()
        cache.save(makeVideos(2), for: "UCtest", uploadsPlaylistId: nil)
        cache.remove("UCtest")
        XCTAssertNil(cache.videos(for: "UCtest"))
    }

    func testDoesNotSaveEmptyList() {
        let cache = makeCache()
        cache.save([], for: "UCtest", uploadsPlaylistId: nil)
        XCTAssertNil(cache.videos(for: "UCtest"))
    }

    /// ファイル名に使えない文字が入っていても壊れないこと。
    func testHandlesUnsafeChannelId() {
        let cache = makeCache()
        cache.save(makeVideos(1), for: "../../etc/passwd", uploadsPlaylistId: nil)
        // 記号を落とした名前で保存され、同じキーで読み出せる
        XCTAssertEqual(cache.videos(for: "../../etc/passwd")?.count, 1)
    }

    func testSurvivesNewCacheInstance() {
        makeCache().save(makeVideos(4), for: "UCtest", uploadsPlaylistId: nil)
        XCTAssertEqual(makeCache().videos(for: "UCtest")?.count, 4)
    }

    // MARK: - 重複の除去（保存済み＋新着）

    func testUniquedByIdKeepsFirstOccurrence() {
        let videos = makeVideos(3)
        let merged = (videos + [videos[1]]).uniquedById()
        XCTAssertEqual(merged.map(\.id), ["video0", "video1", "video2"])
    }
}
