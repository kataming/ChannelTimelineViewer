package com.deskflowlabs.channeltimelineviewer.data

/**
 * チャンネル1つぶんの記録をまとめて捨てる。
 *
 * 無料の枠（保存1件）で「入れ替える」を選んだときに使う。
 * **視聴済み・スキップ・メモ・再生位置・進捗・一覧キャッシュを消す＝元に戻せない**ので、
 * 呼ぶ前に画面ではっきり警告すること（`pro.limit.warning.format`）。
 *
 * 視聴済みなどは videoId をキーに持っているため、どの動画がそのチャンネルのものかは
 * 一覧キャッシュから引く。キャッシュが無い（まだ一度も一覧を開いていない）場合は
 * 動画単位の記録も無いので、進捗とお気に入りだけ消せばよい。
 */
class ChannelDataRemover(
    private val favorites: FavoriteChannelStore,
    private val progress: ChannelProgressStore,
    private val videoListCache: VideoListCache,
    private val watchStore: WatchHistoryStore,
    private val skipStore: SkippedVideoStore,
    private val memoStore: VideoMemoStore,
    private val positionStore: PlaybackPositionStore,
) {

    /**
     * @return 記録を消した動画の本数（画面に出す用）
     */
    fun removeChannel(channelId: String): Int {
        val videoIds = videoListCache.load(channelId)?.videos?.map { it.id }.orEmpty()

        watchStore.removeAll(videoIds)
        skipStore.removeAll(videoIds)
        memoStore.removeAll(videoIds)
        positionStore.removeAll(videoIds)

        videoListCache.remove(channelId)
        progress.remove(channelId)
        favorites.remove(channelId)
        return videoIds.size
    }
}
