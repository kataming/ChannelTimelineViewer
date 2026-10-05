package com.deskflowlabs.channeltimelineviewer.ui

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.widget.ImageView
import androidx.core.content.ContextCompat
import com.deskflowlabs.channeltimelineviewer.MainActivity
import com.deskflowlabs.channeltimelineviewer.R
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * 「YouTube の共有から追加する」のあいだ、YouTube の上に出す「アプリに戻る」ボタン
 * （2026-10-05・ユーザー判断）。
 *
 * 画面上部の通知のポップアップは、YouTube でチャンネルを選ぶ操作のじゃまになる。
 * そこで「他のアプリの上に重ねて表示」を許可した人には、**画面の右端・下寄り**に
 * アプリのロゴマークの丸いボタンを出す（ユーザー指定）。
 *
 * - 真下に帯を置かないのは、YouTube の下のタブと共有メニュー（［コピー］）にかぶるため
 * - 指でドラッグして動かせる。離すと近いほうの端に寄せ、置いた場所は次回も使う
 * - 押すと通知と同じ動き（アプリに戻り、コピーしたリンクのチャンネルを開く）
 * - アプリに戻ったら消える（[CopyLinkGuide.cancelNotification]）。最長 [SHOW_FOR_MILLIS]
 * - 許可していない人には出さない（通知の案内だけ）。許可は設定画面でしか出せない（Play のポリシー）
 */
object CopyGuideOverlay {

    /** これだけたっても戻ってこなければボタンを消す（通知の一覧には案内が残る）。 */
    private const val SHOW_FOR_MILLIS = 10 * 60_000L

    private const val PREFS = "copy_link_guide"
    private const val KEY_SIDE_LEFT = "overlay_left"
    private const val KEY_Y_FRACTION = "overlay_y"
    private const val KEY_ASKED = "overlay_asked"

    /** 最初の位置（画面の高さに対する割合）。共有メニューの［コピー］の行の右の空いているところ。 */
    private const val DEFAULT_Y_FRACTION = 0.70f
    private const val SIZE_DP = 56
    private const val MARGIN_DP = 6

    private val handler = Handler(Looper.getMainLooper())
    private var view: View? = null
    private val autoHide = Runnable { hide() }

    /** 「他のアプリの上に重ねて表示」が許可されているか。 */
    fun canShow(context: Context): Boolean = Settings.canDrawOverlays(context)

    /** 許可を一度聞いたか（聞いたあとは毎回は聞かない。案内の画面に小さく入口を残す）。 */
    fun wasAsked(context: Context): Boolean = prefs(context).getBoolean(KEY_ASKED, false)

    fun markAsked(context: Context) {
        prefs(context).edit().putBoolean(KEY_ASKED, true).apply()
    }

    /** 許可の設定画面（このアプリの項目を直接開く）。 */
    fun settingsIntent(context: Context): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))

    /** ボタンを出す。許可が無い・出せなかったときは false（呼び出し側は通知で案内する）。 */
    fun show(context: Context): Boolean {
        if (view != null) {
            restartTimer()
            return true
        }
        if (!canShow(context)) return false
        val app = context.applicationContext
        val wm = app.getSystemService(WindowManager::class.java) ?: return false
        val density = app.resources.displayMetrics.density
        val size = (SIZE_DP * density).roundToInt()
        val margin = (MARGIN_DP * density).roundToInt()
        val screenH = app.resources.displayMetrics.heightPixels

        val button = ImageView(app).apply {
            // アプリのロゴマーク（一覧＋再生）を、アイコンと同じ背景色の丸に載せる。
            setImageResource(R.drawable.ic_launcher_foreground)
            scaleType = ImageView.ScaleType.FIT_CENTER
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(ContextCompat.getColor(app, R.color.ic_launcher_background))
                // 影は付けない（ウィンドウの四角で影が切れて見えるため）。白い縁で背景と分ける。
                setStroke((2 * density).roundToInt(), 0xFFFFFFFF.toInt())
            }
            contentDescription = app.getString(R.string.copyguide_notification_text)
        }

        val prefs = prefs(app)
        val params = WindowManager.LayoutParams(
            size,
            size,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            // ボタンの外の操作はそのまま YouTube に届ける。キーボードの入力も奪わない。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            val left = prefs.getBoolean(KEY_SIDE_LEFT, false)
            gravity = Gravity.TOP or (if (left) Gravity.LEFT else Gravity.RIGHT)
            x = margin
            y = (prefs.getFloat(KEY_Y_FRACTION, DEFAULT_Y_FRACTION) * screenH).roundToInt() - size / 2
        }
        button.setOnTouchListener(DragOrTap(app, wm, params, size, margin))

        val added = runCatching { wm.addView(button, params) }.isSuccess
        if (!added) return false
        view = button
        restartTimer()
        return true
    }

    /** ボタンを消す（アプリに戻ったとき・時間切れ）。 */
    fun hide() {
        handler.removeCallbacks(autoHide)
        val v = view ?: return
        view = null
        runCatching { v.context.getSystemService(WindowManager::class.java)?.removeView(v) }
    }

    val isShowing: Boolean get() = view != null

    private fun restartTimer() {
        handler.removeCallbacks(autoHide)
        handler.postDelayed(autoHide, SHOW_FOR_MILLIS)
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** 押したらアプリへ戻る。動かしたら端に寄せて位置を覚える。 */
    private class DragOrTap(
        private val context: Context,
        private val wm: WindowManager,
        private val params: WindowManager.LayoutParams,
        private val size: Int,
        private val margin: Int,
    ) : View.OnTouchListener {
        private val slop = ViewConfiguration.get(context).scaledTouchSlop
        private var downRawX = 0f
        private var downRawY = 0f
        private var dragging = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(v: View, e: MotionEvent): Boolean {
            val metrics = context.resources.displayMetrics
            when (e.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    downRawX = e.rawX
                    downRawY = e.rawY
                    dragging = false
                    // 端に寄せた状態から自由に動かすため、ここからは左上を基準に置く。
                    val left = (params.gravity and Gravity.HORIZONTAL_GRAVITY_MASK) == Gravity.LEFT
                    params.gravity = Gravity.TOP or Gravity.LEFT
                    params.x = if (left) params.x else metrics.widthPixels - params.x - size
                    runCatching { wm.updateViewLayout(v, params) }
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = e.rawX - downRawX
                    val dy = e.rawY - downRawY
                    if (!dragging && (abs(dx) > slop || abs(dy) > slop)) dragging = true
                    if (dragging) {
                        params.x = (e.rawX - size / 2f).roundToInt().coerceIn(0, metrics.widthPixels - size)
                        params.y = (e.rawY - size / 2f).roundToInt().coerceIn(0, metrics.heightPixels - size)
                        runCatching { wm.updateViewLayout(v, params) }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    val toLeft = params.x + size / 2 < metrics.widthPixels / 2
                    params.gravity = Gravity.TOP or (if (toLeft) Gravity.LEFT else Gravity.RIGHT)
                    params.x = margin
                    runCatching { wm.updateViewLayout(v, params) }
                    if (dragging) {
                        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                            .putBoolean(KEY_SIDE_LEFT, toLeft)
                            .putFloat(KEY_Y_FRACTION, (params.y + size / 2f) / metrics.heightPixels)
                            .apply()
                    } else if (e.actionMasked == MotionEvent.ACTION_UP) {
                        v.performClick()
                        openApp()
                    }
                }
            }
            return true
        }

        private fun openApp() {
            // 重ねて表示を許可されたアプリは、裏からでも画面を開ける（Android の例外規定）。
            val intent = Intent(context, MainActivity::class.java)
                .setAction(CopyLinkGuide.ACTION_FROM_GUIDE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            runCatching { context.startActivity(intent) }
        }
    }
}
