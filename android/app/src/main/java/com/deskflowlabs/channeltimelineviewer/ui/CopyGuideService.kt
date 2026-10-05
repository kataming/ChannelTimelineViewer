package com.deskflowlabs.channeltimelineviewer.ui

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat

/**
 * 「YouTube の共有から追加する」で YouTube を開いているあいだだけ動く、短時間のフォアグラウンドサービス。
 *
 * なぜ要るか（2026-10-05 実機で確認）: 画面上部の通知のポップアップは数秒で引っ込むので、
 * ［コピー］を押すころには見えない。そこで数秒おきに出し直すが、メモリの少ない端末では
 * アプリが裏に回った直後に Android がアプリを終了させ、出し直しも止まってしまった。
 * フォアグラウンドサービスにしておけば、YouTube を見ているあいだも止められない。
 *
 * - 通知そのものが「アプリに戻る」（押すとアプリに戻り、コピーしたリンクのチャンネルを開く）
 * - [CopyLinkGuide.REPEAT_EVERY_MILLIS] ごとに出し直して、ポップアップをもう一度出す（音・振動なし）
 * - [CopyLinkGuide.REPEAT_FOR_MILLIS] たったら出し直しをやめる（通知は押されるまで残す）
 * - アプリに戻ったら [CopyLinkGuide.cancelNotification] で止まる
 * - 「他のアプリの上に重ねて表示」を許可した人には、上部のポップアップの代わりに
 *   画面の端へ「アプリに戻る」ボタン（[CopyGuideOverlay]）を出す。このときは通知を
 *   ポップアップの出ないチャンネルで出し（YouTube の操作のじゃまをしない）、出し直しもしない
 * - Android 14 以降は「短時間のサービス（shortService・約3分まで）」として動かす
 */
class CopyGuideService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var until = 0L
    private var overlay = false

    private val tick = object : Runnable {
        override fun run() {
            if (System.currentTimeMillis() >= until) {
                finishRepeating()
                return
            }
            CopyLinkGuide.notify(this@CopyGuideService, CopyLinkGuide.build(this@CopyGuideService, alert = true))
            handler.postDelayed(this, CopyLinkGuide.REPEAT_EVERY_MILLIS)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        until = System.currentTimeMillis() + CopyLinkGuide.REPEAT_FOR_MILLIS
        overlay = CopyGuideOverlay.show(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE
        } else {
            0
        }
        val started = runCatching {
            ServiceCompat.startForeground(this, CopyLinkGuide.NOTIFICATION_ID, firstNotification(), type)
        }.isSuccess
        if (!started) {
            // 始められなかったら、ふつうの通知だけ出して終わる（戻るボタンで戻れば同じように開く）。
            CopyLinkGuide.notify(this, firstNotification())
            stopSelf()
            return START_NOT_STICKY
        }
        handler.removeCallbacks(tick)
        // ボタンを出せたときは出し直さない（ボタンがあれば足りる。上部のポップアップはじゃまになる）。
        if (!overlay) handler.postDelayed(tick, CopyLinkGuide.REPEAT_EVERY_MILLIS)
        return START_NOT_STICKY
    }

    private fun firstNotification() =
        if (overlay) CopyLinkGuide.build(this, alert = false, quiet = true) else CopyLinkGuide.build(this, alert = true)

    /** 出し直しをやめる。通知は押されるまで残す（サービスから切り離して、ふつうの通知として出し直す）。 */
    private fun finishRepeating() {
        handler.removeCallbacks(tick)
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_DETACH)
        // ボタンはサービスが終わっても残す（[CopyGuideOverlay] が自分の時間切れで消す）。
        CopyLinkGuide.notify(this, CopyLinkGuide.build(this, alert = false, quiet = overlay))
        stopSelf()
    }

    /** Android 14 以降の「短時間のサービス」の時間切れ。 */
    override fun onTimeout(startId: Int) {
        finishRepeating()
    }

    override fun onDestroy() {
        handler.removeCallbacks(tick)
        super.onDestroy()
    }

    companion object {
        fun stop(service: android.content.Context) {
            CopyGuideOverlay.hide()
            service.stopService(Intent(service, CopyGuideService::class.java))
            runCatching { NotificationManagerCompat.from(service).cancel(CopyLinkGuide.NOTIFICATION_ID) }
        }
    }
}
