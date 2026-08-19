package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Divider
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.ui.theme.SkippedOrange
import com.deskflowlabs.channeltimelineviewer.ui.theme.WatchedGreen
import com.deskflowlabs.channeltimelineviewer.viewmodel.VideoListViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.WatchFilter
import java.text.DateFormat
import java.util.Date

/**
 * 動画一覧。iOS 版 `Views/VideoListView.swift` に対応する。
 *
 * 行をタップで再生画面、右のチェックで視聴済みの切り替え、長押しでスキップの切り替え。
 * （iOS はスワイプ操作。Android は長押し/ボタンの方が馴染むのでこの形にしている）
 */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun VideoListScreen(
    viewModel: VideoListViewModel,
    watchStore: WatchHistoryStore,
    skipStore: SkippedVideoStore,
    onBack: () -> Unit,
    onOpenVideo: (List<VideoItem>, Int) -> Unit,
) {
    val videos by viewModel.videos.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val isCheckingForNew by viewModel.isCheckingForNew.collectAsStateWithLifecycle()
    val lastUpdatedAt by viewModel.lastUpdatedAt.collectAsStateWithLifecycle()
    val errorRes by viewModel.errorRes.collectAsStateWithLifecycle()
    val sortAscending by viewModel.sortAscending.collectAsStateWithLifecycle()
    val filter by viewModel.watchFilter.collectAsStateWithLifecycle()
    val watched by watchStore.watched.collectAsStateWithLifecycle()
    val skipped by skipStore.skipped.collectAsStateWithLifecycle()

    val isWatched: (String) -> Boolean = { it in watched }
    val isSkipped: (String) -> Boolean = { it in skipped }

    // 並び替え・絞り込みの結果は remember で持つ。
    // ここで毎回作り直すと、LazyColumn の中身が古い値を掴んだままになり
    //（5,000本のチャンネルで「0本表示」になる不具合が出た）、並び替えの計算も無駄に走る。
    val visible = remember(videos, watched, skipped, filter, sortAscending) {
        viewModel.visibleVideos(isWatched)
    }
    val oldestFirst = remember(videos) { viewModel.oldestFirst() }
    val next = remember(videos, watched, skipped) { viewModel.nextUnwatched(isWatched, isSkipped) }
    val nextPosition = remember(videos, watched, skipped) {
        viewModel.nextUnwatchedPosition(isWatched, isSkipped)
    }

    var menuOpen by remember { mutableStateOf(false) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(viewModel.channel.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.Default.ArrowBack, null) }
                },
                actions = {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Default.Sort, stringResource(R.string.list_menu_a11y))
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        Text(
                            stringResource(R.string.list_menu_sort),
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                        listOf(true to R.string.list_sort_oldest, false to R.string.list_sort_newest)
                            .forEach { (ascending, label) ->
                                DropdownMenuItem(
                                    text = { Text(stringResource(label)) },
                                    leadingIcon = {
                                        RadioButton(selected = sortAscending == ascending, onClick = null)
                                    },
                                    onClick = {
                                        viewModel.setSortAscending(ascending)
                                        menuOpen = false
                                    },
                                )
                            }
                        Divider()
                        Text(
                            stringResource(R.string.list_menu_show),
                            style = MaterialTheme.typography.labelMedium,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                        WatchFilter.entries.forEach { value ->
                            DropdownMenuItem(
                                text = { Text(stringResource(value.labelRes)) },
                                leadingIcon = { RadioButton(selected = filter == value, onClick = null) },
                                onClick = {
                                    viewModel.setWatchFilter(value)
                                    menuOpen = false
                                },
                            )
                        }
                        Divider()
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.list_menu_checknew)) },
                            leadingIcon = { Icon(Icons.Default.Refresh, null) },
                            onClick = {
                                viewModel.checkForNewVideos()
                                menuOpen = false
                            },
                        )
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.list_menu_reloadall)) },
                            onClick = {
                                viewModel.reloadAll()
                                menuOpen = false
                            },
                        )
                    }
                },
            )
        },
    ) { padding ->
        if (isLoading && videos.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator()
                Text(
                    stringResource(R.string.list_loading),
                    modifier = Modifier.padding(top = 12.dp),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            return@Scaffold
        }

        LazyColumn(modifier = Modifier.fillMaxSize().padding(padding)) {
            item {
                ProgressHeader(
                    watchedCount = watchStore.watchedCount(videos.map { it.id }),
                    totalCount = videos.size,
                )
            }

            if (next != null && nextPosition != null) {
                item {
                    NextToWatchRow(
                        video = next,
                        position = nextPosition,
                        isResume = watched.isNotEmpty(),
                        onOpen = { onOpenVideo(oldestFirst, oldestFirst.indexOf(next)) },
                    )
                }
            } else if (videos.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.list_allwatched),
                        modifier = Modifier.padding(16.dp),
                        color = WatchedGreen,
                    )
                }
            }

            if (isCheckingForNew) {
                item {
                    Text(
                        stringResource(R.string.list_checkingnew),
                        modifier = Modifier.padding(horizontal = 16.dp),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            } else {
                lastUpdatedAt?.let { updated ->
                    item {
                        Text(
                            stringResource(
                                R.string.list_cached_format,
                                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
                                    .format(Date(updated * 1000)),
                            ),
                            modifier = Modifier.padding(horizontal = 16.dp),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            errorRes?.let { res ->
                item {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            stringResource(R.string.list_error_title),
                            style = MaterialTheme.typography.titleSmall,
                        )
                        Text(stringResource(res), color = MaterialTheme.colorScheme.error)
                        TextButton(onClick = { viewModel.load() }) {
                            Text(stringResource(R.string.common_retry))
                        }
                    }
                }
            }

            item {
                Text(
                    stringResource(
                        R.string.list_count_format,
                        visible.size.toString(),
                        videos.size.toString(),
                    ),
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            items(visible, key = { it.id }) { video ->
                VideoRow(
                    video = video,
                    watched = isWatched(video.id),
                    skipped = isSkipped(video.id),
                    onOpen = { onOpenVideo(oldestFirst, oldestFirst.indexOf(video)) },
                    onToggleWatched = { watchStore.toggleWatched(video.id) },
                    onToggleSkipped = { skipStore.toggleSkipped(video.id) },
                )
                Divider()
            }
        }
    }
}

@Composable
private fun ProgressHeader(watchedCount: Int, totalCount: Int) {
    val rate = if (totalCount <= 0) 0f else watchedCount.toFloat() / totalCount
    Column(Modifier.padding(16.dp)) {
        Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.progress_title), style = MaterialTheme.typography.titleSmall)
            Row(modifier = Modifier.weight(1f), horizontalArrangement = Arrangement.End) {
                Text(
                    stringResource(
                        R.string.progress_count_format,
                        watchedCount.toString(),
                        totalCount.toString(),
                        (rate * 100).toInt().toString(),
                    ),
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
        LinearProgressIndicator(
            progress = { rate },
            modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
        )
    }
}

@Composable
private fun NextToWatchRow(video: VideoItem, position: Int, isResume: Boolean, onOpen: () -> Unit) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clip(RoundedCornerShape(12.dp)),
        onClick = onOpen,
    ) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            AsyncImage(
                model = video.thumbnailUrl,
                contentDescription = null,
                modifier = Modifier.width(88.dp).height(50.dp).clip(RoundedCornerShape(6.dp)),
            )
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(
                    stringResource(
                        if (isResume) R.string.list_next_resume_format else R.string.list_next_new_format,
                        position.toString(),
                    ),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Text(video.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
            Icon(Icons.Default.PlayArrow, null)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun VideoRow(
    video: VideoItem,
    watched: Boolean,
    skipped: Boolean,
    onOpen: () -> Unit,
    onToggleWatched: () -> Unit,
    onToggleSkipped: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            // タップで再生、長押しでスキップの切り替え（iOS のスワイプ操作に相当）。
            .combinedClickable(onClick = onOpen, onLongClick = onToggleSkipped)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = video.thumbnailUrl,
            contentDescription = null,
            modifier = Modifier.width(120.dp).height(68.dp).clip(RoundedCornerShape(6.dp)),
        )
        Column(Modifier.weight(1f).padding(horizontal = 12.dp)) {
            Text(video.title, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                DateFormat.getDateInstance(DateFormat.MEDIUM)
                    .format(Date(video.publishedAtEpochSeconds * 1000)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            IconButton(onClick = onToggleWatched) {
                Icon(
                    Icons.Default.CheckCircle,
                    stringResource(if (watched) R.string.video_markunwatched else R.string.video_watched),
                    tint = if (watched) WatchedGreen else MaterialTheme.colorScheme.outlineVariant,
                )
            }
            if (skipped) {
                Icon(
                    Icons.Default.CheckCircle,
                    stringResource(R.string.video_skip),
                    tint = SkippedOrange,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}
