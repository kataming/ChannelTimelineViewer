import Foundation

/// 動画一覧の1ページ分。
struct VideoPage {
    let items: [VideoItem]
    let nextPageToken: String?
}

/// 「人気動画から選ぶ」に並べる動画（選ぶとその投稿チャンネルを開く）。
struct PopularVideo: Identifiable, Equatable {
    let videoId: String
    let title: String
    let channelId: String
    let channelTitle: String
    let thumbnailURL: URL?

    var id: String { videoId }
}

/// YouTube Data API v3 クライアント。
/// スクレイピングは行わず、公式の Data API のみを使用する。
final class YouTubeAPIClient {

    private let session: URLSession
    private let baseURL = "https://www.googleapis.com/youtube/v3"
    /// 人気動画の一覧を国ごとに持っている当方のサーバー（site/functions/api/popular.js）。
    /// Android（`YouTubeApiClient.fetchPopularVideos`）と同じものを使う。
    private let popularURL = "https://channeltimeline.jewelrysunflower.com/api/popular"
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

    /// 「人気動画から選ぶ」に並べる、その国でいま人気の動画。
    ///
    /// まず当方のサーバー（`popularURL`・Cloudflare）から読む。サーバーが国ごとに1時間だけ持っているので、
    /// 利用者が何人いても・何度入れ直しても、アプリの quota は使わない（2026-10-05・Android と同じ判断）。
    /// 送るのは2文字の国コードだけ。サーバーが使えないときだけ、直接 YouTube に問い合わせる（quota 1）。
    func fetchPopularVideos(regionCode: String?) async throws -> [PopularVideo] {
        let region = Self.normalizedRegion(regionCode)
        if var comps = URLComponents(string: popularURL) {
            if let region { comps.queryItems = [URLQueryItem(name: "region", value: region)] }
            if let url = comps.url,
               let result = try? await session.data(from: url),
               let http = result.1 as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let videos = try? Self.popularVideos(fromServerJSON: result.0), !videos.isEmpty {
                return videos
            }
        }
        return try await fetchPopularVideosDirect(region: region)
    }

    /// YouTube に直接問い合わせる（chart=mostPopular・quota 1）。サーバーが使えないときの予備。
    /// 国に対応していない（400 など）ときは国を指定せずに取り直す。
    private func fetchPopularVideosDirect(region: String?) async throws -> [PopularVideo] {
        let base: [(String, String)] = [("part", "snippet"), ("chart", "mostPopular"), ("maxResults", "50")]
        let data: Data
        if let region {
            do {
                data = try await getData("videos", query: base + [("regionCode", region)])
            } catch {
                data = try await getData("videos", query: base)
            }
        } else {
            data = try await getData("videos", query: base)
        }
        return try Self.popularVideos(fromChartJSON: data)
    }

    /// 国コードを2文字の大文字にそろえる（それ以外は nil＝国を指定しない）。
    static func normalizedRegion(_ code: String?) -> String? {
        guard let upper = code?.uppercased(), upper.count == 2,
              upper.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return upper
    }

    /// 当方のサーバー（/api/popular）の答え `{ region, items: [...] }` を読む（テスト可能）。
    /// 同じチャンネルは最初の1本だけにする。
    static func popularVideos(fromServerJSON data: Data) throws -> [PopularVideo] {
        let response: PopularServerResponse
        do {
            response = try JSONDecoder().decode(PopularServerResponse.self, from: data)
        } catch {
            throw YouTubeAPIError.decodingError
        }
        let videos = (response.items ?? []).compactMap { item -> PopularVideo? in
            guard let videoId = item.videoId, !videoId.isEmpty,
                  let channelId = item.channelId, !channelId.isEmpty else { return nil }
            return PopularVideo(
                videoId: videoId,
                title: item.title?.nonEmpty ?? String(localized: "video.untitled"),
                channelId: channelId,
                channelTitle: item.channelTitle?.nonEmpty ?? String(localized: "channel.untitled"),
                thumbnailURL: item.thumbnailUrl.flatMap(URL.init(string:)))
        }
        return distinctByChannel(videos)
    }

    /// chart=mostPopular の videos.list の答えを読む（テスト可能）。同じチャンネルは最初の1本だけ。
    static func popularVideos(fromChartJSON data: Data) throws -> [PopularVideo] {
        let response: VideoListResponse
        do {
            response = try JSONDecoder().decode(VideoListResponse.self, from: data)
        } catch {
            throw YouTubeAPIError.decodingError
        }
        let videos = response.items.compactMap { item -> PopularVideo? in
            guard let videoId = item.id, !videoId.isEmpty,
                  let channelId = item.snippet?.channelId, !channelId.isEmpty else { return nil }
            return PopularVideo(
                videoId: videoId,
                title: item.snippet?.title?.nonEmpty ?? String(localized: "video.untitled"),
                channelId: channelId,
                channelTitle: item.snippet?.channelTitle?.nonEmpty ?? String(localized: "channel.untitled"),
                thumbnailURL: item.snippet?.thumbnails?.mediumURL)
        }
        return distinctByChannel(videos)
    }

    private static func distinctByChannel(_ videos: [PopularVideo]) -> [PopularVideo] {
        var seen = Set<String>()
        return videos.filter { seen.insert($0.channelId).inserted }
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

    /// 視聴回数（statistics.viewCount）を 50 本ずつ取る（1回 = quota 1）。
    /// 視聴回数を非公開にしている動画は結果に含まれない。
    func fetchViewCounts(videoIds: [String]) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        var start = 0
        while start < videoIds.count {
            let chunk = videoIds[start..<min(start + 50, videoIds.count)]
            let response: VideoStatisticsResponse = try await get("videos", query: [
                ("part", "statistics"),
                ("id", chunk.joined(separator: ",")),
                ("maxResults", "50"),
            ])
            for item in response.items {
                if let raw = item.statistics?.viewCount, let value = Int(raw) {
                    counts[item.id] = value
                }
            }
            start += 50
        }
        return counts
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
                title: item.snippet?.title ?? String(localized: "video.untitled"),
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
            title: item.snippet?.title ?? String(localized: "channel.untitled"),
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
        let thumbnails: Thumbnails?
    }
}

/// 当方のサーバー（/api/popular）の答え。
private struct PopularServerResponse: Decodable {
    let items: [Item]?
    struct Item: Decodable {
        let videoId: String?
        let title: String?
        let channelId: String?
        let channelTitle: String?
        let thumbnailUrl: String?
    }
}

private extension String {
    /// 空文字なら nil。
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// videos.list（statistics）用。
private struct VideoStatisticsResponse: Decodable {
    let items: [Item]
    struct Item: Decodable {
        let id: String
        let statistics: Statistics?
    }
    struct Statistics: Decodable {
        let viewCount: String?
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

    /// 一覧の小さな表示に向くサムネイルURL（medium 優先）。
    var mediumURL: URL? {
        let candidate = medium?.url ?? high?.url ?? `default`?.url
        return candidate.flatMap(URL.init(string:))
    }

    /// 利用可能な中で品質の高いサムネイルURL。
    var bestURL: URL? {
        let candidate = maxres?.url ?? standard?.url ?? high?.url ?? medium?.url ?? `default`?.url
        return candidate.flatMap(URL.init(string:))
    }
}
