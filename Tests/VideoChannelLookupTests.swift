import XCTest
@testable import ChannelTimelineViewer

/// 動画URL（videoId）から channelId を取り出す処理のテスト。
/// ネットワークに依存しないよう、videos.list のレスポンス JSON を解釈する部分を切り出してある。
final class VideoChannelLookupTests: XCTestCase {

    private func json(_ string: String) -> Data {
        Data(string.utf8)
    }

    func testExtractsChannelIdFromVideosListResponse() throws {
        let data = json("""
        {
          "kind": "youtube#videoListResponse",
          "items": [
            {
              "id": "dQw4w9WgXcQ",
              "snippet": {
                "channelId": "UCuAXFkgsw1L7xaCfnd5JJOw",
                "channelTitle": "Some Channel",
                "title": "Some Video"
              }
            }
          ]
        }
        """)
        XCTAssertEqual(try YouTubeAPIClient.channelId(fromVideosListJSON: data),
                       "UCuAXFkgsw1L7xaCfnd5JJOw")
    }

    func testThrowsWhenVideoNotFound() {
        // 非公開・削除済み・存在しない videoId では items が空で返る
        let data = json(#"{"kind":"youtube#videoListResponse","items":[]}"#)
        XCTAssertThrowsError(try YouTubeAPIClient.channelId(fromVideosListJSON: data)) { error in
            XCTAssertEqual(error as? YouTubeAPIError, .videoNotFound)
        }
    }

    func testThrowsWhenChannelIdMissing() {
        let data = json(#"{"items":[{"id":"dQw4w9WgXcQ","snippet":{"title":"no channelId"}}]}"#)
        XCTAssertThrowsError(try YouTubeAPIClient.channelId(fromVideosListJSON: data)) { error in
            XCTAssertEqual(error as? YouTubeAPIError, .videoNotFound)
        }
    }

    func testThrowsOnBrokenJSON() {
        XCTAssertThrowsError(try YouTubeAPIClient.channelId(fromVideosListJSON: json("not json"))) { error in
            XCTAssertEqual(error as? YouTubeAPIError, .decodingError)
        }
    }

    /// 不正な videoId ではネットワークに出る前に弾く（APIクォータを無駄にしない）。
    func testRejectsInvalidVideoIdBeforeNetworkCall() async {
        let client = YouTubeAPIClient()
        do {
            _ = try await client.fetchChannelId(forVideoId: "not-a-video-id")
            XCTFail("不正な videoId は弾かれるべき")
        } catch {
            XCTAssertEqual(error as? YouTubeAPIError, .invalidVideoURL)
        }
    }

    /// 共有された動画URL → videoId → （API 呼び出し）という流れの入口が繋がっていること。
    func testSharedVideoURLResolvesToVideoIdentifier() throws {
        let shared = "面白い動画\nhttps://youtu.be/dQw4w9WgXcQ?si=AbCdEfGhIjK"
        let link = try XCTUnwrap(SharedLinkParser.extractYouTubeURLString(from: shared))
        XCTAssertEqual(try ChannelResolver.parse(link), .video("dQw4w9WgXcQ"))
    }
}
