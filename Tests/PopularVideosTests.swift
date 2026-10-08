import XCTest
@testable import ChannelTimelineViewer

/// 「人気動画から選ぶ」の一覧の読み取り（当方のサーバー /api/popular と、予備の chart=mostPopular）。
final class PopularVideosTests: XCTestCase {

    func testParsesServerResponseAndKeepsOneVideoPerChannel() throws {
        let json = """
        { "region": "JP", "items": [
          { "videoId": "aaaaaaaaaaa", "title": "First", "channelId": "UC1", "channelTitle": "One",
            "thumbnailUrl": "https://i.ytimg.com/vi/aaaaaaaaaaa/mqdefault.jpg" },
          { "videoId": "bbbbbbbbbbb", "title": "Second from same channel", "channelId": "UC1", "channelTitle": "One",
            "thumbnailUrl": null },
          { "videoId": "ccccccccccc", "title": "Third", "channelId": "UC2", "channelTitle": "Two" },
          { "videoId": "ddddddddddd", "title": "No channel" }
        ] }
        """
        let videos = try YouTubeAPIClient.popularVideos(fromServerJSON: Data(json.utf8))

        XCTAssertEqual(videos.map(\.videoId), ["aaaaaaaaaaa", "ccccccccccc"])
        XCTAssertEqual(videos.first?.channelTitle, "One")
        XCTAssertEqual(videos.first?.thumbnailURL?.absoluteString,
                       "https://i.ytimg.com/vi/aaaaaaaaaaa/mqdefault.jpg")
        XCTAssertNil(videos.last?.thumbnailURL)
    }

    func testServerResponseWithoutItemsIsEmpty() throws {
        XCTAssertEqual(try YouTubeAPIClient.popularVideos(fromServerJSON: Data(#"{"region":"US"}"#.utf8)), [])
    }

    func testBrokenServerResponseThrows() {
        XCTAssertThrowsError(try YouTubeAPIClient.popularVideos(fromServerJSON: Data("<html>".utf8)))
    }

    func testParsesChartResponse() throws {
        let json = """
        { "items": [
          { "id": "aaaaaaaaaaa", "snippet": { "title": "First", "channelId": "UC1", "channelTitle": "One",
            "thumbnails": { "default": { "url": "https://example.com/d.jpg" },
                            "medium": { "url": "https://example.com/m.jpg" } } } },
          { "id": "bbbbbbbbbbb", "snippet": { "title": "Same channel", "channelId": "UC1" } },
          { "id": "ccccccccccc", "snippet": { "title": "Third", "channelId": "UC2", "channelTitle": "Two" } }
        ] }
        """
        let videos = try YouTubeAPIClient.popularVideos(fromChartJSON: Data(json.utf8))

        XCTAssertEqual(videos.map(\.channelId), ["UC1", "UC2"])
        XCTAssertEqual(videos.first?.thumbnailURL?.absoluteString, "https://example.com/m.jpg",
                       "一覧の小さな表示には medium を使う")
    }

    func testNormalizesRegionCode() {
        XCTAssertEqual(YouTubeAPIClient.normalizedRegion("jp"), "JP")
        XCTAssertEqual(YouTubeAPIClient.normalizedRegion("US"), "US")
        XCTAssertNil(YouTubeAPIClient.normalizedRegion(nil))
        XCTAssertNil(YouTubeAPIClient.normalizedRegion("419"), "数字の地域コードは送らない")
        XCTAssertNil(YouTubeAPIClient.normalizedRegion("JPN"))
    }

    func testPickedVideoOpensItsChannelURL() throws {
        let url = ChannelInputViewModel.channelURLString(forChannelId: "UC_x5XG1OV2P6uZZ5FSM9Ttw")
        XCTAssertEqual(url, "https://www.youtube.com/channel/UC_x5XG1OV2P6uZZ5FSM9Ttw")
        // 既存の解決処理でそのまま channelId として読める。
        XCTAssertEqual(try ChannelResolver.parse(url), .channelId("UC_x5XG1OV2P6uZZ5FSM9Ttw"))
    }

    /// 人気動画を選んだら、その動画の URL で開く（動画URL → すぐ再生＋投稿チャンネルを特定）。
    func testPickedVideoOpensItsVideoURL() throws {
        let url = ChannelInputViewModel.videoURLString(forVideoId: "dQw4w9WgXcQ")
        XCTAssertEqual(try ChannelResolver.parse(url), .video("dQw4w9WgXcQ"))
    }

    /// 動画URLから来たときにすぐ再生する1本（videos.list の snippet・statistics）。
    func testReadsVideoForQuickStart() throws {
        let json = """
        {"items":[{"id":"abcdefghijk","snippet":{"title":"t","description":"d",
          "publishedAt":"2024-01-02T03:04:05Z","channelId":"UC1"},"statistics":{"viewCount":"1234"}}]}
        """
        let video = try XCTUnwrap(YouTubeAPIClient.video(fromVideosListJSON: Data(json.utf8)))
        XCTAssertEqual(video.id, "abcdefghijk")
        XCTAssertEqual(video.channelId, "UC1")
        XCTAssertEqual(video.viewCount, 1234)
        XCTAssertEqual(video.publishedAt.timeIntervalSince1970, 1_704_164_645)
        XCTAssertNil(YouTubeAPIClient.video(fromVideosListJSON: Data(#"{"items":[]}"#.utf8)))
    }
}
