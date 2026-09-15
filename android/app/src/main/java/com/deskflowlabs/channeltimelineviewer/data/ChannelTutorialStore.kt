package com.deskflowlabs.channeltimelineviewer.data

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * 「チャンネルの追加方法」のチュートリアルを見終わったか。
 *
 * 出す条件は「初めてチャンネルを追加しようとしたとき」だけ。起動のたびに出さない。
 * スキップも見終わったのと同じ扱いにする（**同じ案内を二度出さない**。
 * 出し続けると、分かっている人にとっては邪魔でしかない）。
 *
 * 他のストアと同じく端末の中だけに持つ。アプリを消せば一緒に消えるので、
 * 入れ直した人には新しい利用者として、もう一度出る。
 */
class ChannelTutorialStore(private val prefs: SharedPreferences) {

    private val key = "channel_tutorial_completed_v1"

    private val _isCompleted = MutableStateFlow(prefs.getBoolean(key, false))
    val isCompleted: StateFlow<Boolean> = _isCompleted.asStateFlow()

    /**
     * 見終わった（またはスキップした）。
     *
     * 「このアプリについて」から自分で開き直したときは**呼ばない**。
     * 手で見直しただけで状態が変わると、説明が要る人かどうかの区別がつかなくなる。
     */
    fun markCompleted() {
        if (_isCompleted.value) return
        _isCompleted.value = true
        prefs.edit().putBoolean(key, true).apply()
    }
}
