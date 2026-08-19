package com.deskflowlabs.channeltimelineviewer

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.network.SharedLinkParser
import com.deskflowlabs.channeltimelineviewer.ui.AboutScreen
import com.deskflowlabs.channeltimelineviewer.ui.ChannelInputScreen
import com.deskflowlabs.channeltimelineviewer.ui.PlaybackOptionsSheet
import com.deskflowlabs.channeltimelineviewer.ui.PlayerScreen
import com.deskflowlabs.channeltimelineviewer.ui.VideoListScreen
import com.deskflowlabs.channeltimelineviewer.ui.theme.ChannelTimelineTheme
import com.deskflowlabs.channeltimelineviewer.viewmodel.ChannelInputViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.VideoListViewModel
import kotlinx.coroutines.flow.MutableStateFlow

/**
 * 画面はこの1つの Activity 内で切り替える（3画面なので Navigation ライブラリは使わない）。
 */
class MainActivity : ComponentActivity() {

    private lateinit var container: AppContainer

    /** 共有（ACTION_SEND）で受け取った YouTube URL。 */
    private val sharedUrl = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        container = AppContainer(this)
        handleShareIntent(intent)

        setContent {
            ChannelTimelineTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    AppRoot(container, sharedUrl)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent)
    }

    /**
     * YouTube アプリやブラウザからの共有を受け取る。
     * iOS と違って Android は共有からアプリを直接開けるので、そのまま一覧まで進む。
     */
    private fun handleShareIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val text = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        SharedLinkParser.extractYouTubeUrl(text)?.let { sharedUrl.value = it }
    }
}

/** いま表示している画面。 */
private sealed interface Screen {
    data object Input : Screen
    data object About : Screen
    data class Videos(val channel: Channel) : Screen
    data class Play(val channel: Channel, val videos: List<VideoItem>, val index: Int) : Screen
}

@Composable
private fun AppRoot(container: AppContainer, sharedUrl: MutableStateFlow<String?>) {
    var screen by remember { mutableStateOf<Screen>(Screen.Input) }
    var showOptions by remember { mutableStateOf(false) }

    val inputViewModel: ChannelInputViewModel = viewModel(
        factory = simpleFactory { ChannelInputViewModel(container.api, container.favorites) }
    )
    val resolved by inputViewModel.resolvedChannel.collectAsStateWithLifecycle()
    val shared by sharedUrl.collectAsStateWithLifecycle()

    // 共有された URL が届いたらチャンネルを特定して開く。
    LaunchedEffect(shared) {
        val url = shared ?: return@LaunchedEffect
        sharedUrl.value = null
        screen = Screen.Input
        inputViewModel.openSharedLink(url)
    }

    LaunchedEffect(resolved) {
        val channel = resolved ?: return@LaunchedEffect
        inputViewModel.consumeResolvedChannel()
        screen = Screen.Videos(channel)
    }

    when (val current = screen) {
        is Screen.Input -> ChannelInputScreen(
            viewModel = inputViewModel,
            favorites = container.favorites,
            progressStore = container.progress,
            isApiConfigured = container.isApiConfigured,
            onOpenAbout = { screen = Screen.About },
            onOpenFavorite = { favorite -> inputViewModel.open(favorite.toChannel()) },
        )

        is Screen.About -> AboutScreen(onBack = { screen = Screen.Input })

        is Screen.Videos -> VideoListRoute(
            container = container,
            channel = current.channel,
            onBack = { screen = Screen.Input },
            onOpenVideo = { videos, index ->
                screen = Screen.Play(current.channel, videos, index.coerceAtLeast(0))
            },
        )

        is Screen.Play -> {
            val playerViewModel: PlayerViewModel = viewModel(
                key = "player-${current.channel.id}-${current.index}",
                factory = simpleFactory {
                    PlayerViewModel(
                        videos = current.videos,
                        startIndex = current.index,
                        watchStore = container.watchStore,
                        skipStore = container.skipStore,
                        positionStore = container.positionStore,
                        settings = container.settings,
                    )
                },
            )
            val index by playerViewModel.currentIndex.collectAsStateWithLifecycle()

            // 「続きから見る」のために、最後に開いた動画を記録する。
            LaunchedEffect(index) {
                playerViewModel.currentVideo?.let {
                    container.progress.recordOpened(current.channel.id, it.id)
                }
            }

            PlayerScreen(
                viewModel = playerViewModel,
                channel = current.channel,
                settings = container.settings,
                memoStore = container.memoStore,
                onBack = { screen = Screen.Videos(current.channel) },
                onOpenOptions = { showOptions = true },
            )

            if (showOptions) {
                PlaybackOptionsSheet(
                    viewModel = playerViewModel,
                    onDismiss = { showOptions = false },
                )
            }
        }
    }
}

@Composable
private fun VideoListRoute(
    container: AppContainer,
    channel: Channel,
    onBack: () -> Unit,
    onOpenVideo: (List<VideoItem>, Int) -> Unit,
) {
    val listViewModel: VideoListViewModel = viewModel(
        key = "list-${channel.id}",
        factory = simpleFactory {
            VideoListViewModel(channel, container.api, container.videoListCache)
        },
    )
    LaunchedEffect(channel.id) { listViewModel.loadIfNeeded() }

    // 一覧の件数を進捗に反映する（ホームのお気に入り行に出る）。
    val videos by listViewModel.videos.collectAsStateWithLifecycle()
    val watched by container.watchStore.watched.collectAsStateWithLifecycle()
    LaunchedEffect(videos.size, watched.size) {
        if (videos.isNotEmpty()) {
            container.progress.updateCounts(
                channelId = channel.id,
                totalCount = videos.size,
                watchedCount = videos.count { it.id in watched },
            )
        }
    }

    VideoListScreen(
        viewModel = listViewModel,
        watchStore = container.watchStore,
        skipStore = container.skipStore,
        onBack = onBack,
        onOpenVideo = onOpenVideo,
    )
}

/** ViewModel を引数付きで作るための最小のファクトリ。 */
private inline fun <reified T : ViewModel> simpleFactory(crossinline create: () -> T) =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = create() as VM
    }
