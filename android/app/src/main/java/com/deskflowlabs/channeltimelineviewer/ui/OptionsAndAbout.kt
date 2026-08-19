package com.deskflowlabs.channeltimelineviewer.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Divider
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.BuildConfig
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel

/**
 * 再生設定（速度・字幕）。公式プレイヤーの設定メニューは埋め込みの中で切れてしまうため、
 * iOS 版と同じく**プレイヤーの外**で同じ操作ができるようにしている。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlaybackOptionsSheet(viewModel: PlayerViewModel, onDismiss: () -> Unit) {
    val options by viewModel.options.collectAsStateWithLifecycle()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // 字幕トラックは再生開始から少し遅れて用意されるので、開くたびに取り直す。
    LaunchedEffect(Unit) { viewModel.refreshOptions() }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp)
                .padding(bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(stringResource(R.string.options_title), style = MaterialTheme.typography.titleMedium)

            Text(
                stringResource(R.string.options_rate_section),
                style = MaterialTheme.typography.titleSmall,
                modifier = Modifier.padding(top = 12.dp),
            )
            viewModel.availableRates.forEach { rate ->
                OptionRow(
                    label = stringResource(R.string.player_rate_format, PlayerViewModel.rateNumber(rate)),
                    selected = kotlin.math.abs(options.rate - rate) < 0.001,
                    onClick = { viewModel.setPlaybackRate(rate) },
                )
            }

            Divider(Modifier.padding(vertical = 8.dp))
            Text(
                stringResource(R.string.options_captions_section),
                style = MaterialTheme.typography.titleSmall,
            )
            OptionRow(
                label = stringResource(R.string.captions_off),
                selected = options.activeCaption == null,
                onClick = { viewModel.setCaptionTrack(null) },
            )
            options.captions.forEach { caption ->
                OptionRow(
                    label = caption.name,
                    selected = options.activeCaption == caption.code,
                    onClick = { viewModel.setCaptionTrack(caption.code) },
                )
            }
            Text(
                stringResource(
                    if (options.captions.isEmpty()) R.string.options_captions_notloaded
                    else R.string.options_captions_defaultoff
                ),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Divider(Modifier.padding(vertical = 8.dp))
            Row {
                Text(stringResource(R.string.options_quality_title), modifier = Modifier.weight(1f))
                Text(
                    stringResource(R.string.options_quality_auto),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                stringResource(R.string.options_quality_note),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            TextButton(onClick = onDismiss, modifier = Modifier.padding(top = 8.dp)) {
                Text(stringResource(R.string.common_done))
            }
        }
    }
}

@Composable
private fun OptionRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        if (selected) Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
    }
}

/**
 * 「このアプリについて」。規約順守に関わる注意事項を明示する画面で、内容は iOS 版と同じ。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AboutScreen(onBack: () -> Unit) {
    val context = LocalContext.current

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.about_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, null) }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(stringResource(R.string.app_name), style = MaterialTheme.typography.titleMedium)
            Body(stringResource(R.string.about_summary))

            Header(stringResource(R.string.about_notices_header))
            listOf(
                R.string.about_notice_notofficial,
                R.string.about_notice_officialplayer,
                R.string.about_notice_nodownload,
                R.string.about_notice_noadblock,
                R.string.about_notice_nobackground,
            ).forEach { res -> Body("・" + stringResource(res)) }

            Header(stringResource(R.string.about_data_header))
            Body(stringResource(R.string.about_data_body))

            Header(stringResource(R.string.about_autoplay_header))
            Body(stringResource(R.string.about_autoplay_body))

            Header(stringResource(R.string.about_screen_header))
            Body(stringResource(R.string.about_screen_body))

            Header(stringResource(R.string.about_resume_header))
            Body(stringResource(R.string.about_resume_body))

            TextButton(onClick = {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(BuildConfig.PRIVACY_POLICY_URL))
                )
            }) {
                Text(stringResource(R.string.about_privacypolicy))
            }
        }
    }
}

@Composable
private fun Header(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
}

@Composable
private fun Body(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}
