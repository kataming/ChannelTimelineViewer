package com.deskflowlabs.channeltimelineviewer.analytics

import android.content.Context
import android.os.Bundle
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics

/**
 * [Analytics] の Firebase 実装。
 *
 * `app/google-services.json` があるビルドだけ Firebase が初期化されるので、
 * 生成は [create] から行い、初期化されていなければ [Analytics.Noop] を返す。
 * こうしておくと、設定ファイルを置いていない端末・CI でも今までどおり動く。
 */
class FirebaseAnalyticsTracker private constructor(
    private val firebase: FirebaseAnalytics,
) : Analytics {

    override fun setCollectionEnabled(enabled: Boolean) {
        // Firebase 側がこの値を端末に覚えるので、次回起動時は呼ぶ前から反映されている。
        firebase.setAnalyticsCollectionEnabled(enabled)
    }

    override fun logScreen(screenName: String) {
        log(FirebaseAnalytics.Event.SCREEN_VIEW, FirebaseAnalytics.Param.SCREEN_NAME to screenName)
    }

    override fun log(event: String, vararg params: Pair<String, Any>) {
        firebase.logEvent(event, params.toBundle())
    }

    private fun Array<out Pair<String, Any>>.toBundle(): Bundle? {
        if (isEmpty()) return null
        return Bundle().apply {
            forEach { (key, value) ->
                when (value) {
                    is String -> putString(key, value)
                    is Int -> putLong(key, value.toLong())
                    is Long -> putLong(key, value)
                    is Double -> putDouble(key, value)
                    is Boolean -> putString(key, Analytics.onOff(value))
                    // 上以外は Firebase が受け取れないので、文字にして落とさないようにする。
                    else -> putString(key, value.toString())
                }
            }
        }
    }

    companion object {
        private const val TAG = "Analytics"

        /**
         * 使える状態なら Firebase 実装を、そうでなければ [Analytics.Noop] を返す。
         *
         * [enabled] はユーザーの設定（既定はオン）。オフのまま作った場合も
         * `setAnalyticsCollectionEnabled(false)` を呼んでおき、状態を確実に合わせる。
         */
        fun create(context: Context, enabled: Boolean): Analytics {
            // google-services.json が無いと FirebaseApp は初期化されない（＝計測しない）。
            if (FirebaseApp.getApps(context).isEmpty()) {
                Log.i(TAG, "Firebase is not configured; analytics disabled.")
                return Analytics.Noop
            }
            val tracker = runCatching {
                FirebaseAnalyticsTracker(FirebaseAnalytics.getInstance(context.applicationContext))
            }.getOrElse {
                Log.w(TAG, "Failed to start Firebase Analytics; analytics disabled.", it)
                return Analytics.Noop
            }
            tracker.setCollectionEnabled(enabled)
            return tracker
        }
    }
}
