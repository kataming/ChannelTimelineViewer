package com.deskflowlabs.channeltimelineviewer.ui

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.FastForward
import androidx.compose.material.icons.filled.FastRewind
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.RepeatOn
import androidx.compose.material.icons.filled.RepeatOne
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.Undo
import androidx.compose.material3.Card
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.RepeatMode
import com.deskflowlabs.channeltimelineviewer.data.VideoMemoStore
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.ui.theme.SkippedOrange
import com.deskflowlabs.channeltimelineviewer.ui.theme.WatchedGreen
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerState
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel
import java.text.DateFormat
import java.util.Date

/**
 * 再生画面。iOS 版 `Views/PlayerView.swift` に対応する。
 *
 * 再生は公式 IFrame プレイヤー（WebView）で行い、その外側に進行状況・移動ボタン・メモを置く。
 * バックグラウンド再生はしない（画面を離れれば止まる）。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(
    viewModel: PlayerViewModel,
    channel: Channel,
    settings: PlaybackSettingsStore,
    memoStore: VideoMemoStore,
    onBack: () -> Unit,
    onOpenOptions: () -> Unit,
) {
    val context = LocalContext.current
    val currentIndex by viewModel.currentIndex.collectAsStateWithLifecycle()
    val command by viewModel.command.collectAsStateWithLifecycle()
    val startSeconds by viewModel.startSecondsForCurrent.collectAsStateWithLifecycle()
    val autoPlayNext by settings.autoPlayNext.collectAsStateWithLifecycle()
    val unwatchedOnly by settings.playUnwatchedOnly.collectAsStateWithLifecycle()
    val repeatMode by settings.repeatMode.collectAsStateWithLifecycle()
    val showEnded by viewModel.showEndedSuggestion.collectAsStateWithLifecycle()
    val didAutoAdvance by viewModel.didAutoAdvance.collectAsStateWithLifecycle()
    val canGoBack by viewModel.canGoBack.collectAsStateWithLifecycle()
    val statusRevision by viewModel.statusRevision.collectAsStateWithLifecycle()
    val memos by memoStore.memos.collectAsStateWithLifecycle()
    val playerState by viewModel.playerState.collectAsStateWithLifecycle()

    val video = viewModel.currentVideo
    var menuOpen by remember { mutableStateOf(false) }

    // 再生中だけ画面を消さない（置いたまま見ていて消えるのを防ぐ）。
    // バックグラウンド再生ではないので、画面を離れれば再生も止まる。
    KeepScreenOn(enabled = playerState == PlayerState.Playing || playerState == PlayerState.Buffering)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(channel.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, null) }
                },
                actions = {
                    RepeatBadgeButton(
                        mode = repeatMode,
                        onClick = { settings.cycleRepeatMode() },
                    )
                    IconButton(onClick = onOpenOptions) {
                        Icon(Icons.Default.Tune, stringResource(R.string.player_options_a11y))
                    }
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Default.MoreVert, stringResource(R.string.player_menu_a11y))
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        // statusRevision を読むことで、視聴済み・スキップの変化で表示が更新される。
                        val watched = statusRevision.let { viewModel.isCurrentWatched() }
                        val skipped = statusRevision.let { viewModel.isCurrentSkipped() }
                        DropdownMenuItem(
                            text = {
                                Text(stringResource(
                                    if (watched) R.string.player_menu_unmarkwatched
                                    else R.string.player_menu_markwatched
                                ))
                            },
                            onClick = {
                                viewModel.toggleCurrentWatched()
                                menuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = {
                                Text(stringResource(
                                    if (skipped) R.string.player_menu_unskip else R.string.player_menu_skip
                                ))
                            },
                            onClick = {
                                viewModel.toggleCurrentSkipped()
                                menuOpen = false
                            },
                        )
                        Divider()
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.player_menu_restart)) },
                            onClick = {
                                viewModel.restartFromBeginning()
                                menuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.player_openinyoutube)) },
                            onClick = {
                                menuOpen = false
                                video?.let {
                                    context.startActivity(
                                        Intent(Intent.ACTION_VIEW, Uri.parse(it.watchUrl))
                                    )
                                }
                            },
                        )
                    }
                },
            )
        },
    ) { padding ->
        if (video == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.player_novideos))
            }
            return@Scaffold
        }

        Column(Modifier.fillMaxSize().padding(padding)) {
            // プレイヤーは常に 16:9。拡大縮小はしない（レイアウトが崩れるため）。
            YouTubePlayerWebView(
                videoId = video.id,
                startSeconds = startSeconds,
                command = command,
                autoplayOnLoad = true,
                onStateChange = viewModel::handleState,
                onTimeUpdate = viewModel::handleTimeUpdate,
                onOptions = viewModel::handleOptions,
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(16f / 9f)
                    .background(Color.Black),
            )

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Text(video.title, style = MaterialTheme.typography.titleMedium)
                Text(
                    channel.title,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(
                    stringResource(
                        R.string.player_publishedwithposition_format,
                        DateFormat.getDateInstance(DateFormat.LONG)
                            .format(Date(video.publishedAtEpochSeconds * 1000)),
                        viewModel.positionText,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                if (didAutoAdvance) {
                    Text(
                        stringResource(R.string.player_autoadvanced),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }

                if (viewModel.isResumingFromSavedPosition) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            stringResource(
                                R.string.player_resume_notice_format,
                                PlaybackPositionStore.timeString(startSeconds),
                            ),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(1f),
                        )
                        TextButton(onClick = viewModel::restartFromBeginning) {
                            Text(stringResource(R.string.player_resume_restart))
                        }
                    }
                }

                if (showEnded) {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(12.dp)) {
                            Text(
                                stringResource(R.string.player_ended_title),
                                style = MaterialTheme.typography.bodySmall,
                            )
                            viewModel.nextVideo?.let { next ->
                                Text(next.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
                            }
                            TextButton(onClick = viewModel::goNext) {
                                Icon(Icons.Default.PlayArrow, null)
                                Text(stringResource(R.string.player_ended_playnext))
                            }
                        }
                    }
                }

                PlaybackToggles(
                    autoPlayNext = autoPlayNext,
                    unwatchedOnly = unwatchedOnly,
                    repeatMode = repeatMode,
                    onAutoPlayChange = settings::setAutoPlayNext,
                    onUnwatchedOnlyChange = settings::setPlayUnwatchedOnly,
                )

                NavigationButtons(
                    canGoPrevious = viewModel.canGoPrevious,
                    canGoNext = viewModel.canGoNext,
                    canGoBack = canGoBack,
                    onFirst = viewModel::goFirst,
                    onPrevious = viewModel::goPrevious,
                    onUndo = viewModel::goBack,
                    onNext = viewModel::goNext,
                    onLast = viewModel::goLast,
                )

                // statusRevision を読むと、視聴済み・スキップの切り替えで再描画される。
                val watched = statusRevision.let { viewModel.isCurrentWatched() }
                val skipped = statusRevision.let { viewModel.isCurrentSkipped() }
                if (watched) {
                    StatusLine(stringResource(R.string.video_watched), WatchedGreen)
                }
                if (skipped) {
                    StatusLine(stringResource(R.string.player_status_skipped), SkippedOrange)
                }

                OutlinedButton(
                    onClick = {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(video.watchUrl)))
                    },
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(stringResource(R.string.player_openinyoutube))
                }

                Text(
                    stringResource(R.string.player_memo_title),
                    style = MaterialTheme.typography.titleSmall,
                )
                OutlinedTextField(
                    value = memos[video.id].orEmpty(),
                    onValueChange = { memoStore.setMemo(it, video.id) },
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                )
                Text(
                    stringResource(R.string.player_memo_autosave),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )

                if (video.description.isNotEmpty()) {
                    Divider()
                    Text(
                        video.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun StatusLine(text: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Default.CheckCircle, null, tint = color, modifier = Modifier.size(18.dp))
        Text(
            text,
            style = MaterialTheme.typography.bodySmall,
            color = color,
            modifier = Modifier.padding(start = 6.dp),
        )
    }
}

/**
 * 自動再生・未視聴のみ再生のトグル。自動再生は**既定オフ**で、ここでオンにした場合だけ働く。
 */
@Composable
private fun PlaybackToggles(
    autoPlayNext: Boolean,
    unwatchedOnly: Boolean,
    repeatMode: RepeatMode,
    onAutoPlayChange: (Boolean) -> Unit,
    onUnwatchedOnlyChange: (Boolean) -> Unit,
) {
    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(
                        stringResource(
                            if (autoPlayNext) R.string.player_autoplay_on_title
                            else R.string.player_autoplay_off_title
                        ),
                        style = MaterialTheme.typography.titleSmall,
                    )
                    Text(
                        stringResource(
                            if (autoPlayNext) R.string.player_autoplay_on_detail
                            else R.string.player_autoplay_off_detail
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = autoPlayNext, onCheckedChange = onAutoPlayChange)
            }
            Divider()
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.player_unwatchedonly), modifier = Modifier.weight(1f))
                Switch(checked = unwatchedOnly, onCheckedChange = onUnwatchedOnlyChange)
            }
            Text(
                buildString {
                    append(stringResource(R.string.player_mode_skip))
                    if (unwatchedOnly) append(stringResource(R.string.player_mode_unwatchedonly))
                    when (repeatMode) {
                        RepeatMode.One -> append(stringResource(R.string.player_mode_repeatone))
                        RepeatMode.All -> append(stringResource(R.string.player_mode_repeatall))
                        RepeatMode.Off -> Unit
                    }
                },
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** [最初へ / 前へ / 戻す / 次へ / 最後へ] の5つ。 */
@Composable
private fun NavigationButtons(
    canGoPrevious: Boolean,
    canGoNext: Boolean,
    canGoBack: Boolean,
    onFirst: () -> Unit,
    onPrevious: () -> Unit,
    onUndo: () -> Unit,
    onNext: () -> Unit,
    onLast: () -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        NavButton(R.string.player_nav_first, Icons.Default.SkipPrevious, canGoPrevious, onFirst, Modifier.weight(1f))
        NavButton(R.string.player_nav_previous, Icons.Default.FastRewind, canGoPrevious, onPrevious, Modifier.weight(1f))
        NavButton(R.string.player_nav_undo, Icons.Default.Undo, canGoBack, onUndo, Modifier.weight(1f))
        NavButton(R.string.player_nav_next, Icons.Default.FastForward, canGoNext, onNext, Modifier.weight(1f))
        NavButton(R.string.player_nav_last, Icons.Default.SkipNext, canGoNext, onLast, Modifier.weight(1f))
    }
}

@Composable
private fun NavButton(
    labelRes: Int,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier,
        contentPadding = androidx.compose.foundation.layout.PaddingValues(4.dp),
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(icon, null, modifier = Modifier.size(20.dp))
            Text(
                stringResource(labelRes),
                style = MaterialTheme.typography.labelSmall,
                textAlign = TextAlign.Center,
                maxLines = 1,
            )
        }
    }
}

/** リピートの状態を表すボタン（オフ＝枠線／1本＝1／全体＝ALL）。 */
@Composable
private fun RepeatBadgeButton(mode: RepeatMode, onClick: () -> Unit) {
    val description = stringResource(
        when (mode) {
            RepeatMode.Off -> R.string.repeat_a11y_off
            RepeatMode.One -> R.string.repeat_a11y_one
            RepeatMode.All -> R.string.repeat_a11y_all
        }
    )
    IconButton(onClick = onClick) {
        Box(contentAlignment = Alignment.Center) {
            Icon(
                imageVector = when (mode) {
                    RepeatMode.Off -> Icons.Default.Repeat
                    RepeatMode.One -> Icons.Default.RepeatOne
                    RepeatMode.All -> Icons.Default.RepeatOn
                },
                contentDescription = description,
                tint = if (mode.isActive) WatchedGreen else MaterialTheme.colorScheme.onSurfaceVariant,
            )
            // 「ALL」は記号だけだと伝わりにくいので、小さく文字を添える。
            if (mode == RepeatMode.All) {
                Text(
                    "ALL",
                    style = MaterialTheme.typography.labelSmall,
                    color = WatchedGreen,
                    modifier = Modifier.padding(top = 22.dp),
                )
            }
        }
    }
}

/** 指定の間だけ画面を消させない。 */
@Composable
private fun KeepScreenOn(enabled: Boolean) {
    val view = androidx.compose.ui.platform.LocalView.current
    androidx.compose.runtime.DisposableEffect(enabled) {
        view.keepScreenOn = enabled
        onDispose { view.keepScreenOn = false }
    }
}
