package com.deskflowlabs.channeltimelineviewer.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.style.TextOverflow
import coil.compose.AsyncImage
import com.deskflowlabs.channeltimelineviewer.network.PopularVideo
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.SheetValue
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.deskflowlabs.channeltimelineviewer.R

/**
 * 「YouTube のチャンネルをこのアプリに追加する方法」の案内。
 *
 * なぜ要るか: 追加の入口が「YouTube の共有 → このアプリを選ぶ」で、
 * 初めての人には見つけられない。入れた直後に何もできずに終わるのを防ぐ。
 *
 * 出すのは**初めてチャンネルを追加しようとしたとき**だけ（起動のたびには出さない）。
 * あとは「このアプリについて」からいつでも開き直せる。
 *
 * 画像は実機（エミュレータ）で撮った本物の画面を**7言語ぶん**用意してある。
 * 端末の言語に合わせて Android が drawable-<言語>-nodpi から自動で選ぶので、
 * ここでは R.drawable.tutorial_step1 のように既定の名前だけ見ればよい。
 * **説明文は画像に焼き込まない**（同じ絵を使い回すのではなく、絵も文字も言語を揃える）。
 * 詳しくは docs/onboarding/CHANNEL_ADD_TUTORIAL.md。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelTutorialSheet(
    onDismiss: () -> Unit,
    onComplete: () -> Unit,
    onSkip: (stepNumber: Int) -> Unit,
    loadPopular: suspend () -> List<PopularVideo>,
    onPickVideo: (PopularVideo) -> Unit,
    /**
     * 下へのスワイプ・外側のタップ・戻るボタンで閉じられるか。
     * 初めての人（まだ1チャンネルも無い人）には false にする。ここで閉じると
     * 何もできない画面が残るだけなので、動画を選ぶか「YouTube から追加する」へ進むまで残す。
     */
    dismissible: Boolean = true,
    /** 最初から「YouTube の共有から追加する」の案内を開く（最初の画面のボタンから来たとき）。 */
    startWithCopyGuide: Boolean = false,
) {
    val context = LocalContext.current
    val appName = stringResource(R.string.app_name)
    val steps = tutorialSteps()
    var index by remember { mutableIntStateOf(0) }
    // 最初は「人気の動画から選ぶ」画面。YouTube から追加する手順（4ステップ）は、選びたい動画が無い人だけが見る。
    var showSteps by rememberSaveable { mutableStateOf(false) }
    // 「YouTube の共有から追加する」= コピーして通知から戻る案内。従来の4ステップはそこから開く。
    var showCopyGuide by rememberSaveable { mutableStateOf(startWithCopyGuide) }
    // 開くたびに、指定された画面から始める（前回の表示状態を引き継がない）。
    LaunchedEffect(startWithCopyGuide) {
        showCopyGuide = startWithCopyGuide
        showSteps = false
    }
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { dismissible || it != SheetValue.Hidden },
    )
    val step = steps[index]
    val isLast = index == steps.lastIndex

    ModalBottomSheet(
        // 戻るボタンでは閉じて最初の画面に戻す（アプリを終了させない）。下へのスワイプと外側のタップは
        // confirmValueChange で止めているので、ここに来るのは戻るボタン（と閉じてよいとき）だけ。
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = true),
    ) {
        if (showCopyGuide && !showSteps) {
            CopyLinkGuidePage(
                onBack = { showCopyGuide = false },
                onShowSteps = { showSteps = true },
            )
            return@ModalBottomSheet
        }
        if (!showSteps) {
            PopularVideoPicker(
                loadPopular = loadPopular,
                onPickVideo = onPickVideo,
                onShowSteps = { showCopyGuide = true },
                // 初めての人には「閉じる」を出さない（選ぶか、YouTube から追加する方へ進む）。
                onClose = if (dismissible) ({ onSkip(0) }) else null,
            )
            return@ModalBottomSheet
        }
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                stringResource(R.string.tutorial_title),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                stringResource(
                    R.string.tutorial_progress_format,
                    (index + 1).toString(),
                    steps.size.toString(),
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Text(
                stringResource(step.title, appName),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                stringResource(step.body, appName),
                style = MaterialTheme.typography.bodyMedium,
            )

            // 画像が読めなくても案内は続けられるようにする（説明は上の文章で完結している）。
            TutorialImage(step)

            Spacer(Modifier.height(4.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                // 1つ目の手順の「戻る」は、人気の動画を選ぶ画面へ戻る。
                OutlinedButton(onClick = { if (index > 0) index -= 1 else showSteps = false }) {
                    Text(stringResource(R.string.tutorial_back))
                }
                if (isLast) {
                    Button(
                        onClick = {
                            openYouTube(context)
                            onComplete()
                        },
                        modifier = Modifier.weight(1f),
                    ) {
                        Text(stringResource(R.string.tutorial_cta))
                    }
                } else {
                    Button(onClick = { index += 1 }, modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.tutorial_next))
                    }
                }
            }

            TextButton(
                onClick = { onSkip(index + 1) },
                modifier = Modifier.align(Alignment.CenterHorizontally),
            ) {
                Text(stringResource(if (isLast) R.string.tutorial_close else R.string.tutorial_skip))
            }

            // 例として他社のチャンネルを出している以上、関係が無いことは必ず書く。
            Text(
                stringResource(R.string.tutorial_example_note),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * 初めての人向けの最初の画面: その国でいま人気の動画を並べ、選んだ動画のチャンネルをそのまま開く。
 * URL を持っていない人でも、アプリの中だけで「チャンネルの動画を古い順に見る」まで行けるようにする。
 * 読み込めなかったときは、従来どおり YouTube から追加する手順へ案内する。
 */
@Composable
private fun PopularVideoPicker(
    loadPopular: suspend () -> List<PopularVideo>,
    onPickVideo: (PopularVideo) -> Unit,
    onShowSteps: () -> Unit,
    onClose: (() -> Unit)?,
) {
    var videos by remember { mutableStateOf<List<PopularVideo>?>(null) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        runCatching { loadPopular() }
            .onSuccess { videos = it; failed = it.isEmpty() }
            .onFailure { failed = true }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.tutorial_pick_title), style = MaterialTheme.typography.titleLarge)
        Text(
            stringResource(R.string.tutorial_pick_body),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        val list = videos
        when {
            failed -> Text(
                stringResource(R.string.tutorial_pick_error),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.error,
            )
            list == null -> Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(vertical = 24.dp),
            ) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                Text(stringResource(R.string.tutorial_pick_loading))
            }
            else -> list.forEach { video ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(10.dp))
                        .clickable { onPickVideo(video) }
                        .padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    AsyncImage(
                        model = video.thumbnailUrl,
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .width(144.dp)
                            .aspectRatio(16f / 9f)
                            .clip(RoundedCornerShape(8.dp)),
                    )
                    Column(Modifier.weight(1f)) {
                        Text(
                            video.title,
                            style = MaterialTheme.typography.bodyMedium,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            video.channelTitle,
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }

        Spacer(Modifier.height(4.dp))
        Text(stringResource(R.string.tutorial_pick_other), style = MaterialTheme.typography.labelLarge)
        OutlinedButton(onClick = onShowSteps, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tutorial_pick_howto))
        }
        if (onClose != null) {
            TextButton(onClick = onClose, modifier = Modifier.align(Alignment.CenterHorizontally)) {
                Text(stringResource(R.string.tutorial_close))
            }
        }
    }
}

/**
 * 「YouTube の共有から追加する」: YouTube で［共有］→［コピー］を押し、通知をタップして戻ってもらう。
 * 共有メニューの中から本アプリを探す手間をなくすため（2026-10-05・ユーザー判断）。仕組みは [CopyLinkGuide]。
 */
@Composable
private fun CopyLinkGuidePage(
    onBack: () -> Unit,
    onShowSteps: () -> Unit,
) {
    val context = LocalContext.current
    val appName = stringResource(R.string.app_name)
    // 「アプリに戻る」の通知を出してから YouTube を開く。通知を押す（または戻るボタンで戻る）と、
    // MainActivity がコピーされたリンクを読んでチャンネルを開く。
    val goToYouTube = {
        CopyLinkGuide.startAwaiting(context)
        CopyLinkGuide.postNotification(context)
        openYouTube(context)
    }
    // Android 13 以降は通知の許可を先に聞く。許可されなくても YouTube は開く（戻るボタンで戻れば読める）。
    val askPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {
        goToYouTube()
    }
    val goWithNotification = {
        if (CopyLinkGuide.needsPermission(context)) {
            askPermission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        } else {
            goToYouTube()
        }
    }
    // 画面の端の「アプリに戻る」ボタン（[CopyGuideOverlay]）。許可は設定画面でしか出せない。
    var overlayAllowed by remember { mutableStateOf(CopyGuideOverlay.canShow(context)) }
    var overlayAsked by remember { mutableStateOf(CopyGuideOverlay.wasAsked(context)) }
    // 説明（文と③の絵）は、まだ聞いていない人にも画面の端のボタンの方を見せる（これから勧めるのはそちら）。
    // 通知の説明に切り替えるのは、許可しないと決めた人だけ（2026-10-05・ユーザー指摘）。
    val showOverlayGuide = overlayAllowed || !overlayAsked
    var askOverlay by remember { mutableStateOf(false) }
    // 案内の流れの途中で設定画面へ行ったときは、戻ってきたらそのまま YouTube を開く。
    var continueAfterSettings by remember { mutableStateOf(false) }
    val overlaySettings = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        overlayAllowed = CopyGuideOverlay.canShow(context)
        if (continueAfterSettings) {
            continueAfterSettings = false
            if (overlayAllowed) goToYouTube() else goWithNotification()
        }
    }
    val openOverlaySettings = { thenGo: Boolean ->
        CopyGuideOverlay.markAsked(context)
        overlayAsked = true
        continueAfterSettings = thenGo
        val launched = runCatching { overlaySettings.launch(CopyGuideOverlay.settingsIntent(context)) }.isSuccess
        if (!launched && thenGo) {
            continueAfterSettings = false
            goWithNotification()
        }
    }

    if (askOverlay) {
        AlertDialog(
            onDismissRequest = { askOverlay = false },
            title = { Text(stringResource(R.string.copyguide_overlay_ask_title)) },
            text = { Text(stringResource(R.string.copyguide_overlay_ask_body)) },
            confirmButton = {
                Button(onClick = {
                    askOverlay = false
                    openOverlaySettings(true)
                }) { Text(stringResource(R.string.copyguide_overlay_ask_allow)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    askOverlay = false
                    CopyGuideOverlay.markAsked(context)
                    overlayAsked = true
                    goWithNotification()
                }) { Text(stringResource(R.string.copyguide_overlay_ask_skip)) }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp)
            .padding(bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(stringResource(R.string.copyguide_title), style = MaterialTheme.typography.titleLarge)
        // 見出しと同じ大きさで、やることだけを2行で（2026-10-05・ユーザー指定）。
        Text(
            stringResource(if (showOverlayGuide) R.string.copyguide_step1_overlay else R.string.copyguide_step1),
            style = MaterialTheme.typography.titleLarge,
        )
        // ［共有］→［コピー］→「コピーされました」と戻るボタン、を実際の画面（NASA の動画）で順に見せる。
        CopyGuideAnimation(overlay = showOverlayGuide)

        Button(
            onClick = {
                when {
                    overlayAllowed -> goToYouTube()
                    // 初回だけ「画面の端にボタンを出しますか？」と聞く。断った人は通知で案内する。
                    !overlayAsked -> askOverlay = true
                    else -> goWithNotification()
                }
            },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(stringResource(R.string.copyguide_open))
        }
        // 一度断った人にも、あとから画面の端のボタンに切り替えられる入口を残す。
        if (!overlayAllowed && overlayAsked) {
            TextButton(
                onClick = { openOverlaySettings(false) },
                modifier = Modifier.align(Alignment.CenterHorizontally),
            ) {
                Text(stringResource(R.string.copyguide_overlay_enable))
            }
        }
        OutlinedButton(onClick = onBack, modifier = Modifier.fillMaxWidth()) {
            Text(stringResource(R.string.tutorial_back))
        }
        TextButton(onClick = onShowSteps, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text(stringResource(R.string.copyguide_legacy, appName))
        }
    }
}

/**
 * 「YouTube の共有から追加する」の流れを、3枚の画面写真を自動で切り替えて見せる（動画の代わり）。
 * 各写真には ①②③ の丸数字と、押す場所を指す矢印を描き込んである（2026-10-05・ユーザー指定）。
 * 本物の録画にしないのは、他人の映像（動画の中身）をアプリ内で流さないため。映像部分はぼかしてある。
 * 画像は scripts/build_copy_guide_frames.py で作る（7言語。drawable-<言語>-nodpi/copyguide_frame1〜3）。
 * [overlay]（画面の端のボタンを許可済み・またはまだ聞いていない）なら、③は通知ではなく「クリック」→ロゴのボタンの絵
 * （copyguide_frame3_overlay・2026-10-05 ユーザー指定）。
 */
@Composable
private fun CopyGuideAnimation(overlay: Boolean) {
    val frames = remember(overlay) {
        listOf(
            R.drawable.copyguide_frame1,
            R.drawable.copyguide_frame2,
            if (overlay) R.drawable.copyguide_frame3_overlay else R.drawable.copyguide_frame3,
        )
    }
    var index by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            kotlinx.coroutines.delay(if (index == frames.lastIndex) 2800L else 2200L)
            index = (index + 1) % frames.size
        }
    }
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        androidx.compose.animation.Crossfade(targetState = index, label = "copyGuide") { i ->
            Image(
                painter = painterResource(frames[i]),
                contentDescription = null,
                modifier = Modifier
                    .fillMaxWidth(0.62f)
                    .clip(RoundedCornerShape(12.dp))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)),
            )
        }
        // いま何枚目か（1 → 2 → 3）。
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            frames.indices.forEach { i ->
                androidx.compose.foundation.layout.Box(
                    Modifier
                        .size(8.dp)
                        .clip(androidx.compose.foundation.shape.CircleShape)
                        .background(
                            if (i == index) MaterialTheme.colorScheme.primary
                            else MaterialTheme.colorScheme.outlineVariant,
                        ),
                )
            }
        }
    }
}

@Composable
private fun TutorialImage(step: TutorialStep) {
    val description = stringResource(step.imageDescription, stringResource(R.string.app_name))
    Image(
        painter = painterResource(step.image),
        contentDescription = description,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .semantics { contentDescription = description },
    )
}

/** 1手順ぶんの中身。画像とその読み上げ文だけを持つ。 */
private data class TutorialStep(
    @StringRes val title: Int,
    @StringRes val body: Int,
    @DrawableRes val image: Int,
    @StringRes val imageDescription: Int,
)

@Composable
private fun tutorialSteps(): List<TutorialStep> = remember {
    listOf(
        TutorialStep(
            title = R.string.tutorial_step1_title,
            body = R.string.tutorial_step1_body,
            image = R.drawable.tutorial_step1,
            imageDescription = R.string.tutorial_step1_image_a11y,
        ),
        TutorialStep(
            title = R.string.tutorial_step2_title,
            body = R.string.tutorial_step2_body,
            image = R.drawable.tutorial_step2,
            imageDescription = R.string.tutorial_step2_image_a11y,
        ),
        TutorialStep(
            title = R.string.tutorial_step3_title,
            body = R.string.tutorial_step3_body,
            image = R.drawable.tutorial_step3,
            imageDescription = R.string.tutorial_step3_image_a11y,
        ),
        TutorialStep(
            title = R.string.tutorial_step4_title,
            body = R.string.tutorial_step4_body,
            image = R.drawable.tutorial_step4,
            imageDescription = R.string.tutorial_step4_image_a11y,
        ),
    )
}

/**
 * YouTube を開く。特定のチャンネルへは飛ばさない
 * （例に出した NASA ではなく、**その人が見たいチャンネル**を探してもらう）。
 *
 * YouTube アプリが無い端末ではブラウザで開く。どちらも開けなくても落とさない。
 */
private fun openYouTube(context: android.content.Context) {
    val uri = Uri.parse("https://www.youtube.com/")
    val app = Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.youtube")
    runCatching { context.startActivity(app) }
        .recoverCatching { context.startActivity(Intent(Intent.ACTION_VIEW, uri)) }
        .onFailure { if (it !is ActivityNotFoundException) throw it }
}
