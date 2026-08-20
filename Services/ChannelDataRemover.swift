import Foundation

/// チャンネル1つぶんの記録をまとめて捨てる。
///
/// 無料の枠で「入れ替える」「削除する」を選んだときに使う。
/// **視聴済み・スキップ・メモ・再生位置・進捗・一覧キャッシュを消す＝元に戻せない**ので、
/// 呼ぶ前に画面ではっきり警告すること。
///
/// 視聴済みなどは videoId をキーに持っているため、どの動画がそのチャンネルのものかは
/// 一覧キャッシュから引く。キャッシュが無い（まだ一度も一覧を開いていない）場合は
/// 動画単位の記録も無いので、進捗とお気に入りだけ消せばよい。
///
/// - Important: Pro が失効しただけのときは**消さずにロックする**（`ChannelSlotPolicy.isLocked`）。
///   こちらは本人が明示的に「入れ替える／削除する」を選んだときだけ使う。
@MainActor
struct ChannelDataRemover {
    let favoriteStore: FavoriteChannelStore
    let progressStore: ChannelProgressStore
    let videoListCache: VideoListCache
    let watchHistoryStore: WatchHistoryStore
    let skippedVideoStore: SkippedVideoStore
    let memoStore: VideoMemoStore
    let positionStore: PlaybackPositionStore

    /// - Returns: 記録を消した動画の本数
    @discardableResult
    func removeChannel(_ channelId: String) -> Int {
        let videoIds = (videoListCache.videos(for: channelId) ?? []).map(\.id)

        watchHistoryStore.removeAll(videoIds: videoIds)
        skippedVideoStore.removeAll(videoIds: videoIds)
        memoStore.removeAll(videoIds: videoIds)
        positionStore.removeAll(videoIds: videoIds)

        videoListCache.remove(channelId)
        progressStore.remove(channelId)
        favoriteStore.remove(channelId)
        return videoIds.count
    }
}
