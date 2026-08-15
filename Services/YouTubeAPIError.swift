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
            return "URLが正しくありません"
        case .invalidChannelURL:
            return "YouTubeチャンネルのURLとして認識できませんでした"
        case .invalidVideoURL:
            return "YouTube動画のURLとして認識できませんでした"
        case .videoNotFound:
            return "この動画のチャンネルを特定できませんでした"
        case .channelNotFound:
            return "チャンネルが見つかりませんでした"
        case .uploadsPlaylistNotFound:
            return "このチャンネルの動画一覧を取得できませんでした"
        case .apiKeyMissing:
            return "APIキーが設定されていません"
        case .quotaExceeded:
            return "YouTube APIの利用上限に達しました。時間をおいて再度お試しください"
        case .networkError:
            return "通信に失敗しました"
        case .decodingError:
            return "動画一覧を取得できませんでした"
        case .unknown:
            return "不明なエラーが発生しました"
        }
    }
}
