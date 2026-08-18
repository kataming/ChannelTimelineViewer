import SwiftUI

/// アプリの説明・重要な注意事項・プライバシーポリシーを表示する情報画面。
/// App Store 提出時、YouTube 公式アプリではないこと等を明示するために使う。
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var notificationPermission: NotificationPermission

    private var appName: String { AppInfo.displayName }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(appName).font(.headline)
                    Text("about.summary")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section("about.notices.header") {
                    disclaimerRow(String(localized: "about.notice.notOfficial"))
                    disclaimerRow(String(localized: "about.notice.officialPlayer"))
                    disclaimerRow(String(localized: "about.notice.noDownload"))
                    disclaimerRow(String(localized: "about.notice.noAdBlock"))
                    disclaimerRow(String(localized: "about.notice.noBackground"))
                }

                Section("about.share.header") {
                    Text(String(format: String(localized: "about.share.body1"), appName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("about.share.body2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("about.oneTap.header") {
                    Text("about.oneTap.body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if notificationPermission.isEnabled {
                        Label("about.notify.enabled", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.green)
                    } else if notificationPermission.canAsk {
                        Button {
                            Task { await notificationPermission.request() }
                        } label: {
                            Label("about.notify.allow", systemImage: "bell.badge")
                        }
                    } else {
                        Button {
                            notificationPermission.openSettings()
                        } label: {
                            Label("about.notify.settings", systemImage: "gear")
                        }
                    }
                }

                Section("about.pin.header") {
                    Text(String(format: String(localized: "about.pin.body1"), appName))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("about.pin.body2")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "about.pin.steps"), appName))
                        .font(.footnote)
                }

                Section("about.data.header") {
                    Text("about.data.body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("about.autoPlay.header") {
                    Text("about.autoPlay.body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("about.screen.header") {
                    Text("about.screen.body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("about.resume.header") {
                    Text("about.resume.body")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let url = ConfigLoader.privacyPolicyURL() {
                    Section {
                        Button {
                            openURL(url)
                        } label: {
                            Label("about.privacyPolicy", systemImage: "hand.raised")
                        }
                    }
                }
            }
            .navigationTitle(Text("about.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
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
