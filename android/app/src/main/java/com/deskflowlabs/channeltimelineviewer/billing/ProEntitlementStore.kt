package com.deskflowlabs.channeltimelineviewer.billing

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Pro（買い切り）を持っているかどうかの保持。
 *
 * 正は常に Google Play 側の購入情報で、ここに持つのは**その写し**でしかない。
 * 圏外や Play に繋がらない状況で Pro が消えると困るので、
 * 「Play に問い合わせて成功し、購入が無かった」ときだけ false に落とす。
 */
class ProEntitlementStore(private val prefs: SharedPreferences) {

    private val key = "pro_unlocked_v1"

    private val _isPro = MutableStateFlow(prefs.getBoolean(key, false))
    val isPro: StateFlow<Boolean> = _isPro.asStateFlow()

    /** 購入が確認できた（購入直後・復元時）。 */
    fun grant() = write(true)

    /**
     * Play への問い合わせが**成功した**ときだけ呼ぶ。
     * 通信に失敗したときに呼ぶと、オフラインで Pro が消えてしまう。
     *
     * @param hasEntitlement Play が返した購入一覧に Pro があったか
     */
    fun applyPlayQuery(hasEntitlement: Boolean) = write(hasEntitlement)

    private fun write(value: Boolean) {
        if (_isPro.value == value) return
        _isPro.value = value
        prefs.edit().putBoolean(key, value).apply()
    }
}
