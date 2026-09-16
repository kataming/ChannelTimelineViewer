import Foundation

/// Watch Queue V2 同期 API のクライアント（iOS 側）。
///
/// 送るもの: ペアリングのコード・端末トークン・端末の種別とバージョン・購入状態の写し。
/// 送らないもの: Google アカウント情報・視聴履歴・保存チャンネル・メモ・再生位置。
///
/// Feature Flag が OFF の間、`/v2/config` 以外はすべて 503 を返す。
/// そのときアプリは V2 以前とまったく同じ見た目・動きに戻る（`WatchQueueStore` が面倒を見る）。
enum WatchQueueSyncError: Error, Equatable {
    case network
    case disabled          // サーバー側の Feature Flag が OFF（503）
    case unauthorized      // 端末が失効している（401/403）
    case notFound          // コードが存在しない（404）
    case expired           // コードの有効期限切れ（410）
    case alreadyUsed       // そのコードは使用済み（409）
    case tooManyAttempts   // 入力しすぎ / レート制限（429）
    case invalid           // 形が正しくない（400）
    case server            // 5xx
    case unknown

    /// 画面に出す文言のキー（7言語は Localization/strings.json にある）。
    var messageKey: String {
        switch self {
        case .network: return "watchQueue.error.network"
        case .disabled: return "watchQueue.error.disabled"
        case .unauthorized: return "watchQueue.error.unauthorized"
        case .notFound: return "watchQueue.error.code"
        case .expired: return "watchQueue.error.expired"
        case .alreadyUsed: return "watchQueue.error.used"
        case .tooManyAttempts: return "watchQueue.error.tooMany"
        case .invalid, .server, .unknown: return "watchQueue.error.generic"
        }
    }
}

struct WatchQueueConfig: Decodable {
    let watchQueueV2Enabled: Bool
    let contractVersion: Int
    let maxQueues: Int
    let maxItems: Int
    let pairingTtlSeconds: Int
}

struct WatchQueuePairing: Decodable {
    let groupId: String
    let deviceToken: String?
}

struct WatchQueueItemDTO: Decodable, Equatable {
    let videoId: String
    let title: String?
    let channelName: String?
    let durationText: String?
    let addedAt: String?
}

struct WatchQueueDTO: Decodable, Equatable {
    let queueId: String
    let name: String
    let version: Int
    let updatedAt: Double?
    let items: [WatchQueueItemDTO]
}

struct WatchQueueEntitlement: Decodable, Equatable {
    let isPro: Bool
    let channelCount: Int
    let queueCount: Int
    let total: Int
    let canCreateAnother: Bool
}

struct WatchQueueListResponse: Decodable {
    let queues: [WatchQueueDTO]
    let entitlement: WatchQueueEntitlement
}

final class WatchQueueSyncClient {
    /// 同期サーバー（Chrome 拡張・Web VIEWER と同じ場所）。
    static let defaultBaseURL = URL(string: "https://watch-queue-sync.atamitrading.workers.dev")!
    /// この版が扱える機能。サーバーはこれを見て V2 対応クライアントだと判断する。
    static let capabilities = "watch_queue_v2"

    private let baseURL: URL
    private let session: URLSession
    private let clientVersion: String

    /// 送るのは「どの版のアプリか」だけ（端末の識別子は送らない）。
    static var bundleVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short)(\(build))"
    }

    init(baseURL: URL = WatchQueueSyncClient.defaultBaseURL,
         session: URLSession = .shared,
         clientVersion: String = WatchQueueSyncClient.bundleVersion) {
        self.baseURL = baseURL
        self.session = session
        self.clientVersion = clientVersion
    }

    // MARK: - 呼び出し

    /// Feature Flag と上限値。ペアリング前でも呼べる唯一のエンドポイント。
    func fetchConfig() async throws -> WatchQueueConfig {
        try await send(path: "/v2/config", method: "GET", token: nil, body: Optional<Data>.none)
    }

    /// 拡張に出ているコードを入力して、同じグループに入る。
    /// すでにペアリング済みなら、そのトークンを渡してグループを増やさない。
    func claim(code: String, existingToken: String?) async throws -> WatchQueuePairing {
        var body: [String: Any] = [
            "code": code,
            "platform": "ios",
            "capabilities": Self.capabilities,
            "clientVersion": clientVersion,
        ]
        if let existingToken { body["deviceToken"] = existingToken }
        return try await send(path: "/v2/pairing/claim", method: "POST", token: nil,
                              body: try JSONSerialization.data(withJSONObject: body))
    }

    /// このグループのキュー一式（並び順はサーバーが position 順で返す）。
    func fetchQueues(token: String) async throws -> WatchQueueListResponse {
        try await send(path: "/v2/queues", method: "GET", token: token, body: Optional<Data>.none)
    }

    /// 購入状態の写しを渡す（判定の正本は App Store の entitlement。拡張は自己申告できない）。
    @discardableResult
    func reportEntitlement(token: String, isPro: Bool, channelCount: Int) async throws -> WatchQueueEntitlement {
        let body = try JSONSerialization.data(withJSONObject: ["isPro": isPro, "channelCount": channelCount])
        return try await send(path: "/v2/entitlement", method: "POST", token: token, body: body)
    }

    /// この端末の接続を解除する（サーバー側で失効させる）。
    func revokeSelf(token: String) async throws {
        let _: [String: Bool] = try await send(path: "/v2/devices/revoke", method: "POST", token: token,
                                               body: try JSONSerialization.data(withJSONObject: [:]))
    }

    // MARK: - 共通処理

    private func send<T: Decodable>(path: String, method: String, token: String?, body: Data?) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(clientVersion, forHTTPHeaderField: "x-client-version")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WatchQueueSyncError.network
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Self.error(for: status, data: data) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WatchQueueSyncError.unknown
        }
    }

    private static func error(for status: Int, data: Data) -> WatchQueueSyncError {
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])??["error"] as? String
        switch status {
        case 400: return .invalid
        case 401, 403: return .unauthorized
        case 404: return .notFound
        case 409: return .alreadyUsed
        case 410: return .expired
        case 429: return .tooManyAttempts
        case 503: return code == "disabled" ? .disabled : .server
        case 500...599: return .server
        default: return .unknown
        }
    }
}
