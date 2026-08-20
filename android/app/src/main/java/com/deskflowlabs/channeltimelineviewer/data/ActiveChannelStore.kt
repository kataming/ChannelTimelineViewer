package com.deskflowlabs.channeltimelineviewer.data

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 無料の枠で「いま使うチャンネル」。
 *
 * Pro を持っている間は使わない。Pro が外れて保存済みが上限を超えているとき、
 * どれを開けるようにするかをここで覚える（残りはロックされるが、記録は消さない）。
 */
class ActiveChannelStore(private val prefs: SharedPreferences) {

    private val key = "active_channel_v1"

    private val _activeChannelId = MutableStateFlow(prefs.getString(key, null))
    val activeChannelId: StateFlow<String?> = _activeChannelId.asStateFlow()

    fun set(channelId: String) {
        if (_activeChannelId.value == channelId) return
        _activeChannelId.value = channelId
        prefs.edit().putString(key, channelId).apply()
    }
}
