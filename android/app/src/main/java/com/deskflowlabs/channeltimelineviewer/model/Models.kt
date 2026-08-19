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
) {
    /** YouTube で開くための公式URL。 */
    val watchUrl: String get() = "https://www.youtube.com/watch?v=$id"
}

/** publishedAt で並び替える。ascending=true で古い順。 */
fun List<VideoItem>.sortedByPublishedDate(ascending: Boolean): List<VideoItem> =
    if (ascending) sortedBy { it.publishedAtEpochSeconds } else sortedByDescending { it.publishedAtEpochSeconds }

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
