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
    // 通知タップ（共有シートからのワンタップ起動）を受け取る。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // 共有シート（Share Extension）から渡された YouTube URL の受け口。
    // 通知タップからも渡ってくるので共有インスタンスを使う。
    @StateObject private var sharedLinkRouter = SharedLinkRouter.shared
    @StateObject private var notificationPermission = NotificationPermission()
    // 共有シートから直接アプリを開けない iOS 仕様のため、クリップボード経由でも拾えるようにする。
    @StateObject private var clipboardDetector = ClipboardLinkDetector()
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(sharedLinkRouter)
                .environmentObject(clipboardDetector)
                .environmentObject(notificationPermission)
                .onOpenURL { url in
                    // channeltimelineviewer://share?url=... 以外は無視する。
                    sharedLinkRouter.handle(url)
                }
                // 共有してからアプリに戻ってきたタイミングで、クリップボードの URL を拾えるようにする。
                .task {
                    await clipboardDetector.refresh()
                    await notificationPermission.refresh()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await clipboardDetector.refresh()
                        await notificationPermission.refresh()
                    }
                }
        }
    }
}
