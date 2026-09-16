package com.deskflowlabs.channeltimelineviewer.data

import android.content.SharedPreferences
import androidx.core.content.edit
import com.deskflowlabs.channeltimelineviewer.network.WatchQueue
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueEntitlement
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueError
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueException
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueSyncClient
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Watch Queue V2 の状態（この端末の接続と、キューの写し）。
 *
 * 守っていること:
 * - **Feature Flag が OFF のあいだは、何も見せない・何も送らない**。一度も取れていないときも OFF 扱い。
 * - 保存チャンネル・視聴記録・メモ・再生位置・購入状態には一切触れない（読むのは購入状態だけ）。
 * - 端末トークンはアプリ専用の SharedPreferences にだけ置き、画面にもログにも出さない
 *   （iOS は Keychain。Android はライブラリを増やさないため、他の保存物と同じアプリ専用領域に置く）。
 */
class WatchQueueStore(
    private val prefs: SharedPreferences,
    private val client: WatchQueueSyncClient = WatchQueueSyncClient(),
) {
    private companion object {
        const val KEY_TOKEN = "watch_queue_token_v1"
        const val KEY_GROUP = "watch_queue_group_v1"
        const val KEY_ENABLED = "watch_queue_enabled_cache_v1"

        /** この版が Watch Queue V2 を積んでいるか（ビルド時の安全弁）。 */
        const val BUILD_SUPPORTS_V2 = true
    }

    private val _remoteEnabled = MutableStateFlow(prefs.getBoolean(KEY_ENABLED, false))
    val remoteEnabled: StateFlow<Boolean> = _remoteEnabled.asStateFlow()

    private val _queues = MutableStateFlow<List<WatchQueue>>(emptyList())
    val queues: StateFlow<List<WatchQueue>> = _queues.asStateFlow()

    private val _entitlement = MutableStateFlow<WatchQueueEntitlement?>(null)
    val entitlement: StateFlow<WatchQueueEntitlement?> = _entitlement.asStateFlow()

    private val _isPaired = MutableStateFlow(prefs.getString(KEY_TOKEN, null) != null)
    val isPaired: StateFlow<Boolean> = _isPaired.asStateFlow()

    private var token: String? = prefs.getString(KEY_TOKEN, null)

    /** 画面に Watch Queue を出してよいか。ビルドとサーバーの両方が有効なときだけ。 */
    val isAvailable: Boolean get() = BUILD_SUPPORTS_V2 && _remoteEnabled.value

    /** 起動時と前面復帰時に呼ぶ。取れなければ最後の値のままにする（勝手に ON にしない）。 */
    suspend fun refreshAvailability() {
        if (!BUILD_SUPPORTS_V2) return
        try {
            val config = client.fetchConfig()
            _remoteEnabled.value = config.enabled
            prefs.edit { putBoolean(KEY_ENABLED, config.enabled) }
            if (!config.enabled) {
                // OFF になったら、画面に残っている写しも消して V2 以前の状態に戻す。
                _queues.value = emptyList()
                _entitlement.value = null
            }
        } catch (e: WatchQueueException) {
            // 取れないときは何も変えない。未取得なら false のまま＝出さない。
        }
    }

    /** 拡張に表示された8文字のコードで接続する。大文字小文字・空白・ハイフンは気にしなくてよい。 */
    suspend fun pair(code: String): WatchQueueError? {
        if (!isAvailable) return WatchQueueError.DISABLED
        val normalized = code.uppercase().filter { it.isLetterOrDigit() }
        if (normalized.length < 6) return WatchQueueError.CODE
        return try {
            val pairing = client.claim(normalized, token)
            pairing.deviceToken?.let { newToken ->
                token = newToken
                prefs.edit { putString(KEY_TOKEN, newToken) }
            }
            prefs.edit { putString(KEY_GROUP, pairing.groupId) }
            _isPaired.value = token != null
            loadQueues()
        } catch (e: WatchQueueException) {
            e.error
        }
    }

    /** キューを読み直す。失敗した理由を返す（成功なら null）。 */
    suspend fun loadQueues(): WatchQueueError? {
        val current = token ?: return null
        if (!isAvailable) return null
        return try {
            val list = client.fetchQueues(current)
            _queues.value = list.queues
            _entitlement.value = list.entitlement
            null
        } catch (e: WatchQueueException) {
            if (e.error == WatchQueueError.UNAUTHORIZED) forgetPairingLocally()
            e.error
        }
    }

    /** 購入状態の写しを渡す。判定の正本は Google Play 側で、ここでは伝えるだけ。 */
    suspend fun reportEntitlement(isPro: Boolean, channelCount: Int) {
        val current = token ?: return
        if (!isAvailable) return
        try {
            _entitlement.value = client.reportEntitlement(current, isPro, channelCount) ?: _entitlement.value
        } catch (e: WatchQueueException) {
            // 伝えられなくても、アプリの購入状態と使い勝手は変わらない。
        }
    }

    /** 接続を解除する。**ローカルの保存（チャンネル・視聴記録・購入）は何も消さない。** */
    suspend fun disconnect() {
        token?.let { current ->
            try {
                client.revokeSelf(current)
            } catch (e: WatchQueueException) {
                // サーバーに伝えられなくても、この端末からは外す。
            }
        }
        forgetPairingLocally()
    }

    fun queueById(queueId: String): WatchQueue? = _queues.value.firstOrNull { it.queueId == queueId }

    private fun forgetPairingLocally() {
        token = null
        _isPaired.value = false
        _queues.value = emptyList()
        _entitlement.value = null
        prefs.edit {
            remove(KEY_TOKEN)
            remove(KEY_GROUP)
        }
    }
}
