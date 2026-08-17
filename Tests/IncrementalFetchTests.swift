import XCTest
@testable import ChannelTimelineViewer

/// 「新着だけ取りに行く」処理のテスト（ネットワークは差し替える）。
final class IncrementalFetchTests: XCTestCase {

    /// リクエストに対して決まった JSON を返すスタブ。
    final class StubURLProtocol: URLProtocol {
        /// 呼ばれた順に返す JSON。
        static var pages: [String] = []
        static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            let index = Self.requestCount
            Self.requestCount += 1
            let body = index < Self.pages.count ? Self.pages[index] : "{\"items\":[]}"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeClient() -> YouTubeAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return YouTubeAPIClient(session: URLSession(configuration: config))
    }

    /// items を新しい順に並べた playlistItems のレスポンス。
    private func page(_ ids: [String], nextPageToken: String? = nil) -> String {
        let items = ids.enumerated().map { offset, id in
            """
            {"contentDetails":{"videoId":"\(id)","videoPublishedAt":"2026-0\(min(offset + 1, 9))-01T00:00:00Z"},
             "snippet":{"title":"\(id) のタイトル","description":"","publishedAt":"2026-01-01T00:00:00Z",
             "channelId":"UCtest","thumbnails":{}}}
            """
        }.joined(separator: ",")
        let token = nextPageToken.map { "\"nextPageToken\":\"\($0)\"," } ?? ""
        return "{\(token)\"items\":[\(items)]}"
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.pages = []
        StubURLProtocol.requestCount = 0
        // 実キーが無い環境でもクライアントを動かせるようにする（送信先はスタブ）。
        setenv(ConfigLoader.apiKeyName, "TEST_KEY", 1)
    }

    override func tearDown() {
        unsetenv(ConfigLoader.apiKeyName)
        super.tearDown()
    }

    /// 既知の動画に当たった時点で止まり、それ以降のページを取りに行かないこと。
    func testStopsAtFirstKnownVideo() async throws {
        StubURLProtocol.pages = [
            page(["new2", "new1", "known3"], nextPageToken: "PAGE2"),
            page(["known2", "known1"]),
        ]
        let client = makeClient()

        let result = try await client.fetchNewVideos(
            playlistId: "UUtest",
            knownVideoIds: ["known1", "known2", "known3"]
        )

        XCTAssertEqual(result.videos.map(\.id), ["new2", "new1"], "新着だけ返す")
        XCTAssertTrue(result.reachedKnown)
        XCTAssertEqual(StubURLProtocol.requestCount, 1, "2ページ目は取りに行かない（通信を節約）")
    }

    /// 新着が無ければ1ページだけ取って何も返さないこと。
    func testReturnsNothingWhenUpToDate() async throws {
        StubURLProtocol.pages = [page(["known2", "known1"])]
        let client = makeClient()

        let result = try await client.fetchNewVideos(
            playlistId: "UUtest",
            knownVideoIds: ["known1", "known2"]
        )

        XCTAssertTrue(result.videos.isEmpty)
        XCTAssertTrue(result.reachedKnown)
        XCTAssertEqual(StubURLProtocol.requestCount, 1)
    }

    /// 上限ページまで見ても既知に当たらない場合は、呼び出し側が全件取得に切り替えられるよう false を返す。
    func testReportsWhenTooManyNewVideos() async throws {
        StubURLProtocol.pages = [
            page(["a"], nextPageToken: "P2"),
            page(["b"], nextPageToken: "P3"),
        ]
        let client = makeClient()

        let result = try await client.fetchNewVideos(
            playlistId: "UUtest",
            knownVideoIds: ["old"],
            maxPages: 2
        )

        XCTAssertFalse(result.reachedKnown, "全件取り直しが必要と分かること")
        XCTAssertEqual(result.videos.map(\.id), ["a", "b"])
    }

    /// 最後のページまで到達した場合は、既知に当たらなくても完了扱いにすること。
    func testTreatsEndOfPlaylistAsComplete() async throws {
        StubURLProtocol.pages = [page(["a", "b"])]   // nextPageToken なし
        let client = makeClient()

        let result = try await client.fetchNewVideos(playlistId: "UUtest", knownVideoIds: [])

        XCTAssertTrue(result.reachedKnown, "プレイリストの末尾まで取れているので取り直し不要")
        XCTAssertEqual(result.videos.count, 2)
    }
}
