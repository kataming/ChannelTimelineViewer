import SwiftUI

/// アプリの説明・重要な注意事項・プライバシーポリシーを表示する情報画面。
/// App Store 提出時、YouTube 公式アプリではないこと等を明示するために使う。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Channel Timeline Viewer"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(appName).font(.headline)
                    Text("チャンネルの投稿動画を公開日順（古い順）に整理し、過去動画視聴・シリーズ視聴・学習を進捗管理しながら行える視聴補助アプリです。YouTube 公式アプリの代替ではありません。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("重要な注意事項") {
                    disclaimerRow("このアプリは YouTube 公式アプリではありません。")
                    disclaimerRow("動画再生には YouTube 公式の埋め込みプレイヤー（IFrame Player）を使用しています。")
                    disclaimerRow("動画のダウンロードは行いません。")
                    disclaimerRow("広告回避は行いません。")
                    disclaimerRow("バックグラウンド再生は行いません。")
                }

                Section("共有シートから開く") {
                    Text("YouTube アプリや Safari の共有ボタンから「\(appName)」を選ぶと、共有されたチャンネル・動画のURLからそのチャンネルの動画一覧を開けます。共有機能はURLを受け取るだけで、外部への送信は行いません。共有先に表示されない場合は、共有シートの「その他」から本アプリをオンにしてください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("データの取得と再生について") {
                    Text("動画一覧の取得には YouTube Data API v3 を使用します。再生は YouTube 公式プレイヤーをそのまま埋め込んで表示します。スクレイピングや独自プレイヤーでの再生は行いません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("自動再生と続きから再生") {
                    Text("再生が終わると、いま開いているチャンネル一覧の次の動画を続けて再生します（再生画面のトグルでオフにできます）。進むのは一覧の中の次の動画だけで、関連動画へ勝手に移動することはありません。また、動画ごとの再生位置を端末内に保存し、次に開いたときは続きから再生します（オフにすると常に最初から再生します）。バックグラウンド再生は行わないため、アプリを閉じると再生も止まります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let url = ConfigLoader.privacyPolicyURL() {
                    Section {
                        Button {
                            openURL(url)
                        } label: {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                        }
                    }
                }
            }
            .navigationTitle("このアプリについて")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func disclaimerRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
        }
        .font(.subheadline)
    }
}
