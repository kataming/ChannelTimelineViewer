package com.deskflowlabs.channeltimelineviewer.data

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 利用状況の記録（Google Analytics for Firebase）を許可するか。**Android 版のみ**の設定。
 *
 * 既定はオン。「このアプリについて」の切り替えでいつでもオフにできる（オプトアウト）。
 * オフにすると Firebase 側の計測を丸ごと止めるので、以降は何も送られない。
 *
 * 保存するのはこの真偽値だけで、他のストアと同じく端末の中から出ない。
 */
class AnalyticsSettingsStore(private val prefs: SharedPreferences) {

    private val key = "setting_analytics_enabled_v1"

    private val _isEnabled = MutableStateFlow(prefs.getBoolean(key, DEFAULT_ENABLED))
    val isEnabled: StateFlow<Boolean> = _isEnabled.asStateFlow()

    fun setEnabled(value: Boolean) {
        _isEnabled.value = value
        prefs.edit().putBoolean(key, value).apply()
    }

    companion object {
        /** 既定値。オフにしたい人が自分で切れる形（オプトアウト）にしている。 */
        const val DEFAULT_ENABLED = true
    }
}
