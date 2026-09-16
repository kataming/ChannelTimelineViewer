package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.viewmodel.WatchQueuePlayerViewModel

/**
 * Watch Queue を順番に再生する画面。
 *
 * 公式プレイヤー（`YouTubePlayerWebView`）と自動再生スイッチだけを通常再生と共有し、
 * 保存（視聴済み・スキップ・メモ・再生位置・チャンネル進捗）には**一切触れない**。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchQueuePlayerScreen(
    viewModel: WatchQueuePlayerViewModel,
    settings: PlaybackSettingsStore,
    onBack: () -> Unit,
) {
    val currentIndex by viewModel.currentIndex.collectAsStateWithLifecycle()
    val autoPlayNext by settings.autoPlayNext.collectAsStateWithLifecycle()
    val showEnded by viewModel.showEndedSuggestion.collectAsStateWithLifecycle()
    val isCompleted by viewModel.isCompleted.collectAsStateWithLifecycle()
    val playedIds by viewModel.playedIds.collectAsStateWithLifecycle()
    val current = viewModel.items.getOrNull(currentIndex)

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        viewModel.queueName.ifBlank { stringResource(R.string.watchqueue_title) },
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close))
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (current != null) {
                YouTubePlayerWebView(
                    videoId = current.videoId,
                    startSeconds = 0.0,
                    command = null,
                    autoplayOnLoad = true,
                    onStateChange = { viewModel.handleState(it) },
                    onTimeUpdate = { _, _, _ -> },
                    onOptions = { },
                    onNearEnd = { viewModel.handleNearEnd(it) },
                    modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
                )
            }

            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    Column(Modifier.padding(top = 12.dp)) {
                        Text(
                            current?.title?.ifBlank { stringResource(R.string.watchqueue_untitled) }
                                ?: stringResource(R.string.watchqueue_untitled),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        if (!current?.channelName.isNullOrBlank()) {
                            Text(
                                current!!.channelName,
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        Text(
                            viewModel.positionText(),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }

                if (isCompleted) {
                    item {
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text(
                                    stringResource(R.string.watchqueue_completed),
                                    style = MaterialTheme.typography.titleSmall,
                                )
                                Text(
                                    stringResource(R.string.watchqueue_completed_detail),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                TextButton(onClick = { viewModel.restartQueue() }) {
                                    Text(stringResource(R.string.watchqueue_restart))
                                }
                            }
                        }
                    }
                } else if (showEnded) {
                    item {
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(12.dp)) {
                                Text(
                                    viewModel.nextItem?.title?.ifBlank {
                                        stringResource(R.string.watchqueue_untitled)
                                    } ?: stringResource(R.string.watchqueue_untitled),
                                    style = MaterialTheme.typography.bodySmall,
                                )
                                TextButton(onClick = { viewModel.goNext() }) {
                                    Text(stringResource(R.string.watchqueue_playnext))
                                }
                            }
                        }
                    }
                }

                item {
                    // 連続再生はユーザーが自分で選んだときだけ働く（通常再生と同じ設定）。
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.watchqueue_autoplay), Modifier.weight(1f))
                        Switch(checked = autoPlayNext, onCheckedChange = { settings.setAutoPlayNext(it) })
                    }
                }

                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(onClick = { viewModel.goFirst() }, enabled = viewModel.canGoPrevious) {
                            Text(stringResource(R.string.player_nav_first))
                        }
                        TextButton(onClick = { viewModel.goPrevious() }, enabled = viewModel.canGoPrevious) {
                            Text(stringResource(R.string.player_nav_previous))
                        }
                        TextButton(onClick = { viewModel.goNext() }, enabled = viewModel.canGoNext) {
                            Text(stringResource(R.string.player_nav_next))
                        }
                        TextButton(onClick = { viewModel.goLast() }, enabled = viewModel.canGoNext) {
                            Text(stringResource(R.string.player_nav_last))
                        }
                    }
                }

                itemsIndexed(viewModel.items, key = { _, item -> item.videoId }) { index, item ->
                    Row(
                        modifier = Modifier.fillMaxWidth().clickable { viewModel.move(index) },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            "${index + 1}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            item.title.ifBlank { stringResource(R.string.watchqueue_untitled) },
                            modifier = Modifier.weight(1f).padding(start = 12.dp),
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            style = if (index == currentIndex) {
                                MaterialTheme.typography.bodyMedium
                            } else {
                                MaterialTheme.typography.bodySmall
                            },
                        )
                        if (playedIds.contains(item.videoId)) {
                            // 再生し終えた印。画面の中だけのもので、視聴記録には保存しない。
                            Icon(
                                Icons.Default.Check,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        }
    }
}
