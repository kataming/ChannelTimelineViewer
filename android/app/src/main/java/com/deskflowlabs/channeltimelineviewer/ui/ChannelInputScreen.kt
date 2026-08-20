package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import coil.compose.AsyncImage
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.ChannelProgressStore
import com.deskflowlabs.channeltimelineviewer.data.FavoriteChannelStore
import com.deskflowlabs.channeltimelineviewer.model.FavoriteChannel
import com.deskflowlabs.channeltimelineviewer.viewmodel.ChannelInputViewModel
import java.text.DateFormat
import java.util.Date

/**
 * 最初の画面。チャンネルURLの入力と、最近使ったチャンネルの一覧。
 * iOS 版 `Views/ChannelInputView.swift` に対応する。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChannelInputScreen(
    viewModel: ChannelInputViewModel,
    favorites: FavoriteChannelStore,
    progressStore: ChannelProgressStore,
    isApiConfigured: Boolean,
    isPro: Boolean,
    onOpenAbout: () -> Unit,
    onOpenPro: () -> Unit,
    onOpenFavorite: (FavoriteChannel) -> Unit,
) {
    val urlText by viewModel.urlText.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorRes by viewModel.errorRes.collectAsStateWithLifecycle()
    val favoriteList by favorites.favorites.collectAsStateWithLifecycle()
    val progressMap by progressStore.progress.collectAsStateWithLifecycle()
    val pendingUpgrade by viewModel.pendingUpgrade.collectAsStateWithLifecycle()
    val pendingDeletion by viewModel.pendingDeletion.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Channel Timeline") },
                actions = {
                    IconButton(onClick = onOpenAbout) {
                        Icon(Icons.Default.Info, stringResource(R.string.about_open_a11y))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!isApiConfigured) {
                item {
                    Card(modifier = Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp)) {
                            Text(
                                stringResource(R.string.api_notconfigured_title),
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.error,
                            )
                            Text(
                                stringResource(R.string.api_notconfigured_detail),
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                    }
                }
            }

            item {
                Text(
                    stringResource(R.string.input_section_header),
                    style = MaterialTheme.typography.titleSmall,
                )
            }

            item {
                OutlinedTextField(
                    value = urlText,
                    onValueChange = viewModel::setUrlText,
                    modifier = Modifier.fillMaxWidth(),
                    singleLine = true,
                    placeholder = { Text("https://www.youtube.com/@handle") },
                    trailingIcon = {
                        if (urlText.isNotEmpty()) {
                            IconButton(onClick = { viewModel.setUrlText("") }) {
                                Icon(Icons.Default.Clear, stringResource(R.string.input_clear_a11y))
                            }
                        }
                    },
                )
            }

            item {
                Button(
                    onClick = viewModel::fetch,
                    enabled = !isLoading && urlText.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                        )
                    }
                    Text(
                        text = stringResource(
                            if (isLoading) R.string.input_fetching else R.string.input_fetch
                        ),
                        modifier = Modifier.padding(start = if (isLoading) 8.dp else 0.dp),
                    )
                }
            }

            errorRes?.let { res ->
                item {
                    Text(
                        stringResource(res),
                        color = MaterialTheme.colorScheme.error,
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
            }

            item {
                Text(
                    // Android は共有からそのままアプリが開くので、iOS とは説明を変えている。
                    stringResource(R.string.input_share_android, stringResource(R.string.app_name)),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }

            item {
                ProEntryCard(isPro = isPro, onOpen = onOpenPro)
            }

            if (favoriteList.isNotEmpty()) {
                item {
                    Text(
                        stringResource(R.string.favorites_section_header),
                        style = MaterialTheme.typography.titleSmall,
                    )
                }
                items(favoriteList, key = { it.id }) { favorite ->
                    FavoriteRow(
                        favorite = favorite,
                        watchedCount = progressMap[favorite.id]?.watchedCount ?: 0,
                        totalCount = progressMap[favorite.id]?.totalCount ?: 0,
                        onOpen = { onOpenFavorite(favorite) },
                        onDelete = { viewModel.askToDelete(favorite) },
                    )
                }
                item {
                    Text(
                        stringResource(R.string.favorites_section_footer_android),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            item {
                Text(
                    stringResource(R.string.disclaimer_short),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 24.dp),
                )
            }
        }
    }

    pendingUpgrade?.let { pending ->
        AlertDialog(
            onDismissRequest = viewModel::dismissPendingUpgrade,
            title = { Text(stringResource(R.string.pro_limit_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    // 記録が消えることは取り返しがつかないので、いちばん目立たせる。
                    Text(
                        stringResource(
                            R.string.pro_limit_warning_format,
                            pending.savedChannelTitle,
                        ),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.error,
                    )
                    Text(
                        stringResource(R.string.pro_limit_replacehint),
                        style = MaterialTheme.typography.bodyMedium,
                    )

                    // 記録を失わずに済む道（Pro）を、失う操作より上に置く。
                    Button(
                        onClick = onOpenPro,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.pro_limit_viewpro))
                    }
                    OutlinedButton(
                        onClick = viewModel::replaceSavedChannel,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                    ) {
                        Text(stringResource(R.string.pro_limit_replace))
                    }
                    TextButton(
                        onClick = viewModel::dismissPendingUpgrade,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.common_cancel))
                    }
                }
            },
            confirmButton = {},
        )
    }

    pendingDeletion?.let { target ->
        AlertDialog(
            onDismissRequest = viewModel::dismissDeletion,
            title = { Text(stringResource(R.string.favorites_delete_title)) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(
                        stringResource(R.string.favorites_delete_warning_format, target.title),
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.Bold,
                        color = MaterialTheme.colorScheme.error,
                    )
                    if (!isPro) {
                        Text(
                            stringResource(R.string.pro_limit_replacehint),
                            style = MaterialTheme.typography.bodyMedium,
                        )
                        Button(onClick = onOpenPro, modifier = Modifier.fillMaxWidth()) {
                            Text(stringResource(R.string.pro_limit_viewpro))
                        }
                    }
                    OutlinedButton(
                        onClick = viewModel::confirmDeletion,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                    ) {
                        Text(stringResource(R.string.common_delete))
                    }
                    TextButton(
                        onClick = viewModel::dismissDeletion,
                        modifier = Modifier.fillMaxWidth(),
                    ) {
                        Text(stringResource(R.string.common_cancel))
                    }
                }
            },
            confirmButton = {},
        )
    }
}

/** Pro（複数チャンネル保存）への入口。無料のうちは案内、購入後は状態表示になる。 */
@Composable
private fun ProEntryCard(isPro: Boolean, onOpen: () -> Unit) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Column(Modifier.padding(12.dp)) {
            Text(
                stringResource(if (isPro) R.string.pro_owned else R.string.pro_entry_title),
                style = MaterialTheme.typography.titleSmall,
            )
            if (!isPro) {
                Text(
                    stringResource(R.string.pro_entry_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun FavoriteRow(
    favorite: FavoriteChannel,
    watchedCount: Int,
    totalCount: Int,
    onOpen: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth().clickable(onClick = onOpen)) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AsyncImage(
                    model = favorite.thumbnailUrl,
                    contentDescription = null,
                    modifier = Modifier.size(44.dp).clip(CircleShape),
                )
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(favorite.title, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(
                        stringResource(
                            R.string.favorites_lastopened_format,
                            formatDateTime(favorite.lastOpenedAtEpochSeconds),
                        ),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                IconButton(onClick = onDelete) {
                    Icon(Icons.Default.Delete, stringResource(R.string.common_delete))
                }
            }

            if (totalCount > 0) {
                val rate = watchedCount.toFloat() / totalCount
                LinearProgressIndicator(
                    progress = { rate },
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                )
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        stringResource(
                            R.string.favorites_progress_format,
                            watchedCount.toString(),
                            totalCount.toString(),
                            (rate * 100).toInt().toString(),
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    Row(
                        modifier = Modifier.weight(1f),
                        horizontalArrangement = Arrangement.End,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Default.PlayArrow, null, modifier = Modifier.size(18.dp))
                        Text(
                            stringResource(R.string.favorites_resume),
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                }
            }
        }
    }
}
