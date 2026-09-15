package com.deskflowlabs.channeltimelineviewer.ui

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.Image
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
 * 画像は実機で撮った本物の画面（YouTube アプリと Android の共有シート）。
 * **説明文は画像に焼き込まず**、ここでローカライズして出す。
 * そうしておけば同じ画像を7言語で使い回せる（docs/onboarding/CHANNEL_ADD_TUTORIAL.md）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelTutorialSheet(
    onDismiss: () -> Unit,
    onComplete: () -> Unit,
    onSkip: (stepNumber: Int) -> Unit,
) {
    val context = LocalContext.current
    val appName = stringResource(R.string.app_name)
    val steps = tutorialSteps()
    var index by remember { mutableIntStateOf(0) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val step = steps[index]
    val isLast = index == steps.lastIndex

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
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
                if (index > 0) {
                    OutlinedButton(onClick = { index -= 1 }) {
                        Text(stringResource(R.string.tutorial_back))
                    }
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
            image = R.drawable.tutorial_youtube_channel,
            imageDescription = R.string.tutorial_step1_image_a11y,
        ),
        TutorialStep(
            title = R.string.tutorial_step2_title,
            body = R.string.tutorial_step2_body,
            image = R.drawable.tutorial_youtube_share,
            imageDescription = R.string.tutorial_step2_image_a11y,
        ),
        TutorialStep(
            title = R.string.tutorial_step3_title,
            body = R.string.tutorial_step3_body,
            image = R.drawable.tutorial_android_share_sheet,
            imageDescription = R.string.tutorial_step3_image_a11y,
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
