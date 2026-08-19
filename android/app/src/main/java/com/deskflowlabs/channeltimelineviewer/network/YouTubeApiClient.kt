package com.deskflowlabs.channeltimelineviewer.network

import android.net.Uri
import com.deskflowlabs.channeltimelineviewer.BuildConfig
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.model.sortedByPublishedDate
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.time.Instant
import java.time.format.DateTimeParseException
import java.util.concurrent.TimeUnit

/** 動画一覧の1ページ分。 */
data class VideoPage(val items: List<VideoItem>, val nextPageToken: String?)

/**
 * YouTube Data API v3 クライアント。iOS 版 `Services/YouTubeAPIClient.swift` の移植。
 * スクレイピングは行わず、公式の Data API のみを使う。
 */
class YouTubeApiClient(
    private val apiKey: String = BuildConfig.YOUTUBE_API_KEY,
    private val httpClient: OkHttpClient = defaultClient,
    private val baseUrl: String = "https://www.googleapis.com/youtube/v3",
) {

    /** 暴走防止のための最大ページ数（50件/ページ × 100 = 5000本）。 */
    private val maxPages = 100

    /** 入力URL（または handle / channelId）からチャンネルを解決する。 */
    suspend fun resolveChannel(inputUrl: String): Channel =
        when (val identifier = ChannelResolver.parse(inputUrl)) {
            is ChannelIdentifier.ChannelId -> fetchChannel(listOf("id" to identifier.value))
            is ChannelIdentifier.Handle -> fetchChannel(listOf("forHandle" to "@${identifier.value}"))
            is ChannelIdentifier.Username -> fetchChannel(listOf("forUsername" to identifier.value))
            is ChannelIdentifier.CustomName ->
                fetchChannel(listOf("id" to searchChannelId(identifier.value)))
            // 共有された動画URL → videos.list で投稿チャンネルを特定してから解決する（quota 1）。
            is ChannelIdentifier.Video ->
                fetchChannel(listOf("id" to fetchChannelIdForVideo(identifier.videoId)))
        }

    /** videoId からその動画を投稿したチャンネルの channelId を取得する（videos.list / quota 1）。 */
    suspend fun fetchChannelIdForVideo(videoId: String): String {
        if (!ChannelResolver.isVideoId(videoId)) throw YouTubeApiException(YouTubeApiError.InvalidVideoUrl)
        val body = getJson("videos", listOf("part" to "snippet", "id" to videoId))
        return channelIdFromVideosList(body)
    }

    /** uploads プレイリストから全動画を取得し、古い順（publishedAt 昇順）で返す。 */
    suspend fun fetchVideos(playlistId: String): List<VideoItem> {
        val all = mutableListOf<VideoItem>()
        var token: String? = null
        var page = 0
        do {
            val result = fetchVideosPage(playlistId, token)
            all += result.items
            token = result.nextPageToken
            page += 1
        } while (token != null && page < maxPages)
        return all.sortedByPublishedDate(ascending = true)
    }

    /**
     * 既に持っている動画に当たるまで、新しい順にページを取得して**新着だけ**返す。
     *
     * @return 新着（新しい順）と、既知の動画に到達したかどうか。
     *   到達しなかった場合は差分が大きいので、呼び出し側で全件取得に切り替える。
     */
    suspend fun fetchNewVideos(
        playlistId: String,
        knownVideoIds: Set<String>,
        maxPages: Int = 5,
    ): Pair<List<VideoItem>, Boolean> {
        val newItems = mutableListOf<VideoItem>()
        var token: String? = null
        var page = 0
        var reachedKnown = false

        do {
            val result = fetchVideosPage(playlistId, token)
            for (item in result.items) {
                if (item.id in knownVideoIds) {
                    reachedKnown = true
                    break
                }
                newItems += item
            }
            if (reachedKnown) break
            token = result.nextPageToken
            page += 1
        } while (token != null && page < maxPages)

        // 最後まで見ても既知に当たらなかった＝そもそも全部が新しい（＝全件取得すべき）。
        return newItems to (reachedKnown || token == null)
    }

    /** uploads プレイリストの1ページ分を取得する。 */
    suspend fun fetchVideosPage(playlistId: String, pageToken: String?): VideoPage {
        val query = mutableListOf(
            "part" to "snippet,contentDetails",
            "playlistId" to playlistId,
            "maxResults" to "50",
        )
        if (pageToken != null) query += "pageToken" to pageToken

        val body = getJson("playlistItems", query)
        return videoPage(body)
    }

    private suspend fun fetchChannel(extraQuery: List<Pair<String, String>>): Channel {
        val body = getJson("channels", listOf("part" to "snippet,contentDetails") + extraQuery)
        val item = body["items"]?.jsonArray?.firstOrNull()?.jsonObject
            ?: throw YouTubeApiException(YouTubeApiError.ChannelNotFound)
        val snippet = item["snippet"]?.jsonObject
        return Channel(
            id = item.string("id") ?: throw YouTubeApiException(YouTubeApiError.ChannelNotFound),
            title = snippet?.string("title") ?: UNTITLED_CHANNEL,
            thumbnailUrl = bestThumbnail(snippet),
            uploadsPlaylistId = item["contentDetails"]?.jsonObject
                ?.get("relatedPlaylists")?.jsonObject?.string("uploads"),
        )
    }

    /** カスタムURL名から search.list で channelId を引く（quota 100）。 */
    private suspend fun searchChannelId(name: String): String {
        val body = getJson(
            "search",
            listOf("part" to "snippet", "type" to "channel", "q" to name, "maxResults" to "1"),
        )
        return body["items"]?.jsonArray?.firstOrNull()?.jsonObject
            ?.get("id")?.jsonObject?.string("channelId")
            ?: throw YouTubeApiException(YouTubeApiError.ChannelNotFound)
    }

    /** 共通のGETリクエスト。エラーを YouTubeApiError にマップする。 */
    private suspend fun getJson(path: String, query: List<Pair<String, String>>): JsonObject {
        if (apiKey.isBlank()) throw YouTubeApiException(YouTubeApiError.ApiKeyMissing)

        val builder = Uri.parse("$baseUrl/$path").buildUpon()
        query.forEach { (name, value) -> builder.appendQueryParameter(name, value) }
        builder.appendQueryParameter("key", apiKey)
        val url = builder.build().toString()

        val (code, body) = withContext(Dispatchers.IO) {
            try {
                httpClient.newCall(Request.Builder().url(url).get().build()).execute().use { response ->
                    response.code to (response.body?.string().orEmpty())
                }
            } catch (e: IOException) {
                throw YouTubeApiException(YouTubeApiError.NetworkError)
            }
        }

        when {
            code in 200..299 -> Unit
            code == 403 ->
                // quota 超過かどうかを本文から判定。
                if (body.contains("quotaExceeded") || body.contains("dailyLimitExceeded")) {
                    throw YouTubeApiException(YouTubeApiError.QuotaExceeded)
                } else {
                    throw YouTubeApiException(YouTubeApiError.Unknown)
                }
            code == 404 -> throw YouTubeApiException(YouTubeApiError.ChannelNotFound)
            else -> throw YouTubeApiException(YouTubeApiError.NetworkError)
        }

        return runCatching { json.parseToJsonElement(body).jsonObject }
            .getOrElse { throw YouTubeApiException(YouTubeApiError.DecodingError) }
    }

    companion object {
        /** タイトルが取れなかったときの表示。文言は画面側で置き換えられるよう素の文字列にする。 */
        const val UNTITLED_VIDEO = "(No title)"
        const val UNTITLED_CHANNEL = "(No channel name)"

        private val json = Json { ignoreUnknownKeys = true; isLenient = true }

        private val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(20, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .build()
        }

        /** videos.list のレスポンスから channelId を取り出す（ネットワーク非依存＝テスト可能）。 */
        fun channelIdFromVideosList(body: JsonObject): String {
            val channelId = body["items"]?.jsonArray?.firstOrNull()?.jsonObject
                ?.get("snippet")?.jsonObject?.string("channelId")
            if (channelId.isNullOrEmpty()) throw YouTubeApiException(YouTubeApiError.VideoNotFound)
            return channelId
        }

        /** playlistItems のレスポンスを VideoItem に変換する（ネットワーク非依存＝テスト可能）。 */
        fun videoPage(body: JsonObject): VideoPage {
            val items = body["items"]?.jsonArray.orEmpty().mapNotNull { element ->
                val item = element.jsonObject
                val snippet = item["snippet"]?.jsonObject
                val contentDetails = item["contentDetails"]?.jsonObject
                val videoId = contentDetails?.string("videoId")
                    ?: snippet?.get("resourceId")?.jsonObject?.string("videoId")
                    ?: return@mapNotNull null
                val publishedText = contentDetails?.string("videoPublishedAt")
                    ?: snippet?.string("publishedAt")
                VideoItem(
                    id = videoId,
                    title = snippet?.string("title") ?: UNTITLED_VIDEO,
                    description = snippet?.string("description").orEmpty(),
                    publishedAtEpochSeconds = parseIso8601(publishedText),
                    thumbnailUrl = bestThumbnail(snippet),
                    channelId = snippet?.string("videoOwnerChannelId")
                        ?: snippet?.string("channelId").orEmpty(),
                )
            }
            return VideoPage(items, body.string("nextPageToken"))
        }

        /** 一番大きいサムネイルを選ぶ（maxres → standard → high → medium → default）。 */
        fun bestThumbnail(snippet: JsonObject?): String? {
            val thumbnails = snippet?.get("thumbnails")?.jsonObject ?: return null
            for (size in listOf("maxres", "standard", "high", "medium", "default")) {
                thumbnails[size]?.jsonObject?.string("url")?.let { return it }
            }
            return null
        }

        /** ISO8601（小数秒の有無どちらも）をエポック秒にする。読めなければ 0。 */
        fun parseIso8601(text: String?): Long {
            if (text.isNullOrBlank()) return 0
            return try {
                Instant.parse(text).epochSecond
            } catch (e: DateTimeParseException) {
                0
            }
        }

        private fun JsonObject.string(key: String): String? =
            runCatching { this[key]?.jsonPrimitive?.content }.getOrNull()
    }
}
