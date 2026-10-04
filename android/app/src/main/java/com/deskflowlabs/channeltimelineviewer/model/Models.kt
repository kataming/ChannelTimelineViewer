package com.deskflowlabs.channeltimelineviewer.model

import kotlinx.serialization.Serializable

/**
 * 1本の動画。iOS 版 `Models/VideoItem.swift` と同じ内容を保持する。
 * `publishedAt` は保存・比較を単純にするためエポック秒で持つ。
 */
@Serializable
data class VideoItem(
    /** videoId */
    val id: String,
    val title: String,
    val description: String = "",
    val publishedAtEpochSeconds: Long,
    val thumbnailUrl: String? = null,
    val channelId: String = "",
    /**
     * 視聴回数（YouTube Data API `videos.list` の statistics.viewCount）。
     * 取れていない・非公開のときは null。保存済みの古い一覧（1.17 より前）にも無い。
     * Long なのは、Int の上限（約21億）を超える動画があるため。
     */
    val viewCount: Long? = null,
) {
    /** YouTube で開くための公式URL。 */
    val watchUrl: String get() = "https://www.youtube.com/watch?v=$id"
}

/** 一覧の並び順（右上のメニュー）。iOS `VideoSortOrder` と同じ。 */
enum class VideoSortOrder {
    /** 公開日の古い順（既定） */
    Oldest,
    /** 公開日の新しい順 */
    Newest,
    /** 視聴回数の多い順。視聴回数が分からない動画は最後（その中は古い順） */
    Popular,
}

/** 並び順を適用する。⚠️ iOS `sorted(by:)` と同じ規則にしておく。 */
fun List<VideoItem>.sortedBy(order: VideoSortOrder): List<VideoItem> = when (order) {
    VideoSortOrder.Oldest -> sortedByPublishedDate(ascending = true)
    VideoSortOrder.Newest -> sortedByPublishedDate(ascending = false)
    VideoSortOrder.Popular -> sortedWith(
        compareBy<VideoItem> { it.viewCount == null }
            .thenByDescending { it.viewCount ?: 0L }
            .thenBy { it.publishedAtEpochSeconds },
    )
}

/** 取得した視聴回数を反映する（取れなかった動画は前の値のまま）。 */
fun List<VideoItem>.withViewCounts(counts: Map<String, Long>): List<VideoItem> =
    map { video -> counts[video.id]?.let { video.copy(viewCount = it) } ?: video }

/** publishedAt で並び替える。ascending=true で古い順。 */
fun List<VideoItem>.sortedByPublishedDate(ascending: Boolean): List<VideoItem> =
    if (ascending) sortedBy { it.publishedAtEpochSeconds } else sortedByDescending { it.publishedAtEpochSeconds }

/**
 * チャンネル内検索：タイトルが検索語を含むか（docs/channel-search.md）。
 * NFKC＋小文字にそろえて部分一致。検索語が空（空白だけ）なら常に true。
 * ⚠️ iOS `VideoItem.titleMatches` / Web `titleMatches` と同じ規則にしておく。
 * （保存するデータには触れない拡張関数。検索語はどこにも送らない・保存しない）
 */
fun VideoItem.titleMatches(query: String): Boolean {
    val needle = searchKey(query.trim())
    return needle.isEmpty() || searchKey(title).contains(needle)
}

fun searchKey(text: String): String =
    java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFKC).lowercase(java.util.Locale.ROOT)

/** videoId の重複を取り除く（先に現れた方を残す）。保存済みの一覧に新着を足すときに使う。 */
fun List<VideoItem>.uniquedById(): List<VideoItem> {
    val seen = HashSet<String>()
    return filter { seen.add(it.id) }
}

/** YouTube チャンネル。 */
@Serializable
data class Channel(
    /** channelId（例: UCxxxxxxxxxxxxxxxxxxxxxx） */
    val id: String,
    val title: String,
    val thumbnailUrl: String? = null,
    /** アップロード動画のプレイリストID（contentDetails.relatedPlaylists.uploads） */
    val uploadsPlaylistId: String? = null,
)

/** お気に入り（最近使った）チャンネル。最終オープン日時を持つ。 */
@Serializable
data class FavoriteChannel(
    val id: String,
    val title: String,
    val thumbnailUrl: String? = null,
    val uploadsPlaylistId: String? = null,
    val lastOpenedAtEpochSeconds: Long,
) {
    fun toChannel(): Channel = Channel(id, title, thumbnailUrl, uploadsPlaylistId)

    companion object {
        fun from(channel: Channel, lastOpenedAtEpochSeconds: Long): FavoriteChannel =
            FavoriteChannel(
                id = channel.id,
                title = channel.title,
                thumbnailUrl = channel.thumbnailUrl,
                uploadsPlaylistId = channel.uploadsPlaylistId,
                lastOpenedAtEpochSeconds = lastOpenedAtEpochSeconds,
            )
    }
}

/** チャンネルごとの進捗。総本数・視聴済み数・最後に開いた動画を持つ。 */
@Serializable
data class ChannelProgress(
    val channelId: String,
    val totalCount: Int = 0,
    val watchedCount: Int = 0,
    val lastOpenedVideoId: String? = null,
) {
    /** 0.0〜1.0 の進捗率。総数が 0 のときは 0。 */
    val rate: Double get() = if (totalCount <= 0) 0.0 else watchedCount.toDouble() / totalCount
}

/** 1本の動画の再生位置（秒）。 */
@Serializable
data class PlaybackPosition(
    val videoId: String,
    val seconds: Double,
    val updatedAtEpochSeconds: Long,
) {
    companion object {
        /** m:ss 形式の表示。 */
        fun timeString(seconds: Double): String {
            val total = seconds.toInt().coerceAtLeast(0)
            return "%d:%02d".format(total / 60, total % 60)
        }
    }
}
