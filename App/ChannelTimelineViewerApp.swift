import SwiftUI

@main
struct ChannelTimelineViewerApp: App {
    // アプリ全体で共有するローカルストア。
    @StateObject private var watchHistoryStore = WatchHistoryStore()
    // 「見るつもりがない」動画の印。自動再生で飛ばす。
    @StateObject private var skippedVideoStore = SkippedVideoStore()
    @StateObject private var favoriteStore = FavoriteChannelStore()
    @StateObject private var progressStore = ChannelProgressStore()
    @StateObject private var memoStore = VideoMemoStore()
    // 続きから再生用の再生位置と、再生の挙動設定。
    @StateObject private var positionStore = PlaybackPositionStore()
    @StateObject private var playbackSettings = PlaybackSettingsStore()
    // 買い切り Pro（複数チャンネル保存）。正は StoreKit の entitlement で、端末内はその写し。
    @StateObject private var proStore: ProEntitlementStore
    // 無料版の広告（AdMob）。Pro かどうかは proStore を読むだけで、課金側には触れない。
    // Pro なら同意フォームも SDK の初期化も広告リクエストも行わない。
    @StateObject private var ads: AdsManager
    // Pro が無効なときに「無料で使う1チャンネル」を覚える。
    @StateObject private var activeChannelStore = ActiveChannelStore()
    // 通知タップ（共有シートからのワンタップ起動）を受け取る。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 共有シート（Share Extension）から渡された YouTube URL の受け口。
    // 通知タップからも渡ってくるので共有インスタンスを使う。
    @StateObject private var sharedLinkRouter = SharedLinkRouter.shared
    @StateObject private var notificationPermission = NotificationPermission()
    /// 「チャンネルの追加方法」の案内を見終わったか（初回だけ自動で出すための印）。
    @StateObject private var channelTutorial = ChannelTutorialStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let pro = ProEntitlementStore()
        _proStore = StateObject(wrappedValue: pro)
        _ads = StateObject(wrappedValue: AdsManager(
            isPro: pro.isPro,
            isProPublisher: pro.$isPro.eraseToAnyPublisher()))
    }

    var body: some Scene {
        WindowGroup {
            ChannelInputView()
                .environmentObject(watchHistoryStore)
                .environmentObject(skippedVideoStore)
                .environmentObject(favoriteStore)
                .environmentObject(progressStore)
                .environmentObject(memoStore)
                .environmentObject(positionStore)
                .environmentObject(playbackSettings)
                .environmentObject(proStore)
                .environmentObject(activeChannelStore)
                .environmentObject(sharedLinkRouter)
                .environmentObject(notificationPermission)
                .environmentObject(channelTutorial)
                .environmentObject(ads)
                .onOpenURL { url in
                    // channeltimelineviewer://share?url=... 以外は無視する。
                    sharedLinkRouter.handle(url)
                }
                .task {
                    // 広告の準備（同意 → 初期化）。Pro なら何もしない。画面の表示は待たせない。
                    ads.activate()
                    await notificationPermission.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await notificationPermission.refresh() }
                }
        }
    }
}
