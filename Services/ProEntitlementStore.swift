import Foundation
import os
import StoreKit

/// 商品情報（価格）の取得状況。
///
/// 「取れていない＝購入できない」を画面と揃えるために、状態として持つ。
/// 2026-08 の審査却下（2.1(b)）は、取得に一度失敗したあと `nil` のまま
/// 「価格を確認しています…」で止まったことが原因だったため、状態と再試行を明示的に持つ。
enum ProProductLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    /// 購入ボタンを押せるのは、商品が取れているときだけ。
    var canPurchase: Bool { self == .loaded }

    /// 「価格を確認しています…」を出してよいのは、取得中（または開始前）だけ。
    var isLoading: Bool { self == .idle || self == .loading }

    var failureReason: String? {
        if case .failed(let reason) = self { return reason }
        return nil
    }
}

/// Pro（買い切り・非消費型）の所有状態と商品情報。StoreKit 2 で扱う。
///
/// 決めごと:
/// - **ローカルのフラグだけを信用しない。** 正は常に `Transaction.currentEntitlements`。
///   端末内に持つのは「前回 StoreKit が返した内容の写し」で、起動直後の一瞬だけ使う。
/// - 返金・購入取消（revoked）は `currentEntitlements` から消える／`revocationDate` が入るので、
///   そのとき Pro を落とす。落とした結果は上限超過チャンネルの**ロック**に反映される（削除はしない）。
/// - **価格はコードに持たない。** `product.displayPrice` をそのまま出す。
/// - 商品取得は**失敗したら間を空けて数回やり直す**。一度きりにしない。
/// - 購入失敗・キャンセル・保留・復元失敗のどれでも落とさない。メッセージを返すだけ。
@MainActor
final class ProEntitlementStore: ObservableObject {

    /// App Store Connect に登録した App 内課金の商品ID（Play 側と同じ値）。
    /// **完全一致**させること（大文字小文字・前後の空白・接頭辞の違いも不可）。
    static let productID = "pro_unlock"

    /// Pro を持っているか。画面はこれを見て上限とロックを決める。
    @Published private(set) var isPro: Bool
    /// 表示用の商品。価格は `product.displayPrice`。
    @Published private(set) var product: Product?
    /// 商品取得の状況。購入ボタンの有効・無効はこれで決める。
    @Published private(set) var loadState: ProProductLoadState = .idle
    /// 購入・復元の処理中。ボタンの二度押しを防ぐ。
    @Published private(set) var isBusy = false
    /// 画面に出す一言（購入できた・保留・失敗など）。表示したら `clearMessage()`。
    @Published var message: String?

    private let defaults: UserDefaults
    private let cacheKey = "pro_unlocked_v1"
    private var updatesTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.deskflowlabs.channeltimelineviewer", category: "IAP")

    /// 取得に失敗したときの再試行。合計4回まで（0.5s → 1s → 2s → 4s）。
    private let retryDelays: [Double] = [0.5, 1, 2, 4]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // StoreKit の返事が来るまでの初期値。来たら必ず上書きされる。
        self.isPro = defaults.bool(forKey: cacheKey)
        startListeningForTransactions()
    }

    // MARK: - 状態の取得

    /// 起動時・前面復帰時・購入画面表示時に呼ぶ。
    func refresh() async {
        await loadProduct()
        await refreshEntitlement()
    }

    /// 「価格を再取得」から呼ぶ。
    func reloadProduct() async {
        await loadProduct(force: true)
    }

    /// StoreKit に「いま持っているか」を聞き直す。返金・取消もここで反映される。
    func refreshEntitlement() async {
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID else { continue }
            // 返金・取消されたものは権利として数えない。
            if transaction.revocationDate == nil {
                owned = true
            }
        }
        apply(isPro: owned)
    }

    // MARK: - 購入・復元

    func purchase() async {
        guard !isBusy else { return }
        // 商品が取れていないのに購入フローへ進まない（何も起きないように見えるため）。
        guard let product else {
            await loadProduct(force: true)
            if product == nil {
                message = String(localized: "pro.price.failed")
                return
            }
            return await purchase()
        }

        isBusy = true
        defer { isBusy = false }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // 受け取ったことを StoreKit に伝える（これをしないと再通知され続ける）。
                    await transaction.finish()
                    await refreshEntitlement()
                    message = String(localized: "pro.owned")
                case .unverified:
                    // 署名の検証に失敗。権利は与えない。
                    log.error("購入の検証に失敗しました")
                    message = String(localized: "pro.error.failed")
                }
            case .pending:
                // 承認待ち（ファミリー共有の承認など）。完了すれば updates で届く。
                message = String(localized: "pro.pending")
            case .userCancelled:
                break   // 本人がやめただけなので何も出さない
            @unknown default:
                message = String(localized: "pro.error.failed")
            }
        } catch {
            log.error("購入に失敗しました: \(String(describing: error), privacy: .public)")
            message = String(localized: "pro.error.failed")
        }
    }

    /// 「購入を復元」。機種変更・再インストール後に同じ Apple アカウントで元に戻す導線。
    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        // 失敗しても currentEntitlements は読めるので、ここで止めない。
        do {
            try await AppStore.sync()
        } catch {
            log.notice("AppStore.sync に失敗: \(String(describing: error), privacy: .public)")
        }
        await refreshEntitlement()
        message = isPro
            ? String(localized: "pro.restore.done")
            : String(localized: "pro.restore.none.apple")
    }

    func clearMessage() {
        message = nil
    }

    // MARK: - 内部

    /// 商品情報を取る。失敗しても間を空けて数回やり直す。
    ///
    /// - Parameter force: すでに取れていても取り直す（「価格を再取得」用）。
    private func loadProduct(force: Bool = false) async {
        if product != nil && !force { return }
        if loadState == .loading { return }
        loadState = .loading

        for (attempt, delay) in retryDelays.enumerated() {
            do {
                let found = try await Product.products(for: [Self.productID])
                if let match = found.first(where: { $0.id == Self.productID }) {
                    product = match
                    loadState = .loaded
                    log.notice("商品を取得しました: \(match.id, privacy: .public) / \(match.displayPrice, privacy: .public)")
                    return
                }
                // 例外は出ないが空で返るケース。商品IDの不一致か、
                // App Store Connect 側で購入可能になっていない（契約・税務情報・審査状態）とき。
                let reason = "商品が見つかりません（ID \(Self.productID) / 返り値 \(found.count) 件）"
                log.error("\(reason, privacy: .public)")
                loadState = .failed(reason)
            } catch {
                let reason = String(describing: error)
                log.error("商品の取得に失敗（\(attempt + 1) 回目）: \(reason, privacy: .public)")
                loadState = .failed(reason)
            }

            if attempt < retryDelays.count - 1 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// 購入・返金・失効の通知を受け取り続ける。アプリが起きている間はこれで自動追随する。
    private func startListeningForTransactions() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self?.refreshEntitlement()
            }
        }
    }

    private func apply(isPro newValue: Bool) {
        if isPro != newValue { isPro = newValue }
        defaults.set(newValue, forKey: cacheKey)
    }
}
