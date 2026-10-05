package com.deskflowlabs.channeltimelineviewer.network

import android.net.Uri
import android.util.Log
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

/** 動画一覧の1ページ分。[totalResults] はプレイリスト全体の本数（読み込みの進み具合を出すのに使う）。 */
data class VideoPage(val items: List<VideoItem>, val nextPageToken: String?, val totalResults: Int? = null)

/** 最初の案内に並べる人気の動画（選ぶとその投稿チャンネルを開く）。 */
data class PopularVideo(
    val videoId: String,
    val title: String,
    val channelId: String,
    val channelTitle: String,
    val thumbnailUrl: String?,
)

/**
 * YouTube Data API v3 クライアント。iOS 版 `Services/YouTubeAPIClient.swift` の移植。
 * スクレイピングは行わず、公式の Data API のみを使う。
 */
class YouTubeApiClient(
    private val apiKey: String = BuildConfig.YOUTUBE_API_KEY,
    private val httpClient: OkHttpClient = defaultClient,
    private val baseUrl: String = "https://www.googleapis.com/youtube/v3",
    /**
     * APIキーに「Android アプリ制限」をかけている場合に必要な自己申告。
     * 素の HTTP で呼ぶときは、Google のライブラリが付けているヘッダーを自分で付ける必要がある。
     */
    private val appIdentity: AndroidAppIdentity? = null,
    /** 人気動画の一覧を国ごとに持っている当方のサーバー（site/functions/api/popular.js）。 */
    private val popularUrl: String = "https://channeltimeline.jewelrysunflower.com/api/popular",
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

    /**
     * 最初の案内に並べる、その国でいま人気の動画。
     *
     * まず当方のサーバー（[popularUrl]・Cloudflare）から読む。サーバーが国ごとに1時間だけ持っているので、
     * 利用者が何人いても・何度入れ直しても、アプリの quota は使わない（2026-10-05・ユーザー判断）。
     * 送るのは2文字の国コードだけ。サーバーが落ちているときだけ、直接 YouTube に問い合わせる（quota 1）。
     */
    suspend fun fetchPopularVideos(regionCode: String?): List<PopularVideo> {
        val region = regionCode?.uppercase()?.takeIf { it.matches(Regex("[A-Z]{2}")) }
        val fromServer = runCatching {
            val url = Uri.parse(popularUrl).buildUpon()
                .apply { if (region != null) appendQueryParameter("region", region) }
                .build().toString()
            val body = withContext(Dispatchers.IO) {
                httpClient.newCall(Request.Builder().url(url).get().build()).execute().use { response ->
                    if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
                    response.body?.string().orEmpty()
                }
            }
            popularFromServer(json.parseToJsonElement(body).jsonObject)
        }.onFailure { Log.w("YouTubeApiClient", "popular server unavailable: ${it.message}") }
            .getOrNull()
        if (!fromServer.isNullOrEmpty()) return fromServer
        return fetchPopularVideosDirect(region)
    }

    /**
     * YouTube に直接問い合わせる（chart=mostPopular・quota 1）。サーバーが使えないときの予備。
     * 国に対応していない（400 など）ときは国を指定せずに取り直す。同じチャンネルは1本だけにする。
     */
    private suspend fun fetchPopularVideosDirect(regionCode: String?, maxResults: Int = 50): List<PopularVideo> {
        val base = listOf("part" to "snippet", "chart" to "mostPopular", "maxResults" to maxResults.toString())
        val body = if (regionCode.isNullOrBlank()) {
            getJson("videos", base)
        } else {
            runCatching { getJson("videos", base + ("regionCode" to regionCode)) }
                .getOrElse { getJson("videos", base) }
        }
        return popularVideos(body)
    }

    /** videoId からその動画を投稿したチャンネルの channelId を取得する（videos.list / quota 1）。 */
    suspend fun fetchChannelIdForVideo(videoId: String): String {
        if (!ChannelResolver.isVideoId(videoId)) throw YouTubeApiException(YouTubeApiError.InvalidVideoUrl)
        val body = getJson("videos", listOf("part" to "snippet", "id" to videoId))
        return channelIdFromVideosList(body)
    }

    /**
     * uploads プレイリストから全動画を取得し、古い順（publishedAt 昇順）で返す。
     *
     * @param onProgress 1ページ読むごとに（読んだ本数, 全体の本数）。全体は最初のページの
     *   pageInfo.totalResults（追加の quota なし）で、上限（[maxPages] × 50）で頭打ちにする。
     */
    suspend fun fetchVideos(
        playlistId: String,
        onProgress: (loaded: Int, total: Int) -> Unit = { _, _ -> },
    ): List<VideoItem> {
        val all = mutableListOf<VideoItem>()
        var token: String? = null
        var page = 0
        var total = 0
        do {
            val result = fetchVideosPage(playlistId, token)
            all += result.items
            token = result.nextPageToken
            page += 1
            if (total == 0) total = minOf(result.totalResults ?: 0, maxPages * 50)
            if (total > 0) onProgress(minOf(all.size, total), total)
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
    /**
     * 視聴回数（statistics.viewCount）を 50 本ずつ取る（1回 = quota 1）。
     * 視聴回数を非公開にしている動画は結果に含まれない。
     */
    suspend fun fetchViewCounts(videoIds: List<String>): Map<String, Long> {
        val counts = mutableMapOf<String, Long>()
        for (chunk in videoIds.chunked(50)) {
            val body = getJson(
                "videos",
                listOf("part" to "statistics", "id" to chunk.joinToString(","), "maxResults" to "50"),
            )
            counts.putAll(viewCounts(body))
        }
        return counts
    }

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

        val request = Request.Builder().url(url).get().apply {
            appIdentity?.let {
                addHeader("X-Android-Package", it.packageName)
                addHeader("X-Android-Cert", it.signatureSha1)
            }
        }.build()

        val (code, body) = withContext(Dispatchers.IO) {
            try {
                httpClient.newCall(request).execute().use { response ->
                    response.code to (response.body?.string().orEmpty())
                }
            } catch (e: IOException) {
                throw YouTubeApiException(YouTubeApiError.NetworkError)
            }
        }

        if (code !in 200..299) {
            // 原因の切り分け用（APIキーそのものは出力しない）。
            Log.w("YouTubeApiClient", "HTTP $code / $path / ${body.take(300)}")
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

        /** 当方のサーバー（/api/popular）の答え `{ region, items: [...] }` を読む。 */
        fun popularFromServer(body: JsonObject): List<PopularVideo> =
            body["items"]?.jsonArray.orEmpty().mapNotNull { element ->
                val item = element.jsonObject
                PopularVideo(
                    videoId = item.string("videoId") ?: return@mapNotNull null,
                    title = item.string("title") ?: UNTITLED_VIDEO,
                    channelId = item.string("channelId") ?: return@mapNotNull null,
                    channelTitle = item.string("channelTitle") ?: UNTITLED_CHANNEL,
                    thumbnailUrl = item.string("thumbnailUrl"),
                )
            }.distinctBy { it.channelId }

        /** chart=mostPopular のレスポンスを読む（ネットワーク非依存＝テスト可能）。同じチャンネルは最初の1本だけ。 */
        fun popularVideos(body: JsonObject): List<PopularVideo> =
            body["items"]?.jsonArray.orEmpty().mapNotNull { element ->
                val item = element.jsonObject
                val snippet = item["snippet"]?.jsonObject ?: return@mapNotNull null
                val videoId = item.string("id") ?: return@mapNotNull null
                val channelId = snippet.string("channelId") ?: return@mapNotNull null
                PopularVideo(
                    videoId = videoId,
                    title = snippet.string("title") ?: UNTITLED_VIDEO,
                    channelId = channelId,
                    channelTitle = snippet.string("channelTitle") ?: UNTITLED_CHANNEL,
                    thumbnailUrl = bestThumbnail(snippet),
                )
            }.distinctBy { it.channelId }

        /** videos.list のレスポンスから channelId を取り出す（ネットワーク非依存＝テスト可能）。 */
        fun channelIdFromVideosList(body: JsonObject): String {
            val channelId = body["items"]?.jsonArray?.firstOrNull()?.jsonObject
                ?.get("snippet")?.jsonObject?.string("channelId")
            if (channelId.isNullOrEmpty()) throw YouTubeApiException(YouTubeApiError.VideoNotFound)
            return channelId
        }

        /** videos.list（statistics）のレスポンスから {videoId: 視聴回数} を取り出す（テスト可能）。 */
        fun viewCounts(body: JsonObject): Map<String, Long> =
            body["items"]?.jsonArray.orEmpty().mapNotNull { element ->
                val item = element.jsonObject
                val id = item.string("id") ?: return@mapNotNull null
                val count = item["statistics"]?.jsonObject?.string("viewCount")?.toLongOrNull()
                    ?: return@mapNotNull null
                id to count
            }.toMap()

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
            val total = runCatching {
                body["pageInfo"]?.jsonObject?.get("totalResults")?.jsonPrimitive?.content?.toInt()
            }.getOrNull()
            return VideoPage(items, body.string("nextPageToken"), total)
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
            // JSON の null は文字列 "null" にしない（サーバーの答えではサムネイルが null のことがある）。
            runCatching { this[key]?.takeUnless { it is kotlinx.serialization.json.JsonNull }?.jsonPrimitive?.content }
                .getOrNull()
    }
}
