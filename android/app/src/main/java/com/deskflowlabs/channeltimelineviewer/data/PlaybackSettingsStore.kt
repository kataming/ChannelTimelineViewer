package com.deskflowlabs.channeltimelineviewer.data

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 繰り返し再生の種類。 */
enum class RepeatMode {
    /** 繰り返さない（既定）。 */
    Off,

    /** いま再生している動画を繰り返す。 */
    One,

    /** 一覧の最後まで行ったら先頭に戻る（自動再生がオンのときに働く）。 */
    All;

    /** ボタンを押したときの次の状態（オフ → 1本 → 全体 → オフ）。 */
    val next: RepeatMode
        get() = when (this) {
            Off -> One
            One -> All
            All -> Off
        }

    /** リピートが働いている状態か（バッジを塗りつぶすかの判断に使う）。 */
    val isActive: Boolean get() = this != Off

    /** 記号の中央に重ねる文字（オフは無し）。 */
    val centerLabel: String?
        get() = when (this) {
            Off -> null
            One -> "1"
            All -> "ALL"
        }
}

/**
 * 再生に関するユーザー設定（端末内に保存）。iOS 版 `Services/PlaybackSettingsStore.swift` の移植。
 *
 * - `resumeFromLastPosition`: 前回停止した位置から再生する（**既定オン**）
 * - `autoPlayNext`: 再生終了時に一覧の次の動画を続けて再生する（**既定オフ＝任意機能**）
 *
 * 自動再生は既定オフで、**ユーザーが再生画面のトグルで明示的にオンにしたときだけ**有効になる。
 * 対象は**ユーザーが開いたチャンネル一覧の中の「次の動画」だけ**で、YouTube の関連動画・
 * おすすめへは進まない。バックグラウンド再生は行わない。
 *
 * 保存は「ユーザーが操作したときだけ」行う。未操作の端末には値が保存されず、
 * アップデートで既定値が変わっても**勝手にオンにはならない**。
 */
class PlaybackSettingsStore(private val prefs: SharedPreferences) {

    private val resumeKey = "setting_resume_from_last_position_v1"
    private val autoPlayNextKey = "setting_autoplay_next_v1"
    private val repeatModeKey = "setting_repeat_mode_v1"
    private val unwatchedOnlyKey = "setting_play_unwatched_only_v1"

    private val _resumeFromLastPosition = MutableStateFlow(prefs.getBoolean(resumeKey, true))
    val resumeFromLastPosition: StateFlow<Boolean> = _resumeFromLastPosition.asStateFlow()

    private val _autoPlayNext = MutableStateFlow(prefs.getBoolean(autoPlayNextKey, false))
    val autoPlayNext: StateFlow<Boolean> = _autoPlayNext.asStateFlow()

    private val _repeatMode = MutableStateFlow(
        runCatching { RepeatMode.valueOf(prefs.getString(repeatModeKey, null) ?: "Off") }
            .getOrDefault(RepeatMode.Off)
    )
    val repeatMode: StateFlow<RepeatMode> = _repeatMode.asStateFlow()

    private val _playUnwatchedOnly = MutableStateFlow(prefs.getBoolean(unwatchedOnlyKey, false))
    val playUnwatchedOnly: StateFlow<Boolean> = _playUnwatchedOnly.asStateFlow()

    fun setResumeFromLastPosition(value: Boolean) {
        _resumeFromLastPosition.value = value
        prefs.edit().putBoolean(resumeKey, value).apply()
    }

    fun setAutoPlayNext(value: Boolean) {
        _autoPlayNext.value = value
        prefs.edit().putBoolean(autoPlayNextKey, value).apply()
    }

    fun setRepeatMode(value: RepeatMode) {
        _repeatMode.value = value
        prefs.edit().putString(repeatModeKey, value.name).apply()
    }

    /** ボタンを押したときに次の状態へ進める。 */
    fun cycleRepeatMode(): RepeatMode {
        val next = _repeatMode.value.next
        setRepeatMode(next)
        return next
    }

    fun setPlayUnwatchedOnly(value: Boolean) {
        _playUnwatchedOnly.value = value
        prefs.edit().putBoolean(unwatchedOnlyKey, value).apply()
    }
}
