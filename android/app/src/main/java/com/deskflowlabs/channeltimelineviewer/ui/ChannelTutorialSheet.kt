package com.deskflowlabs.channeltimelineviewer.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
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
) {
    val context = LocalContext.current
    val appName = stringResource(R.string.app_name)
    val steps = tutorialSteps()
    var index by remember { mutableIntStateOf(0) }
    // 最初は「人気の動画から選ぶ」画面。YouTube から追加する手順（4ステップ）は、選びたい動画が無い人だけが見る。
    var showSteps by rememberSaveable { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true,
        confirmValueChange = { dismissible || it != SheetValue.Hidden },
    )
    val step = steps[index]
    val isLast = index == steps.lastIndex

    ModalBottomSheet(
        onDismissRequest = { if (dismissible) onDismiss() },
        sheetState = sheetState,
        properties = ModalBottomSheetProperties(shouldDismissOnBackPress = dismissible),
    ) {
        if (!showSteps) {
            PopularVideoPicker(
                loadPopular = loadPopular,
                onPickVideo = onPickVideo,
                onShowSteps = { showSteps = true },
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
