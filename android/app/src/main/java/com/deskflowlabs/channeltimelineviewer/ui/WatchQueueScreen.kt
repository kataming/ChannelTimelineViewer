package com.deskflowlabs.channeltimelineviewer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.deskflowlabs.channeltimelineviewer.R
import com.deskflowlabs.channeltimelineviewer.data.WatchQueueStore
import com.deskflowlabs.channeltimelineviewer.network.WatchQueue
import com.deskflowlabs.channeltimelineviewer.network.WatchQueueError
import kotlinx.coroutines.launch

/**
 * Watch Queue（V2）の入口。接続していなければ接続、していればキューの一覧を出す。
 *
 * この画面は **サーバーの Feature Flag が ON のときだけ**開ける（`WatchQueueStore.isAvailable`）。
 * 接続していない人・Flag が OFF の人には、アプリのどこにもこの機能は現れない。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WatchQueueScreen(
    store: WatchQueueStore,
    isPro: Boolean,
    savedChannelCount: Int,
    onBack: () -> Unit,
    onOpenQueue: (WatchQueue) -> Unit,
) {
    val queues by store.queues.collectAsStateWithLifecycle()
    val isPaired by store.isPaired.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var errorRes by remember { mutableStateOf<Int?>(null) }
    var showDisconnectConfirm by remember { mutableStateOf(false) }

    LaunchedEffect(isPaired) {
        if (!isPaired) return@LaunchedEffect
        store.loadQueues()
        store.reportEntitlement(isPro, savedChannelCount)
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.watchqueue_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.common_close))
                    }
                },
            )
        },
    ) { padding ->
        // 解除は取り消せないので、押し間違いで外れないよう一度確かめる。
        if (showDisconnectConfirm) {
            AlertDialog(
                onDismissRequest = { showDisconnectConfirm = false },
                title = { Text(stringResource(R.string.watchqueue_disconnect_confirm)) },
                text = { Text(stringResource(R.string.watchqueue_disconnect_detail)) },
                confirmButton = {
                    TextButton(onClick = {
                        showDisconnectConfirm = false
                        scope.launch { store.disconnect() }
                    }) {
                        Text(
                            stringResource(R.string.watchqueue_disconnect),
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                },
                dismissButton = {
                    TextButton(onClick = { showDisconnectConfirm = false }) {
                        Text(stringResource(R.string.common_cancel))
                    }
                },
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding).padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (!isPaired) {
                item {
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                stringResource(R.string.watchqueue_pair_title),
                                style = MaterialTheme.typography.titleSmall,
                            )
                            Text(
                                stringResource(R.string.watchqueue_pair_detail),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                            OutlinedTextField(
                                value = code,
                                onValueChange = { code = it },
                                singleLine = true,
                                label = { Text(stringResource(R.string.watchqueue_pair_field)) },
                                keyboardOptions = KeyboardOptions(
                                    capitalization = KeyboardCapitalization.Characters,
                                ),
                                modifier = Modifier.fillMaxWidth(),
                            )
                            Button(
                                onClick = {
                                    busy = true
                                    errorRes = null
                                    scope.launch {
                                        val failure = store.pair(code)
                                        errorRes = failure?.let(::messageFor)
                                        if (failure == null) code = ""
                                        busy = false
                                    }
                                },
                                enabled = !busy && code.isNotBlank(),
                            ) {
                                Text(stringResource(R.string.watchqueue_pair_button))
                            }
                        }
                    }
                }
            } else {
                if (queues.isEmpty()) {
                    item {
                        Card(Modifier.fillMaxWidth()) {
                            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    stringResource(R.string.watchqueue_empty_title),
                                    style = MaterialTheme.typography.titleSmall,
                                )
                                Text(
                                    stringResource(R.string.watchqueue_empty_detail),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                } else {
                    item {
                        Text(
                            stringResource(R.string.watchqueue_list_header),
                            style = MaterialTheme.typography.titleSmall,
                        )
                    }
                    items(queues, key = { it.queueId }) { queue ->
                        Card(Modifier.fillMaxWidth().clickable { onOpenQueue(queue) }) {
                            Column(Modifier.padding(12.dp)) {
                                Text(queue.name.ifBlank { stringResource(R.string.watchqueue_title) })
                                Text(
                                    stringResource(R.string.watchqueue_count_format, queue.items.size),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }

                item {
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(
                            stringResource(R.string.watchqueue_connected),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        TextButton(onClick = {
                            scope.launch {
                                busy = true
                                errorRes = store.loadQueues()?.let(::messageFor)
                                busy = false
                            }
                        }) {
                            Text(stringResource(R.string.watchqueue_refresh))
                        }
                        TextButton(onClick = { showDisconnectConfirm = true }) {
                            Text(
                                stringResource(R.string.watchqueue_disconnect),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        Text(
                            stringResource(R.string.watchqueue_disconnect_detail),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }

            errorRes?.let { messageRes ->
                item {
                    Text(
                        stringResource(messageRes),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                }
            }
        }
    }
}

/** サーバーからの失敗を、利用者に見せる文言に対応づける。 */
private fun messageFor(error: WatchQueueError): Int = when (error) {
    WatchQueueError.NETWORK -> R.string.watchqueue_error_network
    WatchQueueError.DISABLED -> R.string.watchqueue_error_disabled
    WatchQueueError.UNAUTHORIZED -> R.string.watchqueue_error_unauthorized
    WatchQueueError.CODE -> R.string.watchqueue_error_code
    WatchQueueError.EXPIRED -> R.string.watchqueue_error_expired
    WatchQueueError.USED -> R.string.watchqueue_error_used
    WatchQueueError.TOO_MANY -> R.string.watchqueue_error_toomany
    WatchQueueError.GENERIC -> R.string.watchqueue_error_generic
}
