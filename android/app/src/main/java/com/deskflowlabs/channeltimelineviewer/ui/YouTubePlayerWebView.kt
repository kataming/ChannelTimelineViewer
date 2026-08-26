package com.deskflowlabs.channeltimelineviewer.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.net.Uri
import android.view.View
import android.view.ViewGroup
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.deskflowlabs.channeltimelineviewer.BuildConfig
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerCommand
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerOptions
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerState
import org.json.JSONObject

/**
 * 公式 IFrame Player を表示する WebView。
 *
 * iOS 版と**同じ中継ページ**（GitHub Pages の player.html）を読み込み、その中に公式プレイヤーを埋め込む。
 * 動画ファイルの取得・保存・独自プレイヤーでの再生は一切行わない。
 *
 * ページからの通知は `window.ytAndroid.postMessage(JSON)` で受け取る（iOS は WKWebView のハンドラ）。
 */
@SuppressLint("SetJavaScriptEnabled")
@Composable
fun YouTubePlayerWebView(
    videoId: String,
    startSeconds: Double,
    command: PlayerCommand?,
    autoplayOnLoad: Boolean,
    onStateChange: (PlayerState) -> Unit,
    onTimeUpdate: (videoId: String, seconds: Double, duration: Double) -> Unit,
    onOptions: (PlayerOptions) -> Unit,
    onNearEnd: (videoId: String) -> Unit = {},
    fullscreen: FullscreenState? = null,
    modifier: Modifier = Modifier,
) {
    // 直前に読み込んだ動画・処理済みのコマンドを覚えておき、無駄な再読み込みを避ける。
    val state = remember { PlayerViewState() }

    // 画面を離れるときは、全画面のままにしない（システムバーと向きを戻す）。
    DisposableEffect(fullscreen) {
        onDispose { fullscreen?.exit() }
    }

    AndroidView(
        modifier = modifier,
        factory = { context ->
            WebView(context).apply {
                // AndroidView の既定は WRAP_CONTENT。WebView は中身の高さが確定しないため
                // 0 の高さで配置されることがあり、「音は出るのに何も見えない」状態になる。
                // 置き場所（16:9 の枠）いっぱいに広げる。
                layoutParams = android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                )
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                // 自動再生・頭出しのために、ユーザー操作なしの再生を許可する
                // （公式プレイヤーの中の話で、こちらで動画データを触るわけではない）。
                settings.mediaPlaybackRequiresUserGesture = false
                webViewClient = WebViewClient()
                // HTML5 の動画を描画するには WebChromeClient が要る。
                // 未設定だと「音は出るのに画面が真っ黒」になる（Android の WebView の仕様）。
                // 公式プレイヤーの全画面ボタンを効かせるには、さらに onShowCustomView が要る。
                webChromeClient = FullscreenWebChromeClient(context.findActivity(), fullscreen)
                addJavascriptInterface(
                    PlayerBridge(onStateChange, onTimeUpdate, onOptions, onNearEnd),
                    "ytAndroid",
                )
                state.load(this, videoId, startSeconds, autoplayOnLoad)
            }
        },
        update = { webView ->
            if (state.loadedVideoId != videoId) {
                state.change(webView, videoId, startSeconds, autoplayOnLoad)
                return@AndroidView
            }
            if (command != null && state.handledCommandId != command.id) {
                state.run(webView, command)
            }
        },
    )
}

/** WebView の読み込み状態（Compose の再構成をまたいで保持する）。 */
private class PlayerViewState {
    var loadedVideoId: String? = null
        private set
    var handledCommandId: Long? = null
        private set

    fun load(webView: WebView, videoId: String, startSeconds: Double, autoplay: Boolean) {
        loadedVideoId = videoId
        webView.loadUrl(pageUrl(videoId, autoplay, startSeconds))
    }

    /** ページを読み直さずに動画だけ差し替える。 */
    fun change(webView: WebView, videoId: String, startSeconds: Double, autoplay: Boolean) {
        loadedVideoId = videoId
        val id = sanitize(videoId)
        val fn = if (autoplay) "loadVideo" else "cueVideo"
        val seconds = startSeconds.takeIf { it.isFinite() && it > 0 }?.toInt() ?: 0
        webView.evaluateJavascript("$fn('$id', $seconds);") { result ->
            // ページがまだ読めていない等で失敗したら読み直す。
            if (result == null || result == "null") return@evaluateJavascript
        }
    }

    fun run(webView: WebView, command: PlayerCommand) {
        handledCommandId = command.id
        webView.evaluateJavascript(javaScript(command), null)
    }

    private fun javaScript(command: PlayerCommand): String = when (command) {
        is PlayerCommand.Seek -> "seekTo(${command.seconds.toInt()});"
        is PlayerCommand.Replay -> "replayVideo();"
        is PlayerCommand.SetRate -> "setRate(${command.rate});"
        is PlayerCommand.SetCaption ->
            command.code?.let { "setCaptionTrack('${sanitize(it)}');" } ?: "setCaptionTrack(null);"
        is PlayerCommand.RefreshOptions -> "postOptions();"
    }

    companion object {
        /** 中継ページの URL を組み立てる。 */
        fun pageUrl(videoId: String, autoplay: Boolean, startSeconds: Double): String {
            val builder = Uri.parse(BuildConfig.PLAYER_RELAY_URL).buildUpon()
                .appendQueryParameter("v", sanitize(videoId))
                .appendQueryParameter("autoplay", if (autoplay) "1" else "0")
            startQueryValue(startSeconds)?.let { builder.appendQueryParameter("start", it) }
            return builder.build().toString()
        }

        /** 開始位置を秒（整数）の文字列にする。0 以下・不正値は付けない。 */
        fun startQueryValue(start: Double): String? =
            if (!start.isFinite() || start < 1) null else start.toInt().toString()

        /** videoId に使える文字だけを残す（JS へ埋め込むため）。 */
        fun sanitize(value: String): String = value.filter { it.isLetterOrDigit() || it == '_' || it == '-' }
    }
}

/**
 * 中継ページ → アプリ の受け口。JSON 文字列で受け取る。
 */
private class PlayerBridge(
    private val onStateChange: (PlayerState) -> Unit,
    private val onTimeUpdate: (String, Double, Double) -> Unit,
    private val onOptions: (PlayerOptions) -> Unit,
    private val onNearEnd: (String) -> Unit,
) {
    @JavascriptInterface
    fun postMessage(json: String) {
        val body = runCatching { JSONObject(json) }.getOrNull() ?: return
        when (body.optString("event")) {
            "state" -> playerState(body.optInt("state", -1))?.let(onStateChange)
            "ended" -> onStateChange(PlayerState.Ended)
            "time" -> {
                // どの動画の位置かを取り違えないよう、videoId 付きで受け取る。
                val id = body.optString("v")
                if (id.isNotEmpty()) {
                    onTimeUpdate(id, body.optDouble("t", 0.0), body.optDouble("d", 0.0))
                }
            }
            "nearEnd" -> {
                // 終了の直前に届く。全画面のまま次の動画へ進むために使う。
                val id = body.optString("v")
                if (id.isNotEmpty()) onNearEnd(id)
            }
            "options" -> onOptions(parseOptions(body))
        }
    }

    companion object {
        /** IFrame Player API の状態値。 */
        fun playerState(raw: Int): PlayerState? = when (raw) {
            -1 -> PlayerState.Unstarted
            0 -> PlayerState.Ended
            1 -> PlayerState.Playing
            2 -> PlayerState.Paused
            3 -> PlayerState.Buffering
            5 -> PlayerState.Cued
            else -> null
        }

        /** 中継ページから届いた options メッセージを解釈する。 */
        fun parseOptions(body: JSONObject): PlayerOptions {
            val rates = body.optJSONArray("rates")?.let { array ->
                (0 until array.length()).mapNotNull { array.optDouble(it).takeIf { v -> !v.isNaN() } }
            }.orEmpty()

            val captions = body.optJSONArray("captions")?.let { array ->
                (0 until array.length()).mapNotNull { index ->
                    val item = array.optJSONObject(index) ?: return@mapNotNull null
                    val code = item.optString("code").ifEmpty { return@mapNotNull null }
                    PlayerOptions.Caption(code, item.optString("name").ifEmpty { code })
                }
            }.orEmpty()

            val active = body.optString("activeCaption").takeIf { it.isNotEmpty() }
            return PlayerOptions(
                rate = body.optDouble("rate", 1.0).takeIf { !it.isNaN() } ?: 1.0,
                rates = rates,
                captions = captions,
                activeCaption = active,
            )
        }
    }
}


/**
 * 公式プレイヤーの全画面表示を受け止める状態。
 *
 * WebView の中の動画を全画面にすると、Android は「この View を画面いっぱいに出してほしい」と
 * [WebChromeClient.onShowCustomView] で渡してくる。アプリ側で置き場所を用意しないと
 * 全画面ボタンを押しても何も起きないため、ここで面倒を見る。
 *
 * 画面（PlayerScreen）は [isFullscreen] を見て「戻る」の扱いを変え、
 * 離脱時には [exit] で元に戻す。
 */
class FullscreenState {
    internal var client: FullscreenWebChromeClient? = null

    /** いま全画面か。 */
    var isFullscreen by mutableStateOf(false)
        internal set

    /** 全画面なら解除して true。もともと全画面でなければ false。 */
    fun exit(): Boolean = client?.exitFullscreen() ?: false
}

@Composable
fun rememberFullscreenState(): FullscreenState = remember { FullscreenState() }

/**
 * 全画面の出し入れを行う WebChromeClient。
 *
 * - 渡された View を Activity の一番上（android.R.id.content）に重ねる
 * - システムバーを隠し、横向きに固定する（動画は横長のため）
 * - 解除時は元の向きとシステムバーに戻す
 */
internal class FullscreenWebChromeClient(
    private val activity: Activity?,
    private val state: FullscreenState?,
) : WebChromeClient() {

    private var customView: View? = null
    private var callback: CustomViewCallback? = null
    private var originalOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED

    init {
        state?.client = this
    }

    override fun onShowCustomView(view: View, cb: CustomViewCallback) {
        val activity = activity
        if (activity == null || customView != null) {
            // 置き場所が無い／すでに全画面なら、受け取らずに返す（重ねると戻せなくなる）。
            cb.onCustomViewHidden()
            return
        }
        customView = view
        callback = cb
        originalOrientation = activity.requestedOrientation

        val root = activity.findViewById<FrameLayout>(android.R.id.content)
        root.addView(
            view,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT,
            ),
        )
        systemBars(show = false)
        activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        state?.isFullscreen = true
    }

    override fun onHideCustomView() {
        exitFullscreen()
    }

    /** 全画面を解除する。もともと全画面でなければ何もせず false。 */
    fun exitFullscreen(): Boolean {
        val view = customView ?: return false
        val activity = activity ?: return false
        (activity.findViewById<FrameLayout>(android.R.id.content)).removeView(view)
        customView = null
        callback?.onCustomViewHidden()
        callback = null
        systemBars(show = true)
        activity.requestedOrientation = originalOrientation
        state?.isFullscreen = false
        return true
    }

    private fun systemBars(show: Boolean) {
        val activity = activity ?: return
        val controller = WindowInsetsControllerCompat(activity.window, activity.window.decorView)
        if (show) {
            controller.show(WindowInsetsCompat.Type.systemBars())
        } else {
            controller.hide(WindowInsetsCompat.Type.systemBars())
            controller.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
    }
}

/** Compose の Context から Activity を取り出す（見つからなければ null）。 */
internal fun Context.findActivity(): Activity? {
    var context = this
    while (context is ContextWrapper) {
        if (context is Activity) return context
        context = context.baseContext
    }
    return null
}
