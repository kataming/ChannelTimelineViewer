import Foundation
import SwiftUI

/// Watch Queue V2 の状態（この端末の接続とキューの写し）。
///
/// 守っていること:
/// - **Feature Flag が OFF のあいだは、何も見せない・何も送らない**。一度も取れていないときも OFF 扱い。
/// - 保存チャンネル・視聴記録・メモ・再生位置・購入状態には一切触れない（読むのは購入状態だけ）。
/// - 端末トークンは Keychain にだけ置き、画面にも URL にもログにも出さない。
/// - Pro かどうかを決めるのはこのアプリ側（StoreKit の entitlement）で、サーバーへは写しを渡すだけ。
@MainActor
final class WatchQueueStore: ObservableObject {
    /// この版が Watch Queue V2 を積んでいるか（ビルド時の安全弁。サーバーの Flag と両方 true で初めて出る）。
    static let buildSupportsV2 = true

    private enum Key {
        static let groupId = "watch_queue_group_v1"
        static let pairedAt = "watch_queue_paired_at_v1"
        /// 最後に取れた Feature Flag の値（取れていない間は false）。
        static let enabledCache = "watch_queue_enabled_cache_v1"
    }

    /// サーバーの Feature Flag（最後に取れた値。未取得なら false）。
    @Published private(set) var remoteEnabled: Bool
    @Published private(set) var groupId: String?
    @Published private(set) var queues: [WatchQueueDTO] = []
    @Published private(set) var entitlement: WatchQueueEntitlement?
    @Published private(set) var isBusy = false
    /// 画面に出す文言キー（生のエラーは出さない）。
    @Published var messageKey: String?

    /// 拡張のリンクから来たが、まだ再生に進めていないキュー（チュートリアル中など）。
    @Published var pendingQueueId: String?

    private let defaults: UserDefaults
    private let client: WatchQueueSyncClient
    private var token: String?

    init(defaults: UserDefaults = .standard, client: WatchQueueSyncClient = WatchQueueSyncClient()) {
        self.defaults = defaults
        self.client = client
        self.remoteEnabled = defaults.bool(forKey: Key.enabledCache)
        self.groupId = defaults.string(forKey: Key.groupId)
        self.token = WatchQueueKeychain.loadToken()
    }

    /// 画面に Watch Queue を出してよいか。ビルドとサーバーの両方が有効なときだけ。
    var isAvailable: Bool { Self.buildSupportsV2 && remoteEnabled }

    var isPaired: Bool { token != nil && groupId != nil }

    // MARK: - Feature Flag

    /// 起動時と前面復帰時に呼ぶ。取れなければ最後の値のままにする（勝手に ON にしない）。
    func refreshAvailability() async {
        guard Self.buildSupportsV2 else { return }
        do {
            let config = try await client.fetchConfig()
            remoteEnabled = config.watchQueueV2Enabled
            defaults.set(config.watchQueueV2Enabled, forKey: Key.enabledCache)
            if !config.watchQueueV2Enabled {
                // OFF になったら、画面に残っている写しも消して V2 以前の状態に戻す。
                queues = []
                entitlement = nil
            }
        } catch {
            // 取れないときは何も変えない。未取得なら false のまま＝出さない。
        }
    }

    // MARK: - ペアリング

    /// 拡張に表示された8文字のコードで接続する。大文字小文字・空白・ハイフンは気にしなくてよい。
    func pair(code: String) async {
        guard isAvailable else { return }
        isBusy = true
        messageKey = nil
        defer { isBusy = false }

        let normalized = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard normalized.count >= 6 else {
            messageKey = "watchQueue.error.code"
            return
        }
        do {
            let pairing = try await client.claim(code: normalized, existingToken: token)
            if let newToken = pairing.deviceToken {
                WatchQueueKeychain.saveToken(newToken)
                token = newToken
            }
            groupId = pairing.groupId
            defaults.set(pairing.groupId, forKey: Key.groupId)
            defaults.set(Date().timeIntervalSince1970, forKey: Key.pairedAt)
            await loadQueues()
        } catch let error as WatchQueueSyncError {
            messageKey = error.messageKey
        } catch {
            messageKey = WatchQueueSyncError.unknown.messageKey
        }
    }

    /// 接続を解除する。**ローカルの保存（チャンネル・視聴記録・購入）は何も消さない。**
    func disconnect() async {
        if let token {
            try? await client.revokeSelf(token: token)
        }
        WatchQueueKeychain.deleteToken()
        token = nil
        groupId = nil
        queues = []
        entitlement = nil
        defaults.removeObject(forKey: Key.groupId)
        defaults.removeObject(forKey: Key.pairedAt)
    }

    // MARK: - キュー

    func loadQueues() async {
        // プロパティと同じ名前で束縛すると、失効時に token を消せなくなるので別名にする。
        guard isAvailable, let deviceToken = token else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let response = try await client.fetchQueues(token: deviceToken)
            queues = response.queues
            entitlement = response.entitlement
            messageKey = nil
        } catch let error as WatchQueueSyncError {
            if error == .unauthorized {
                // 別の端末から接続を解除された。ローカルは消さずに、つながっていない状態へ戻す。
                WatchQueueKeychain.deleteToken()
                token = nil
                groupId = nil
                defaults.removeObject(forKey: Key.groupId)
            }
            messageKey = error.messageKey
        } catch {
            messageKey = WatchQueueSyncError.unknown.messageKey
        }
    }

    /// 購入状態の写しを渡す。判定の正本は StoreKit 側で、ここでは伝えるだけ。
    func reportEntitlement(isPro: Bool, channelCount: Int) async {
        guard isAvailable, let token else { return }
        do {
            entitlement = try await client.reportEntitlement(token: token, isPro: isPro, channelCount: channelCount)
        } catch {
            // 伝えられなくても、アプリの購入状態と使い勝手は変わらない。
        }
    }

    func queue(withId id: String) -> WatchQueueDTO? {
        queues.first { $0.queueId == id }
    }
}
