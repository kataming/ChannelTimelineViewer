import Foundation
import StoreKit

/// Pro（買い切り・非消費型）の所有状態。StoreKit 2 で判定する。
///
/// 決めごと:
/// - **ローカルのフラグだけを信用しない。** 正は常に `Transaction.currentEntitlements`。
///   端末内に持つのは「前回 StoreKit が返した内容の写し」で、起動直後の一瞬だけ使う。
/// - 返金・購入取消（revoked）は `currentEntitlements` から消える／`revocationDate` が入るので、
///   そのときは Pro を落とす。落とした結果は上限超過チャンネルの**ロック**に反映される（削除はしない）。
/// - 価格はコードに持たない。App Store Connect の値をそのまま表示する。
/// - 購入失敗・キャンセル・保留・復元失敗のどれでも落とさない。メッセージを返すだけ。
@MainActor
final class ProEntitlementStore: ObservableObject {

    /// App Store Connect に登録する App 内課金の商品ID（Android の Play 側と同じ値）。
    static let productID = "pro_unlock"

    /// Pro を持っているか。画面はこれを見て上限とロックを決める。
    @Published private(set) var isPro: Bool
    /// 表示用の商品（価格は `product.displayPrice`）。取れていなければ nil。
    @Published private(set) var product: Product?
    /// 購入・復元の処理中。ボタンの二度押しを防ぐ。
    @Published private(set) var isBusy = false
    /// 画面に出す一言（購入できた・保留・失敗など）。表示したら `clearMessage()`。
    @Published var message: String?

    private let defaults: UserDefaults
    private let cacheKey = "pro_unlocked_v1"
    private var updatesTask: Task<Void, Never>?

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
        isBusy = true
        defer { isBusy = false }

        if product == nil { await loadProduct() }
        guard let product else {
            // 商品が未公開・審査中などで取得できない状態。
            message = String(localized: "pro.error.unavailable")
            return
        }

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
                    message = String(localized: "pro.error.failed")
                }
            case .pending:
                // 承認待ち（ファミリー共有の承認・コンビニ払いなど）。完了すれば updates で届く。
                message = String(localized: "pro.pending")
            case .userCancelled:
                break   // 本人がやめただけなので何も出さない
            @unknown default:
                message = String(localized: "pro.error.failed")
            }
        } catch {
            message = String(localized: "pro.error.failed")
        }
    }

    /// 「購入を復元」。機種変更・再インストール後に同じ Apple ID で元に戻すための導線。
    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        // 失敗しても currentEntitlements は読めるので、ここで止めない。
        try? await AppStore.sync()
        await refreshEntitlement()
        message = isPro
            ? String(localized: "pro.restore.done")
            : String(localized: "pro.restore.none")
    }

    func clearMessage() {
        message = nil
    }

    // MARK: - 内部

    private func loadProduct() async {
        guard let loaded = try? await Product.products(for: [Self.productID]) else { return }
        product = loaded.first { $0.id == Self.productID }
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
