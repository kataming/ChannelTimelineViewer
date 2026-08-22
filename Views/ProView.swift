import SwiftUI

/// Pro（買い切り）の説明と購入。
///
/// 表示で必ず守ること（App Store の要件でもあり、利用者への説明としても必要）:
/// - 買い切りであること／サブスクリプションではないこと
/// - Pro で解放されるのは「複数チャンネル保存」と「チャンネルごとの記録の保持」であること
/// - 無料でも1チャンネルは主要機能込みで使えること
/// - **StoreKit から取った実価格を出すこと**
///
/// 2026-08 の審査却下（2.1(b)）は、価格が取れないまま「価格を確認しています…」で
/// 止まっていたことが原因。取得中・取得済み・失敗を区別し、失敗時は再取得の導線を出す。
struct ProView: View {
    @EnvironmentObject private var pro: ProEntitlementStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("pro.headline")
                        .font(.headline)
                    Text("pro.benefit.multiChannel")
                    Text("pro.notSubscription")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Text("pro.freeFeatures.body")
                        .font(.callout)
                    Text("pro.free.summary")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("pro.freeFeatures.header")
                }

                Section {
                    Text("pro.proFeatures.body")
                        .font(.callout)
                } header: {
                    Text("pro.proFeatures.header")
                }

                Section {
                    if pro.isPro {
                        Label("pro.owned", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        purchaseRow
                    }

                    Button("pro.restore") {
                        Task { await pro.restore() }
                    }
                    .disabled(pro.isBusy)
                } footer: {
                    Text("pro.restore.hint.apple")
                }

                if let message = pro.message {
                    Section {
                        Text(message)
                        Button("common.close") { pro.clearMessage() }
                            .font(.footnote)
                    }
                }

                Section {
                    Text("disclaimer.short")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(Text("pro.name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
            }
            // 開くたびに購入状態と価格を読み直す（別端末で買った直後でも合うように）。
            .task { await pro.refresh() }
        }
    }

    /// 購入ボタンと、その下に出す価格の状態。
    @ViewBuilder
    private var purchaseRow: some View {
        Button {
            Task { await pro.purchase() }
        } label: {
            HStack {
                if pro.isBusy { ProgressView().padding(.trailing, 4) }
                Text(buyLabel)
                    .font(.body.bold())
            }
        }
        // 商品（＝価格）が取れるまでは押せないようにする。
        .disabled(pro.isBusy || !pro.loadState.canPurchase)

        if pro.loadState.isLoading {
            Text("pro.price.loading")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if pro.loadState.failureReason != nil {
            Text("pro.price.failed")
                .font(.footnote)
                .foregroundStyle(.red)
            Button("pro.price.retry") {
                Task { await pro.reloadProduct() }
            }
            .font(.footnote)
        }
    }

    /// 価格はコードに持たず、App Store が返す表示価格をそのまま使う。
    private var buyLabel: String {
        guard let product = pro.product else { return String(localized: "pro.buy") }
        return String(format: String(localized: "pro.buy.format"), product.displayPrice)
    }
}
