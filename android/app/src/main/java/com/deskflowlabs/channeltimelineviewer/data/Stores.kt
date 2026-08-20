package com.deskflowlabs.channeltimelineviewer.data

import android.content.Context
import android.content.SharedPreferences
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.ChannelProgress
import com.deskflowlabs.channeltimelineviewer.model.FavoriteChannel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

/**
 * 端末内保存の共通部分。iOS 版の UserDefaults に相当する。
 * どのストアも「アプリの外へは出さない」ことが前提（プライバシーポリシーの記載どおり）。
 */
internal val storeJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

internal fun Context.storePrefs(): SharedPreferences =
    getSharedPreferences("channel_timeline_viewer", Context.MODE_PRIVATE)

/** 現在時刻（エポック秒）。テストから差し替えられるように関数で持つ。 */
internal fun nowEpochSeconds(): Long = System.currentTimeMillis() / 1000

/**
 * 視聴済みの記録。videoId → 視聴日時（エポック秒）。
 */
class WatchHistoryStore(private val prefs: SharedPreferences) {
    private val key = "watch_history_v1"
    private val _watched = MutableStateFlow(load())
    val watched: StateFlow<Map<String, Long>> = _watched.asStateFlow()

    fun isWatched(videoId: String): Boolean = _watched.value.containsKey(videoId)

    val watchedCount: Int get() = _watched.value.size

    fun markWatched(videoId: String, at: Long = nowEpochSeconds()) {
        if (isWatched(videoId)) return
        update(_watched.value + (videoId to at))
    }

    fun markUnwatched(videoId: String) {
        if (!isWatched(videoId)) return
        update(_watched.value - videoId)
    }

    fun toggleWatched(videoId: String) {
        if (isWatched(videoId)) markUnwatched(videoId) else markWatched(videoId)
    }

    /** まとめて消す（チャンネルの記録を捨てるとき）。 */
    fun removeAll(videoIds: Collection<String>) {
        if (videoIds.isEmpty()) return
        val ids = videoIds.toSet()
        val next = _watched.value.filterKeys { it !in ids }
        if (next.size != _watched.value.size) update(next)
    }

    /** 一覧のうち視聴済みの本数。 */
    fun watchedCount(videoIds: Collection<String>): Int = videoIds.count { isWatched(it) }

    private fun update(value: Map<String, Long>) {
        _watched.value = value
        prefs.edit().putString(key, storeJson.encodeToString(
            MapSerializer(String.serializer(), Long.serializer()), value)).apply()
    }

    private fun load(): Map<String, Long> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return runCatching {
            storeJson.decodeFromString(MapSerializer(String.serializer(), Long.serializer()), raw)
        }.getOrDefault(emptyMap())
    }
}

/**
 * スキップ指定（自動再生で飛ばす）。視聴済みとは別の状態。
 */
class SkippedVideoStore(private val prefs: SharedPreferences) {
    private val key = "skipped_videos_v1"
    private val _skipped = MutableStateFlow(load())
    val skipped: StateFlow<Set<String>> = _skipped.asStateFlow()

    fun isSkipped(videoId: String): Boolean = videoId in _skipped.value

    val skippedCount: Int get() = _skipped.value.size

    fun markSkipped(videoId: String) {
        if (isSkipped(videoId)) return
        update(_skipped.value + videoId)
    }

    fun toggleSkipped(videoId: String) {
        update(if (isSkipped(videoId)) _skipped.value - videoId else _skipped.value + videoId)
    }

    /** まとめて消す（チャンネルの記録を捨てるとき）。 */
    fun removeAll(videoIds: Collection<String>) {
        if (videoIds.isEmpty()) return
        val next = _skipped.value - videoIds.toSet()
        if (next.size != _skipped.value.size) update(next)
    }

    private fun update(value: Set<String>) {
        _skipped.value = value
        prefs.edit().putStringSet(key, value).apply()
    }

    private fun load(): Set<String> = prefs.getStringSet(key, emptySet()).orEmpty().toSet()
}

/**
 * 動画ごとのメモ（学習・シリーズ視聴用）。
 */
class VideoMemoStore(private val prefs: SharedPreferences) {
    private val key = "video_memos_v1"
    private val _memos = MutableStateFlow(load())
    val memos: StateFlow<Map<String, String>> = _memos.asStateFlow()

    fun memo(videoId: String): String = _memos.value[videoId].orEmpty()

    fun setMemo(text: String, videoId: String) {
        val trimmed = text
        val next = if (trimmed.isEmpty()) _memos.value - videoId else _memos.value + (videoId to trimmed)
        _memos.value = next
        prefs.edit().putString(key, storeJson.encodeToString(
            MapSerializer(String.serializer(), String.serializer()), next)).apply()
    }

    /** まとめて消す（チャンネルの記録を捨てるとき）。 */
    fun removeAll(videoIds: Collection<String>) {
        if (videoIds.isEmpty()) return
        val ids = videoIds.toSet()
        val next = _memos.value.filterKeys { it !in ids }
        if (next.size == _memos.value.size) return
        _memos.value = next
        prefs.edit().putString(key, storeJson.encodeToString(
            MapSerializer(String.serializer(), String.serializer()), next)).apply()
    }

    private fun load(): Map<String, String> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return runCatching {
            storeJson.decodeFromString(MapSerializer(String.serializer(), String.serializer()), raw)
        }.getOrDefault(emptyMap())
    }
}

/**
 * 動画ごとの再生位置（続きから再生用）。
 *
 * 位置の取得元は**公式プレイヤーが通知する再生時間だけ**で、動画データは保存しない。
 */
class PlaybackPositionStore(private val prefs: SharedPreferences) {
    private val key = "playback_positions_v1"
    private var positions: MutableMap<String, Double> = load()

    /** 保存されている再開位置（秒）。無ければ null。 */
    fun position(videoId: String): Double? =
        positions[videoId]?.takeIf { it >= MINIMUM_RESUME_SECONDS }

    fun hasPosition(videoId: String): Boolean = position(videoId) != null

    /**
     * 再生位置を記録する。
     * 冒頭すぎる場合・ほぼ見終わっている場合は「続きから」の意味がないので消す。
     */
    fun record(videoId: String, seconds: Double, duration: Double) {
        if (videoId.isEmpty() || !seconds.isFinite() || seconds < 0) return

        val nearEnd = duration > 0 && seconds >= duration - FINISHED_THRESHOLD_SECONDS
        if (seconds < MINIMUM_RESUME_SECONDS || nearEnd) {
            clear(videoId)
            return
        }
        positions[videoId] = seconds
        save()
    }

    /** 記録を消す（最初から見直した・見終わった場合）。 */
    fun clear(videoId: String) {
        if (positions.remove(videoId) != null) save()
    }

    /** まとめて消す（チャンネルの記録を捨てるとき）。 */
    fun removeAll(videoIds: Collection<String>) {
        if (videoIds.isEmpty()) return
        var removed = false
        videoIds.forEach { if (positions.remove(it) != null) removed = true }
        if (removed) save()
    }

    private fun save() {
        prefs.edit().putString(key, storeJson.encodeToString(
            MapSerializer(String.serializer(), Double.serializer()), positions)).apply()
    }

    private fun load(): MutableMap<String, Double> {
        val raw = prefs.getString(key, null) ?: return mutableMapOf()
        return runCatching {
            storeJson.decodeFromString(
                MapSerializer(String.serializer(), Double.serializer()), raw).toMutableMap()
        }.getOrDefault(mutableMapOf())
    }

    companion object {
        /** これ未満の位置は「実質最初から」とみなして保存しない（秒）。 */
        const val MINIMUM_RESUME_SECONDS = 10.0
        /** 終端からこの秒数以内まで見ていたら「見終わった」とみなして保存しない（秒）。 */
        const val FINISHED_THRESHOLD_SECONDS = 15.0

        /** m:ss 形式の表示。 */
        fun timeString(seconds: Double): String {
            val total = seconds.toInt().coerceAtLeast(0)
            return "%d:%02d".format(total / 60, total % 60)
        }
    }
}

/**
 * お気に入り（最近使った）チャンネル。最終オープンが新しい順に並べて保持する。
 */
class FavoriteChannelStore(private val prefs: SharedPreferences) {
    private val key = "favorite_channels_v1"
    private val _favorites = MutableStateFlow(load())
    val favorites: StateFlow<List<FavoriteChannel>> = _favorites.asStateFlow()

    fun touch(channel: Channel, at: Long = nowEpochSeconds()) {
        val others = _favorites.value.filterNot { it.id == channel.id }
        update((listOf(FavoriteChannel.from(channel, at)) + others)
            .sortedByDescending { it.lastOpenedAtEpochSeconds })
    }

    fun remove(channelId: String) {
        update(_favorites.value.filterNot { it.id == channelId })
    }

    private fun update(value: List<FavoriteChannel>) {
        _favorites.value = value
        prefs.edit().putString(key, storeJson.encodeToString(
            ListSerializer(FavoriteChannel.serializer()), value)).apply()
    }

    private fun load(): List<FavoriteChannel> {
        val raw = prefs.getString(key, null) ?: return emptyList()
        return runCatching {
            storeJson.decodeFromString(ListSerializer(FavoriteChannel.serializer()), raw)
        }.getOrDefault(emptyList())
    }
}

/**
 * チャンネルごとの進捗（総数・視聴済み数・最後に開いた動画）。
 */
class ChannelProgressStore(private val prefs: SharedPreferences) {
    private val key = "channel_progress_v1"
    private val _progress = MutableStateFlow(load())
    val progress: StateFlow<Map<String, ChannelProgress>> = _progress.asStateFlow()

    fun progress(channelId: String): ChannelProgress? = _progress.value[channelId]

    fun updateCounts(channelId: String, totalCount: Int, watchedCount: Int) {
        val current = _progress.value[channelId] ?: ChannelProgress(channelId)
        update(_progress.value + (channelId to current.copy(
            totalCount = totalCount, watchedCount = watchedCount)))
    }

    fun recordOpened(channelId: String, videoId: String) {
        val current = _progress.value[channelId] ?: ChannelProgress(channelId)
        update(_progress.value + (channelId to current.copy(lastOpenedVideoId = videoId)))
    }

    fun remove(channelId: String) {
        update(_progress.value - channelId)
    }

    private fun update(value: Map<String, ChannelProgress>) {
        _progress.value = value
        prefs.edit().putString(key, storeJson.encodeToString(
            MapSerializer(String.serializer(), ChannelProgress.serializer()), value)).apply()
    }

    private fun load(): Map<String, ChannelProgress> {
        val raw = prefs.getString(key, null) ?: return emptyMap()
        return runCatching {
            storeJson.decodeFromString(
                MapSerializer(String.serializer(), ChannelProgress.serializer()), raw)
        }.getOrDefault(emptyMap())
    }
}

/**
 * チャンネルごとの動画一覧のキャッシュ。
 * 一度開いたチャンネルを開き直したときに、取得を待たずに表示するためのもの。
 */
class VideoListCache(private val prefs: SharedPreferences) {

    @kotlinx.serialization.Serializable
    data class Entry(val updatedAtEpochSeconds: Long, val videos: List<VideoItem>)

    fun load(channelId: String): Entry? {
        val raw = prefs.getString(keyFor(channelId), null) ?: return null
        return runCatching { storeJson.decodeFromString(Entry.serializer(), raw) }.getOrNull()
    }

    fun store(channelId: String, videos: List<VideoItem>, at: Long = nowEpochSeconds()) {
        val entry = Entry(at, videos)
        prefs.edit().putString(keyFor(channelId),
            storeJson.encodeToString(Entry.serializer(), entry)).apply()
    }

    fun remove(channelId: String) {
        prefs.edit().remove(keyFor(channelId)).apply()
    }

    private fun keyFor(channelId: String) = "video_list_cache_v1_$channelId"
}
