package com.deskflowlabs.channeltimelineviewer.ads

import android.util.Log
import android.view.ViewGroup
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.R
import com.google.android.gms.ads.AdListener
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdSize
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.LoadAdError

/**
 * 画面に置く広告（アンカー型アダプティブバナーと MREC）。
 *
 * どちらも**読み込みに成功してから**場所を取る。取得中・失敗・オフライン・Pro のときは
 * 何も描かない（空白の枠を残さない）。広告の読み込みは画面の表示を待たせない。
 *
 * 再生画面には、本文の中（移動ボタンと「YouTubeでコメントする」の間）にだけ置く
 * （[PlayerBannerAd]）。⚠️ プレイヤーの上・中・重なる位置には置かない（YouTube API 規約 III.G.1.3）。
 * 置き場所は MainActivity・PlayerScreen で決めている。
 */

/**
 * 画面下に固定するアンカー型アダプティブバナー。Scaffold の `bottomBar` に入れて使う。
 * ナビゲーションバーの分だけ上に置く（下端のジェスチャー領域に重ねない）。
 */
@Composable
fun AnchorAdaptiveBanner(ads: AdsManager, modifier: Modifier = Modifier) {
    val canShow by ads.canShowAds.collectAsStateWithLifecycle()
    if (!canShow) return

    val context = LocalContext.current
    val widthDp = LocalConfiguration.current.screenWidthDp
    // Google が現在推奨しているアンカー型（高さは画面の20%以内・50〜150dp）。
    // 従来の getCurrentOrientationAnchoredAdaptiveBannerAdSize は 25.x で非推奨になった。
    val adSize = remember(widthDp) {
        AdSize.getLargeAnchoredAdaptiveBannerAdSize(context, widthDp)
    }
    val adView = rememberLoadedAdView(ads.config.bannerUnitId, adSize, placement = "anchor")
        ?: return

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // 一覧の最後の行と広告がくっついて見えないように区切る。
            HorizontalDivider()
            AdViewHost(
                adView = adView,
                modifier = Modifier.width(adSize.width.dp).height(adSize.height.dp),
            )
        }
    }
}

/**
 * 再生画面の本文の中に置くバナー（320×50）。スクロールと一緒に動く（画面に固定しない）。
 *
 * 1画面目に収まるよう、高さが一定の標準バナーにしている。「広告」の表示は、一覧のバナーと
 * 同じく付けない（2026-10-09・ユーザー判断）。移動ボタンを押し間違えないように上下に余白を取る。
 */
@Composable
fun PlayerBannerAd(ads: AdsManager, modifier: Modifier = Modifier) {
    val canShow by ads.canShowAds.collectAsStateWithLifecycle()
    if (!canShow) return
    val adView = rememberLoadedAdView(ads.config.playerBannerUnit, AdSize.BANNER, placement = "player")
        ?: return
    Box(
        modifier = modifier.fillMaxWidth().padding(vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        AdViewHost(adView = adView, modifier = Modifier.size(320.dp, 50.dp))
    }
}

/**
 * MREC（300×250）を読み込んでおく。**画面単位で呼ぶ**（一覧の行の中で呼ぶと、
 * スクロールで行が消えるたびに広告を作り直してしまう）。
 *
 * @return 読み込めた広告。出してはいけない・まだ・失敗のときは null
 */
@Composable
fun rememberMrecAd(ads: AdsManager): AdView? {
    val canShow by ads.canShowAds.collectAsStateWithLifecycle()
    if (!canShow) return null
    return rememberLoadedAdView(ads.config.mrecUnitId, AdSize.MEDIUM_RECTANGLE, placement = "mrec")
}

/**
 * MREC の枠。本文と見分けがつくように「広告」の表示と枠線を付け、中央に置く。
 * 動画やチャンネルの行と同じ見た目（カード・サムネイル）にはしない。
 */
@Composable
fun MrecAdSlot(adView: AdView, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            stringResource(R.string.ads_label),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Box(
            modifier = Modifier
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(4.dp))
                .padding(1.dp),
        ) {
            AdViewHost(adView = adView, modifier = Modifier.size(300.dp, 250.dp))
        }
    }
}

/**
 * 広告を1つ作って読み込み、成功したら返す。画面から外れたら破棄する。
 * 読み込みは画面に貼る前に始める（貼るのは成功してから）。
 */
@Composable
private fun rememberLoadedAdView(unitId: String, adSize: AdSize, placement: String): AdView? {
    val context = LocalContext.current
    var loaded by remember(unitId, adSize) { mutableStateOf<AdView?>(null) }

    DisposableEffect(unitId, adSize) {
        val view = runCatching {
            AdView(context).apply {
                setAdSize(adSize)
                adUnitId = unitId
                adListener = object : AdListener() {
                    override fun onAdLoaded() {
                        loaded = this@apply
                    }

                    override fun onAdFailedToLoad(error: LoadAdError) {
                        // 表示済みの広告の更新に失敗しただけなら、表示中のものはそのまま残す。
                        Log.i(TAG, "$placement ad failed to load: ${error.code} ${error.message}")
                    }
                }
                loadAd(AdRequest.Builder().build())
            }
        }.onFailure { Log.w(TAG, "$placement ad could not be created.", it) }.getOrNull()

        onDispose {
            loaded = null
            view?.let { runCatching { (it.parent as? ViewGroup)?.removeView(it); it.destroy() } }
        }
    }

    // 画面が裏に回っている間は広告の更新を止める。
    val lifecycleOwner = LocalLifecycleOwner.current
    val current = loaded
    DisposableEffect(lifecycleOwner, current) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_PAUSE -> current?.pause()
                Lifecycle.Event.ON_RESUME -> current?.resume()
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    return current
}

@Composable
private fun AdViewHost(adView: AdView, modifier: Modifier) {
    AndroidView(
        modifier = modifier,
        factory = {
            // 同じ広告を別の場所へ貼り直すとき（再構成など）に、前の親から外しておく。
            (adView.parent as? ViewGroup)?.removeView(adView)
            adView
        },
    )
}

private const val TAG = "Ads"
