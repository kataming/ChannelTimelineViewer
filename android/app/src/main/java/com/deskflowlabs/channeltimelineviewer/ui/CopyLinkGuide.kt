package com.deskflowlabs.channeltimelineviewer.ui

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.deskflowlabs.channeltimelineviewer.MainActivity
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.network.SharedLinkParser

/**
 * 「YouTube の共有から追加する」を、共有メニューの中から本アプリを探さなくても済むようにする仕組み
 * （2026-10-05・ユーザー判断）。
 *
 * 1. 案内の [YouTube を開く] で YouTube を開き、同時に「アプリに戻る」の通知を出す
 *    （開く前にコピーされていたリンクを控える）
 * 2. 利用者は YouTube で［共有］→［コピー］を押し、通知を押してこのアプリへ戻る
 *    （戻るボタン・最近使ったアプリから戻っても同じように開く）
 * 3. 戻ったとき、新しくコピーされた YouTube のリンクを読んで、そのチャンネルを開く
 *
 * 通知は**押されるまで消さない**（2026-10-05 ユーザー指定）。スワイプでも消えない。
 * ただし画面上部のポップアップは数秒で引っ込む（Android の決まりで変えられない）ので、
 * そのあとは通知の一覧を引き下ろして押してもらう。チャンネルを開いたら自動で消す。
 *
 * クリップボードを読むのは**このアプリが前面にあるときだけ**。読むのは YouTube の URL だけで、
 * それ以外の内容は使わず、どこにも送らない。
 */
object CopyLinkGuide {

    /** 通知から戻ってきたことを示す Intent の action。 */
    const val ACTION_FROM_GUIDE = "com.deskflowlabs.channeltimelineviewer.action.FROM_COPY_GUIDE"

    // 無音で出し直すため、最初の版（音あり）とは別のチャンネルにする（チャンネルの音はあとから変えられない）。
    private const val CHANNEL_ID = "copy_link_guide_silent"
    // 画面の端のボタン（[CopyGuideOverlay]）を出しているときの通知。上部にポップアップを出さない。
    private const val QUIET_CHANNEL_ID = "copy_link_guide_quiet"
    const val NOTIFICATION_ID = 4101

    /** Android 13 以降は通知の許可が要る。 */
    fun needsPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED

    /** 出し直しの間隔と、出し直しを続ける時間（2026-10-05 ユーザーと試して決める・まずは 8 秒ごと 2 分）。 */
    const val REPEAT_EVERY_MILLIS = 8_000L
    const val REPEAT_FOR_MILLIS = 2 * 60_000L

    /**
     * 「アプリに戻る」の通知を出す。許可が無ければ何もしない（戻るボタンで戻れば同じように開く）。
     *
     * 画面上部のポップアップは数秒で引っ込む（Android の決まり）ので、[CopyGuideService] が
     * アプリに戻るまで [REPEAT_EVERY_MILLIS] ごとに出し直す（最長 [REPEAT_FOR_MILLIS]・音と振動は無し）。
     */
    fun postNotification(context: Context) {
        // 通知を許可していなくても、画面の端のボタンを出せるならサービスは動かす。
        if (needsPermission(context) && !CopyGuideOverlay.canShow(context)) return
        val app = context.applicationContext
        runCatching { ContextCompat.startForegroundService(app, Intent(app, CopyGuideService::class.java)) }
            .onFailure { notify(app, build(app, alert = true)) }
    }

    /**
     * 「アプリに戻る」の通知の中身。[alert] が true なら、画面上部にもう一度ポップアップを出す。
     * [quiet] なら上部にポップアップを出さず、通知の一覧にだけ置く（画面の端にボタンを出しているとき）。
     */
    fun build(context: Context, alert: Boolean, quiet: Boolean = false): android.app.Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (quiet && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager != null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    QUIET_CHANNEL_ID,
                    context.getString(R.string.copyguide_notification_channel_quiet),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        if (!quiet && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager != null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    context.getString(R.string.copyguide_notification_channel),
                    // 画面上部にポップアップで出す。ただし音と振動は無し（何度も出し直すため）。
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                },
            )
        }
        val intent = Intent(context, MainActivity::class.java)
            .setAction(ACTION_FROM_GUIDE)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(
            context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, if (quiet) QUIET_CHANNEL_ID else CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.copyguide_notification_text))
            .setContentText(context.getString(R.string.app_name))
            .setPriority(if (quiet) NotificationCompat.PRIORITY_LOW else NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setContentIntent(pending)
            .setAutoCancel(true)
            // 押されるまで残す（スワイプでは消えない）。
            .setOngoing(true)
            .setOnlyAlertOnce(!alert)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
    }

    // 通知の権限は直前の needsPermission で確かめている（Lint はそれを追えない）。
    @android.annotation.SuppressLint("MissingPermission")
    fun notify(context: Context, notification: android.app.Notification) {
        if (needsPermission(context)) return
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }

    /** 通知を消し、出し直しも止める（アプリに戻ったとき・チャンネルを開いたとき）。 */
    fun cancelNotification(context: Context) {
        CopyGuideService.stop(context.applicationContext)
    }

    /** 案内から YouTube を開いてから、この時間までに戻ってきたら「コピーしに行っていた」とみなす。 */
    private const val AWAIT_MILLIS = 30 * 60 * 1000L
    private const val PREFS = "copy_link_guide"
    private const val KEY_AWAITING_SINCE = "awaiting_since"
    private const val KEY_BASELINE = "baseline_clip"

    /**
     * 案内から YouTube を開く直前に呼ぶ。その時点でコピーされていたリンクを控えておき、
     * 戻ってきたときに**それと違う** YouTube のリンクがあれば、新しくコピーしたものとして開く。
     */
    fun startAwaiting(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong(KEY_AWAITING_SINCE, System.currentTimeMillis())
            .putString(KEY_BASELINE, copiedYouTubeUrl(context))
            .apply()
    }

    /**
     * 案内の途中で戻ってきたときに、新しくコピーされた YouTube のリンクを返す（無ければ null）。
     * 見つかったら待ち状態を終える。
     */
    fun takeNewlyCopiedUrl(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val since = prefs.getLong(KEY_AWAITING_SINCE, 0L)
        if (since == 0L) return null
        // アプリに戻ってきた時点で、通知の役目は終わり（押さずに戻るボタンで戻った場合も消して、出し直しも止める）。
        // YouTube を開く直前の画面の切り替わり（許可の確認を閉じたとき等）では消さないよう、少し待つ。
        if (System.currentTimeMillis() - since > 3_000L) cancelNotification(context)
        if (System.currentTimeMillis() - since > AWAIT_MILLIS) {
            prefs.edit().remove(KEY_AWAITING_SINCE).remove(KEY_BASELINE).apply()
            return null
        }
        val url = copiedYouTubeUrl(context) ?: return null
        if (url == prefs.getString(KEY_BASELINE, null)) return null
        prefs.edit().remove(KEY_AWAITING_SINCE).remove(KEY_BASELINE).apply()
        cancelNotification(context)
        return url
    }

    /** コピーされている内容を消す（「コピーをクリア」）。 */
    fun clearClipboard(context: Context) {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
        runCatching {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                clipboard.clearPrimaryClip()
            } else {
                clipboard.setPrimaryClip(android.content.ClipData.newPlainText("", ""))
            }
        }
    }

    /** クリップボードにある YouTube の URL（無ければ null）。前面にいるときだけ呼ぶこと。 */
    fun copiedYouTubeUrl(context: Context): String? {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return null
        val clip = runCatching { clipboard.primaryClip }.getOrNull() ?: return null
        if (clip.itemCount == 0) return null
        val text = clip.getItemAt(0).coerceToText(context)?.toString() ?: return null
        return SharedLinkParser.extractYouTubeUrl(text)
    }
}
