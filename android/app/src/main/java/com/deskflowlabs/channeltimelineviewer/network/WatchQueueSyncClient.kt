package com.deskflowlabs.channeltimelineviewer.network

import com.deskflowlabs.channeltimelineviewer.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Watch Queue V2 同期 API のクライアント（Android 側）。
 *
 * 送るもの: ペアリングのコード・端末トークン・端末の種別とバージョン・購入状態の写し。
 * 送らないもの: Google アカウント情報・視聴履歴・保存チャンネル・メモ・再生位置。
 *
 * 応答は org.json で手ずから読む。R8（難読化）の設定に左右されないようにするため。
 */
enum class WatchQueueError {
    NETWORK,
    DISABLED,        // サーバー側の Feature Flag が OFF（503）
    UNAUTHORIZED,    // 端末が失効している（401/403）
    CODE,            // コードが見つからない（404）
    EXPIRED,         // 期限切れ（410）
    USED,            // 使用済み（409）
    TOO_MANY,        // 試行しすぎ・レート制限（429）
    GENERIC,
}

class WatchQueueException(val error: WatchQueueError) : Exception(error.name)

data class WatchQueueConfig(
    val enabled: Boolean,
    val contractVersion: Int,
    val maxQueues: Int,
    val maxItems: Int,
)

data class WatchQueuePairing(val groupId: String, val deviceToken: String?)

data class WatchQueueItem(
    val videoId: String,
    val title: String,
    val channelName: String,
)

data class WatchQueue(
    val queueId: String,
    val name: String,
    val version: Int,
    val items: List<WatchQueueItem>,
)

data class WatchQueueEntitlement(
    val isPro: Boolean,
    val channelCount: Int,
    val queueCount: Int,
    val total: Int,
    val canCreateAnother: Boolean,
)

data class WatchQueueList(val queues: List<WatchQueue>, val entitlement: WatchQueueEntitlement?)

class WatchQueueSyncClient(
    private val baseUrl: String = DEFAULT_BASE_URL,
    private val httpClient: OkHttpClient = defaultClient,
    private val clientVersion: String = BuildConfig.VERSION_NAME,
) {
    companion object {
        /** 同期サーバー（Chrome 拡張・Web VIEWER・iOS と同じ場所）。 */
        const val DEFAULT_BASE_URL = "https://watch-queue-sync.atamitrading.workers.dev"

        /** この版が扱える機能。サーバーはこれを見て V2 対応クライアントだと判断する。 */
        const val CAPABILITIES = "watch_queue_v2"

        private val JSON = "application/json; charset=utf-8".toMediaType()

        private val defaultClient: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(20, TimeUnit.SECONDS)
                .build()
        }
    }

    /** Feature Flag と上限値。ペアリング前でも呼べる唯一のエンドポイント。 */
    suspend fun fetchConfig(): WatchQueueConfig {
        val json = request("/v2/config", "GET", token = null, body = null)
        return WatchQueueConfig(
            enabled = json.optBoolean("watchQueueV2Enabled", false),
            contractVersion = json.optInt("contractVersion", 0),
            maxQueues = json.optInt("maxQueues", 0),
            maxItems = json.optInt("maxItems", 0),
        )
    }

    /** 拡張に出ているコードを入力して、同じグループに入る。 */
    suspend fun claim(code: String, existingToken: String?): WatchQueuePairing {
        val body = JSONObject()
            .put("code", code)
            .put("platform", "android")
            .put("capabilities", CAPABILITIES)
            .put("clientVersion", clientVersion)
        if (!existingToken.isNullOrBlank()) body.put("deviceToken", existingToken)

        val json = request("/v2/pairing/claim", "POST", token = null, body = body)
        return WatchQueuePairing(
            groupId = json.optString("groupId"),
            deviceToken = json.optString("deviceToken").takeIf { it.isNotBlank() },
        )
    }

    /** このグループのキュー一式（並び順はサーバーが position 順で返す）。 */
    suspend fun fetchQueues(token: String): WatchQueueList {
        val json = request("/v2/queues", "GET", token = token, body = null)
        val queues = mutableListOf<WatchQueue>()
        val array = json.optJSONArray("queues")
        for (i in 0 until (array?.length() ?: 0)) {
            val queue = array!!.getJSONObject(i)
            val items = mutableListOf<WatchQueueItem>()
            val rawItems = queue.optJSONArray("items")
            for (j in 0 until (rawItems?.length() ?: 0)) {
                val item = rawItems!!.getJSONObject(j)
                val videoId = item.optString("videoId")
                if (videoId.isBlank()) continue
                items += WatchQueueItem(
                    videoId = videoId,
                    title = item.optString("title"),
                    channelName = item.optString("channelName"),
                )
            }
            queues += WatchQueue(
                queueId = queue.optString("queueId"),
                name = queue.optString("name"),
                version = queue.optInt("version", 0),
                items = items,
            )
        }
        return WatchQueueList(queues, parseEntitlement(json.optJSONObject("entitlement")))
    }

    /** 購入状態の写しを渡す（判定の正本は Google Play の購入。拡張は自己申告できない）。 */
    suspend fun reportEntitlement(token: String, isPro: Boolean, channelCount: Int): WatchQueueEntitlement? {
        val body = JSONObject().put("isPro", isPro).put("channelCount", channelCount)
        return parseEntitlement(request("/v2/entitlement", "POST", token = token, body = body))
    }

    /** この端末の接続を解除する（サーバー側で失効させる）。 */
    suspend fun revokeSelf(token: String) {
        request("/v2/devices/revoke", "POST", token = token, body = JSONObject())
    }

    private fun parseEntitlement(json: JSONObject?): WatchQueueEntitlement? {
        if (json == null) return null
        return WatchQueueEntitlement(
            isPro = json.optBoolean("isPro", false),
            channelCount = json.optInt("channelCount", 0),
            queueCount = json.optInt("queueCount", 0),
            total = json.optInt("total", 0),
            canCreateAnother = json.optBoolean("canCreateAnother", false),
        )
    }

    private suspend fun request(path: String, method: String, token: String?, body: JSONObject?): JSONObject =
        withContext(Dispatchers.IO) {
            val builder = Request.Builder()
                .url(baseUrl + path)
                .header("x-client-version", clientVersion)
            if (token != null) builder.header("authorization", "Bearer $token")
            when (method) {
                "POST" -> builder.post((body ?: JSONObject()).toString().toRequestBody(JSON))
                else -> builder.get()
            }

            val response = try {
                httpClient.newCall(builder.build()).execute()
            } catch (e: Exception) {
                throw WatchQueueException(WatchQueueError.NETWORK)
            }

            response.use {
                val text = it.body?.string().orEmpty()
                val json = try {
                    if (text.isBlank()) JSONObject() else JSONObject(text)
                } catch (e: Exception) {
                    JSONObject()
                }
                if (!it.isSuccessful) throw WatchQueueException(errorFor(it.code, json.optString("error")))
                json
            }
        }

    private fun errorFor(status: Int, code: String?): WatchQueueError = when {
        status == 400 -> WatchQueueError.GENERIC
        status == 401 || status == 403 -> WatchQueueError.UNAUTHORIZED
        status == 404 -> WatchQueueError.CODE
        status == 409 -> WatchQueueError.USED
        status == 410 -> WatchQueueError.EXPIRED
        status == 429 -> WatchQueueError.TOO_MANY
        status == 503 && code == "disabled" -> WatchQueueError.DISABLED
        status >= 500 -> WatchQueueError.GENERIC
        else -> WatchQueueError.GENERIC
    }
}
