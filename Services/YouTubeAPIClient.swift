import Foundation

/// 動画一覧の1ページ分。
struct VideoPage {
    let items: [VideoItem]
    let nextPageToken: String?
}

/// YouTube Data API v3 クライアント。
/// スクレイピングは行わず、公式の Data API のみを使用する。
final class YouTubeAPIClient {

    private let session: URLSession
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    /// 暴走防止のための最大ページ数（50件/ページ × 100 = 5000本）。
    private let maxPages = 100

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func apiKey() throws -> String {
        guard let key = ConfigLoader.youtubeAPIKey() else {
            throw YouTubeAPIError.apiKeyMissing
        }
        return key
    }

    // MARK: - Public API

    /// 入力URL（または handle / channelId）からチャンネルを解決する。
    func resolveChannel(from inputURL: String) async throws -> Channel {
        let identifier = try ChannelResolver.parse(inputURL)
        switch identifier {
        case .channelId(let id):
            return try await fetchChannel(query: [("id", id)])
        case .handle(let handle):
            return try await fetchChannel(query: [("forHandle", "@\(handle)")])
        case .username(let name):
            return try await fetchChannel(query: [("forUsername", name)])
        case .customName(let name):
            let channelId = try await searchChannelId(byName: name)
            return try await fetchChannel(query: [("id", channelId)])
        case .video(let videoId):
            // 共有された動画URL → videos.list で投稿チャンネルを特定してから解決する（quota 1）。
            let channelId = try await fetchChannelId(forVideoId: videoId)
            return try await fetchChannel(query: [("id", channelId)])
        }
    }

    /// videoId からその動画を投稿したチャンネルの channelId を取得する（videos.list / quota 1）。
    func fetchChannelId(forVideoId videoId: String) async throws -> String {
        guard ChannelResolver.isVideoId(videoId) else {
            throw YouTubeAPIError.invalidVideoURL
        }
        let data = try await getData("videos", query: [("part", "snippet"), ("id", videoId)])
        return try Self.channelId(fromVideosListJSON: data)
    }

    /// videos.list のレスポンス JSON から channelId を取り出す（ネットワーク非依存＝テスト可能）。
    static func channelId(fromVideosListJSON data: Data) throws -> String {
        let response: VideoListResponse
        do {
            response = try JSONDecoder().decode(VideoListResponse.self, from: data)
        } catch {
            throw YouTubeAPIError.decodingError
        }
        guard let channelId = response.items.first?.snippet?.channelId,
              !channelId.isEmpty else {
            throw YouTubeAPIError.videoNotFound
        }
        return channelId
    }

    /// channelId から uploads プレイリストIDを取得する。
    func fetchUploadsPlaylistId(channelId: String) async throws -> String {
        let channel = try await fetchChannel(query: [("id", channelId)])
        guard let uploads = channel.uploadsPlaylistId else {
            throw YouTubeAPIError.uploadsPlaylistNotFound
        }
        return uploads
    }

    /// uploads プレイリストから全動画を取得し、古い順（publishedAt 昇順）で返す。
    /// uploads プレイリストは新しい順で返るため、古い順表示には全ページの取得が必要。
    func fetchVideos(playlistId: String) async throws -> [VideoItem] {
        var all: [VideoItem] = []
        var token: String? = nil
        var page = 0
        repeat {
            let result = try await fetchVideosPage(playlistId: playlistId, pageToken: token)
            all.append(contentsOf: result.items)
            token = result.nextPageToken
            page += 1
        } while token != nil && page < maxPages

        return all.sortedByPublishedDate(ascending: true)
    }

    /// 既に持っている動画に当たるまで、新しい順にページを取得して**新着だけ**返す。
    ///
    /// uploads プレイリストは新しい順に返るため、既知の動画に当たった時点で
    /// それ以降はすべて既知とみなせる。本数の多いチャンネルを毎回全件取り直さずに済む。
    ///
    /// - Returns: 新着（新しい順）と、既知の動画に到達したかどうか。
    ///   到達しなかった場合は差分が大きい（久しぶりに開いた等）ので、呼び出し側で全件取得に切り替える。
    func fetchNewVideos(playlistId: String,
                        knownVideoIds: Set<String>,
                        maxPages: Int = 5) async throws -> (videos: [VideoItem], reachedKnown: Bool) {
        var newItems: [VideoItem] = []
        var token: String?
        var page = 0
        var reachedKnown = false

        repeat {
            let result = try await fetchVideosPage(playlistId: playlistId, pageToken: token)
            for item in result.items {
                if knownVideoIds.contains(item.id) {
                    reachedKnown = true
                    break
                }
                newItems.append(item)
            }
            if reachedKnown { break }
            token = result.nextPageToken
            page += 1
        } while token != nil && page < maxPages

        // 最後まで見ても既知に当たらなかった＝そもそも全部が新しい（＝全件取得すべき）。
        return (newItems, reachedKnown || token == nil)
    }

    /// uploads プレイリストの1ページ分を取得する。
    func fetchVideosPage(playlistId: String, pageToken: String?) async throws -> VideoPage {
        var query: [(String, String)] = [
            ("part", "snippet,contentDetails"),
            ("playlistId", playlistId),
            ("maxResults", "50"),
        ]
        if let pageToken { query.append(("pageToken", pageToken)) }

        let response: PlaylistItemListResponse = try await get("playlistItems", query: query)
        let items: [VideoItem] = response.items.compactMap { item in
            guard let videoId = item.contentDetails?.videoId ?? item.snippet?.resourceId?.videoId else {
                return nil
            }
            let publishedString = item.contentDetails?.videoPublishedAt ?? item.snippet?.publishedAt
            let published = publishedString.flatMap(ISO8601.date(from:)) ?? Date.distantPast
            return VideoItem(
                id: videoId,
                title: item.snippet?.title ?? "(タイトルなし)",
                description: item.snippet?.description ?? "",
                publishedAt: published,
                thumbnailURL: item.snippet?.thumbnails?.bestURL,
                channelId: item.snippet?.videoOwnerChannelId ?? item.snippet?.channelId ?? ""
            )
        }
        return VideoPage(items: items, nextPageToken: response.nextPageToken)
    }

    // MARK: - Private helpers

    private func fetchChannel(query extra: [(String, String)]) async throws -> Channel {
        var query: [(String, String)] = [("part", "snippet,contentDetails")]
        query.append(contentsOf: extra)
        let response: ChannelListResponse = try await get("channels", query: query)
        guard let item = response.items.first else {
            throw YouTubeAPIError.channelNotFound
        }
        return Channel(
            id: item.id,
            title: item.snippet?.title ?? "(チャンネル名なし)",
            thumbnailURL: item.snippet?.thumbnails?.bestURL,
            uploadsPlaylistId: item.contentDetails?.relatedPlaylists?.uploads
        )
    }

    /// カスタムURL名から search.list で channelId を引く（quota 100）。
    private func searchChannelId(byName name: String) async throws -> String {
        let query: [(String, String)] = [
            ("part", "snippet"),
            ("type", "channel"),
            ("q", name),
            ("maxResults", "1"),
        ]
        let response: SearchListResponse = try await get("search", query: query)
        guard let id = response.items.first?.id?.channelId else {
            throw YouTubeAPIError.channelNotFound
        }
        return id
    }

    /// 共通のGETリクエスト（デコードまで行う）。
    private func get<T: Decodable>(_ path: String, query: [(String, String)]) async throws -> T {
        let data = try await getData(path, query: query)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw YouTubeAPIError.decodingError
        }
    }

    /// 共通のGETリクエスト（生データ）。エラーを YouTubeAPIError にマップする。
    private func getData(_ path: String, query: [(String, String)]) async throws -> Data {
        let key = try apiKey()
        var comps = URLComponents(string: "\(baseURL)/\(path)")!
        comps.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
            + [URLQueryItem(name: "key", value: key)]
        guard let url = comps.url else { throw YouTubeAPIError.invalidURL }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw YouTubeAPIError.networkError
        }

        guard let http = response as? HTTPURLResponse else {
            throw YouTubeAPIError.unknown
        }
        switch http.statusCode {
        case 200...299:
            break
        case 403:
            // quota 超過かどうかを本文から判定。
            if let body = String(data: data, encoding: .utf8),
               body.contains("quotaExceeded") || body.contains("dailyLimitExceeded") {
                throw YouTubeAPIError.quotaExceeded
            }
            throw YouTubeAPIError.unknown
        case 404:
            throw YouTubeAPIError.channelNotFound
        default:
            throw YouTubeAPIError.networkError
        }

        return data
    }
}

// MARK: - ISO8601 パース（fractional seconds 有無の両対応）

enum ISO8601 {
    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(from string: String) -> Date? {
        withFraction.date(from: string) ?? plain.date(from: string)
    }
}

// MARK: - API レスポンス（Decodable）

private struct ChannelListResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let snippet: Snippet?
        let contentDetails: ContentDetails?
    }
    struct Snippet: Decodable {
        let title: String?
        let thumbnails: Thumbnails?
    }
    struct ContentDetails: Decodable {
        let relatedPlaylists: RelatedPlaylists?
    }
    struct RelatedPlaylists: Decodable {
        let uploads: String?
    }
}

/// videos.list（共有された動画URL → 投稿チャンネルの特定）用。
private struct VideoListResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String?
        let snippet: Snippet?
    }
    struct Snippet: Decodable {
        let channelId: String?
        let channelTitle: String?
        let title: String?
    }
}

private struct SearchListResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: ID?
    }
    struct ID: Decodable {
        let channelId: String?
    }
}

private struct PlaylistItemListResponse: Decodable {
    let items: [Item]
    let nextPageToken: String?
    struct Item: Decodable {
        let snippet: Snippet?
        let contentDetails: ContentDetails?
    }
    struct Snippet: Decodable {
        let title: String?
        let description: String?
        let publishedAt: String?
        let channelId: String?
        let videoOwnerChannelId: String?
        let thumbnails: Thumbnails?
        let resourceId: ResourceId?
    }
    struct ResourceId: Decodable {
        let videoId: String?
    }
    struct ContentDetails: Decodable {
        let videoId: String?
        let videoPublishedAt: String?
    }
}

/// 各種 thumbnails オブジェクト（共通）。
private struct Thumbnails: Decodable {
    let `default`: Thumb?
    let medium: Thumb?
    let high: Thumb?
    let standard: Thumb?
    let maxres: Thumb?

    struct Thumb: Decodable {
        let url: String?
    }

    /// 利用可能な中で品質の高いサムネイルURL。
    var bestURL: URL? {
        let candidate = maxres?.url ?? standard?.url ?? high?.url ?? medium?.url ?? `default`?.url
        return candidate.flatMap(URL.init(string:))
    }
}
