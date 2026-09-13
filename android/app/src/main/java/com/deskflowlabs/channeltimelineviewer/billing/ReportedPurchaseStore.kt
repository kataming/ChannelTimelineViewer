package com.deskflowlabs.channeltimelineviewer.billing

import android.content.SharedPreferences
import java.security.MessageDigest

/**
 * 「この購入はもう実売として数えた」を端末に控えておく入れ物。
 *
 * なぜ要るか: Play は同じ購入を何度も通知してくる。`onPurchasesUpdated` は再接続や
 * acknowledge の前後で重ねて呼ばれることがあり、そのたびに実売を数えると**売上が水増し**される。
 * ここで1回だけに絞る。
 *
 * ⚠️ **purchaseToken そのものは保存しない。** SHA-256 にしてから持つ。
 * Analytics へは、ハッシュ化したものも含めて**一切送らない**（照合は端末の中だけ）。
 *
 * 端末内の他のストアと同じく SharedPreferences に置く。アプリを消せば一緒に消えるが、
 * その場合は購入も再取得（復元）になり、復元では実売を数えないので二重計上にはならない。
 */
class ReportedPurchaseStore(private val prefs: SharedPreferences) {

    private val key = "pro_reported_purchases_v1"

    /**
     * まだ数えていない購入なら控えて true、すでに数えていれば false。
     *
     * 「確認してから書く」を1つにまとめてあるので、呼ぶ側は戻り値を見るだけでよい。
     */
    fun reportOnce(purchaseToken: String): Boolean {
        if (purchaseToken.isBlank()) return false
        val digest = hash(purchaseToken)
        val saved = prefs.getStringSet(key, emptySet()).orEmpty()
        if (digest in saved) return false

        // 際限なく増えないよう、古いものから落として上限を守る。
        // 買い切り1商品なので実際には1件しか入らないが、再購入（返金後など）に備える。
        val updated = (saved + digest).let {
            if (it.size <= MAX_ENTRIES) it else it.toList().takeLast(MAX_ENTRIES).toSet()
        }
        prefs.edit().putStringSet(key, updated).apply()
        return true
    }

    /** すでに数えた購入か（書き込まずに見るだけ）。 */
    fun isReported(purchaseToken: String): Boolean =
        purchaseToken.isNotBlank() &&
            hash(purchaseToken) in prefs.getStringSet(key, emptySet()).orEmpty()

    private fun hash(value: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }

    private companion object {
        const val MAX_ENTRIES = 20
    }
}
