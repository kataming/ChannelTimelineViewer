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
 * - `autoPlayNext`: 再生終了時に一覧の次の動画を続けて再生する（**既定オン**・2026-09-16 変更）
 *
 * 自動再生が進む先は**ユーザーが開いたチャンネル一覧の中の「次の動画」だけ**で、YouTube の
 * 関連動画・おすすめへは進まない。再生画面の「自動再生」トグルでいつでもオフにできる。
 * バックグラウンド再生は行わない。
 *
 * ⚠️ **既定値は「まだ一度も操作していない人」にだけ効く。**
 * 保存はユーザーが操作したときだけ行うので、キーの有無で「未操作」と「自分で選んだ」を見分けられる。
 * 自分でオフにした人は**オフのまま**、オンにした人は**オンのまま**引き継がれ、既定値の変更で
 * 上書きされることはない（`getBoolean` の第2引数はキーが無いときだけ使われる）。
 */
class PlaybackSettingsStore(private val prefs: SharedPreferences) {

    private val resumeKey = "setting_resume_from_last_position_v1"
    private val autoPlayNextKey = "setting_autoplay_next_v1"
    private val repeatModeKey = "setting_repeat_mode_v1"
    private val unwatchedOnlyKey = "setting_play_unwatched_only_v1"

    private val _resumeFromLastPosition = MutableStateFlow(prefs.getBoolean(resumeKey, true))
    val resumeFromLastPosition: StateFlow<Boolean> = _resumeFromLastPosition.asStateFlow()

    // 既定オン。自分で切り替えた人はキーが保存されているので、その選択がそのまま使われる。
    private val _autoPlayNext = MutableStateFlow(prefs.getBoolean(autoPlayNextKey, true))
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
