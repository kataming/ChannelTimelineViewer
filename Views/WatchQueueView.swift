import SwiftUI

/// Watch Queue（V2）の入口。接続していなければ接続、していればキューの一覧を出す。
///
/// この画面は **サーバーの Feature Flag が ON のときだけ**開ける（`WatchQueueStore.isAvailable`）。
/// 接続していない人・Flag が OFF の人には、アプリのどこにもこの機能は現れない。
struct WatchQueueView: View {
    @EnvironmentObject private var store: WatchQueueStore
    @EnvironmentObject private var settings: PlaybackSettingsStore
    @EnvironmentObject private var pro: ProEntitlementStore
    @EnvironmentObject private var favorites: FavoriteChannelStore
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var showDisconnectConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                if store.isPaired {
                    queuesSection
                    connectionSection
                } else {
                    pairingSection
                }

                if let messageKey = store.messageKey {
                    Section {
                        Text(LocalizedStringKey(messageKey))
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("watchQueue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common.close") { dismiss() }
                }
            }
            .navigationDestination(for: String.self) { queueId in
                if let queue = store.queue(withId: queueId) {
                    WatchQueuePlayerView(queue: queue, settings: settings)
                }
            }
            .task {
                await store.refreshAvailability()
                await store.loadQueues()
                await store.reportEntitlement(isPro: pro.isPro, channelCount: favorites.favorites.count)
            }
        }
    }

    // MARK: - 接続していないとき

    private var pairingSection: some View {
        Section {
            Text("watchQueue.pair.detail")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("watchQueue.pair.field", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.title3.monospaced())
            Button {
                Task {
                    await store.pair(code: code)
                    if store.isPaired { code = "" }
                }
            } label: {
                if store.isBusy {
                    ProgressView()
                } else {
                    Text("watchQueue.pair.button")
                }
            }
            .disabled(store.isBusy || code.trimmingCharacters(in: .whitespaces).isEmpty)
        } header: {
            Text("watchQueue.pair.title")
        }
    }

    // MARK: - 接続しているとき

    @ViewBuilder
    private var queuesSection: some View {
        if store.queues.isEmpty {
            Section {
                Text("watchQueue.empty.title").font(.headline)
                Text("watchQueue.empty.detail")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Section {
                ForEach(store.queues, id: \.queueId) { queue in
                    NavigationLink(value: queue.queueId) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(queue.name.isEmpty ? String(localized: "watchQueue.title") : queue.name)
                            // 差し込みは %1$@ なので、数は文字列にしてから渡す（iOS の %@ は数値を受け取れない）。
                            Text(String(format: String(localized: "watchQueue.count.format"),
                                        String(queue.items.count)))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("watchQueue.list.header")
            }
        }
    }

    private var connectionSection: some View {
        Section {
            Label("watchQueue.connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.footnote)
            Button("watchQueue.refresh") {
                Task { await store.loadQueues() }
            }
            .disabled(store.isBusy)
            Button("watchQueue.disconnect", role: .destructive) { showDisconnectConfirm = true }
        }
        .confirmationDialog("watchQueue.disconnect.confirm",
                            isPresented: $showDisconnectConfirm,
                            titleVisibility: .visible) {
            Button("watchQueue.disconnect", role: .destructive) {
                Task { await store.disconnect() }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("watchQueue.disconnect.detail")
        }
    }
}
