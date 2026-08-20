import SwiftUI

/// 「記録が消える」操作を確認するシート群。
///
/// 共通の作り:
/// - 消えることを**大きめ・太字・赤**で出す（小さな注意書きにしない）
/// - 記録を失わずに済む道（Pro）を、失う操作より**上**に置く
/// - キャンセルで安全に戻れる
struct DestructiveConfirmSheet<Actions: View>: View {
    let title: LocalizedStringKey
    let warning: String
    let note: LocalizedStringKey?
    @ViewBuilder var actions: () -> Actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(warning)
                    .font(.title3.bold())
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let note {
                    Text(note)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    actions()

                    Button("common.cancel") { dismiss() }
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

/// 目立たせたい主要ボタン（Pro の案内）。
struct PrimarySheetButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
    }
}

/// 記録が消える操作。危険と分かる見た目にする（控えめ＋赤）。
struct DestructiveSheetButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .tint(.red)
    }
}

/// Pro が無効になったときに、無料で使い続ける1チャンネルを選ぶ。
struct FreeChannelPickerSheet: View {
    let favorites: [FavoriteChannel]
    let activeChannelId: String?
    let onSelect: (FavoriteChannel) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(favorites) { favorite in
                        Button {
                            onSelect(favorite)
                            dismiss()
                        } label: {
                            HStack {
                                Text(favorite.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if favorite.id == activeChannelId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } header: {
                    Text("pro.disabled.title")
                } footer: {
                    Text("pro.disabled.body")
                }
            }
            .navigationTitle(Text("pro.disabled.choose"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }
}
