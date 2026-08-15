import SwiftUI

@main
struct ChannelTimelineViewerApp: App {
    // アプリ全体で共有するローカルストア。
    @StateObject private var watchHistoryStore = WatchHistoryStore()
    @StateObject private var favoriteStore = FavoriteChannelStore()
    @StateObject private var progressStore = ChannelProgressStore()
    @StateObject private var memoStore = VideoMemoStore()
    // 続きから再生用の再生位置と、再生の挙動設定。
    @StateObject private var positionStore = PlaybackPositionStore()
    @StateObject private var playbackSettings = PlaybackSettingsStore()
    // 共有シート（Share Extension）から渡された YouTube URL の受け口。
    @StateObject private var sharedLinkRouter = SharedLinkRouter()

    var body: some Scene {
        WindowGroup {
            ChannelInputView()
                .environmentObject(watchHistoryStore)
                .environmentObject(favoriteStore)
                .environmentObject(progressStore)
                .environmentObject(memoStore)
                .environmentObject(positionStore)
                .environmentObject(playbackSettings)
                .environmentObject(sharedLinkRouter)
                .onOpenURL { url in
                    // channeltimelineviewer://share?url=... 以外は無視する。
                    sharedLinkRouter.handle(url)
                }
        }
    }
}
