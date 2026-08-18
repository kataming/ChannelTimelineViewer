import Foundation

/// YouTube API 関連のエラー。ユーザー向けに日本語メッセージを返す。
enum YouTubeAPIError: LocalizedError, Equatable {
    case invalidURL
    case invalidChannelURL
    case invalidVideoURL
    case videoNotFound
    case channelNotFound
    case uploadsPlaylistNotFound
    case apiKeyMissing
    case quotaExceeded
    case networkError
    case decodingError
    case unknown

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "error.invalidURL")
        case .invalidChannelURL:
            return String(localized: "error.invalidChannelURL")
        case .invalidVideoURL:
            return String(localized: "error.invalidVideoURL")
        case .videoNotFound:
            return String(localized: "error.videoNotFound")
        case .channelNotFound:
            return String(localized: "error.channelNotFound")
        case .uploadsPlaylistNotFound:
            return String(localized: "error.uploadsPlaylistNotFound")
        case .apiKeyMissing:
            return String(localized: "error.apiKeyMissing")
        case .quotaExceeded:
            return String(localized: "error.quotaExceeded")
        case .networkError:
            return String(localized: "error.network")
        case .decodingError:
            return String(localized: "error.decoding")
        case .unknown:
            return String(localized: "error.unknown")
        }
    }
}
