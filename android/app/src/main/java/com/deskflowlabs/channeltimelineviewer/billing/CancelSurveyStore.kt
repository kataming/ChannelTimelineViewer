package com.deskflowlabs.channeltimelineviewer.billing

import android.content.SharedPreferences

/**
 * 購入をやめた直後の一問アンケート（2026-10-02・Android 1.16〜）を、出しすぎないための控え。
 *
 * 目的: Purchase Start は多いのに Purchase Success が 0 件。Play はキャンセルの理由
 * （支払い方法が無い・価格・あとで）をアプリに教えないため、本人に一度だけ聞いて切り分ける。
 *
 * - 同じ端末では [INTERVAL_MILLIS]（7 日）に 1 回まで。キャンセルのたびに聞くとしつこいため
 * - 控えるのは「最後に聞いた時刻」だけ。回答の中身は端末に残さない
 */
class CancelSurveyStore(
    private val prefs: SharedPreferences,
    private val now: () -> Long = System::currentTimeMillis,
) {

    private val key = "pro_cancel_survey_last_asked_v1"

    /** 今聞いてよければ、聞いた時刻を控えて true。前回から 7 日たっていなければ false。 */
    fun tryAsk(): Boolean {
        val current = now()
        val last = prefs.getLong(key, 0L)
        // 端末の時計が戻された（last が未来）ときも聞かない
        if (last != 0L && (current - last < INTERVAL_MILLIS || last > current)) return false
        prefs.edit().putLong(key, current).apply()
        return true
    }

    companion object {
        const val INTERVAL_MILLIS = 7L * 24 * 60 * 60 * 1000
    }
}
