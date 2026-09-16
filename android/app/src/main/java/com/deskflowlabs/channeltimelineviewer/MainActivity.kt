package com.deskflowlabs.channeltimelineviewer

import android.content.Intent
import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.model.VideoItem
import com.deskflowlabs.channeltimelineviewer.network.SharedLinkParser
import com.deskflowlabs.channeltimelineviewer.ui.AboutScreen
import com.deskflowlabs.channeltimelineviewer.ui.BadgePreviewScreen
import com.deskflowlabs.channeltimelineviewer.ui.ChannelInputScreen
import com.deskflowlabs.channeltimelineviewer.ui.ChannelTutorialSheet
import com.deskflowlabs.channeltimelineviewer.ui.PlaybackOptionsSheet
import com.deskflowlabs.channeltimelineviewer.ui.PlayerScreen
import com.deskflowlabs.channeltimelineviewer.ui.ProScreen
import com.deskflowlabs.channeltimelineviewer.ui.VideoListScreen
import com.deskflowlabs.channeltimelineviewer.ui.theme.ChannelTimelineTheme
import com.deskflowlabs.channeltimelineviewer.viewmodel.ChannelInputViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.PlayerViewModel
import com.deskflowlabs.channeltimelineviewer.viewmodel.VideoListViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import java.util.Locale

/**
 * 画面はこの1つの Activity 内で切り替える（3画面なので Navigation ライブラリは使わない）。
 */
class MainActivity : ComponentActivity() {

    private lateinit var container: AppContainer

    /** 共有（ACTION_SEND）で受け取った YouTube URL。 */
    private val sharedUrl = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        // 画面の端から端まで描く（Android 15 以降は既定の挙動。それより前の端末でも見た目を揃える）。
        // 各画面は Scaffold の余白をそのまま使っているので、上下のバーに文字が潜り込むことはない。
        // 全画面再生（onShowCustomView）は WindowInsetsControllerCompat でバーを隠す作りなので、
        // この設定と両立する。
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        container = AppContainer(this)
        container.billing.start()
        handleShareIntent(intent)

        // デバッグビルドでのみ使う確認用の入り口。
        //   --es preview badge … バッジの見た目確認
        //   --es locale ja      … 表示言語を切り替える（ストア用スクショを言語別に撮るため）
        val previewName = if (BuildConfig.DEBUG) intent?.getStringExtra("preview") else null
        val localeTag = if (BuildConfig.DEBUG) intent?.getStringExtra("locale") else null
        // スクリーンショット撮影では「チャンネルの追加方法」の案内が邪魔になる。
        // 初回起動で自動的に前に出るため、これが無いと入力欄が隠れて撮影が失敗する
        // （iOS 側で実際に起きた。--ez skipTutorial true で止める）。
        val skipTutorial = BuildConfig.DEBUG && intent?.getBooleanExtra("skipTutorial", false) == true

        setContent {
            WithLocale(localeTag) {
                ChannelTimelineTheme {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        if (previewName == "badge") {
                            BadgePreviewScreen()
                        } else {
                            AppRoot(container, sharedUrl, skipTutorial)
                        }
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 別端末で買った・返金された・保留が確定した、のどれでも追随できるようにする。
        container.billing.refresh()
    }

    override fun onDestroy() {
        super.onDestroy()
        container.billing.dispose()
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

/**
 * 表示言語を差し替えて中身を描く（デバッグ専用）。
 * 端末の言語設定を変えずに、7言語ぶんのスクリーンショットを撮るために使う。
 */
@Composable
private fun WithLocale(languageTag: String?, content: @Composable () -> Unit) {
    if (languageTag.isNullOrBlank()) {
        content()
        return
    }
    val context = LocalContext.current
    val configuration = Configuration(LocalConfiguration.current).apply {
        setLocale(Locale.forLanguageTag(languageTag))
    }
    CompositionLocalProvider(
        LocalConfiguration provides configuration,
        LocalContext provides context.createConfigurationContext(configuration),
    ) {
        content()
    }
}

/** いま表示している画面。 */
private sealed interface Screen {
    data object Input : Screen
    data object About : Screen
    data object Pro : Screen
    data class Videos(val channel: Channel) : Screen
    data class Play(val channel: Channel, val videos: List<VideoItem>, val index: Int) : Screen

    // Watch Queue（V2）。サーバーの Feature Flag が ON のときだけ入口が出る。
    data object WatchQueue : Screen
    data class WatchQueuePlay(
        val queue: com.deskflowlabs.channeltimelineviewer.network.WatchQueue,
    ) : Screen
}

@Composable
private fun AppRoot(
    container: AppContainer,
    sharedUrl: MutableStateFlow<String?>,
    skipTutorial: Boolean = false,
) {
    var screen by remember { mutableStateOf<Screen>(Screen.Input) }
    var showOptions by remember { mutableStateOf(false) }

    val inputViewModel: ChannelInputViewModel = viewModel(
        factory = simpleFactory {
            ChannelInputViewModel(
                api = container.api,
                favorites = container.favorites,
                isPro = container.proEntitlement.isPro,
                dataRemover = container.channelDataRemover,
                activeChannel = container.activeChannel,
                analytics = container.analytics,
            )
        }
    )
    val isPro by container.proEntitlement.isPro.collectAsStateWithLifecycle()
    val resolved by inputViewModel.resolvedChannel.collectAsStateWithLifecycle()
    val shared by sharedUrl.collectAsStateWithLifecycle()

    // 共有された URL が届いたらチャンネルを特定して開く。
    LaunchedEffect(shared) {
        val url = shared ?: return@LaunchedEffect
        sharedUrl.value = null
        screen = Screen.Input
        inputViewModel.openSharedLink(url)
    }

    // Pro を買った直後は、上限で止めていたチャンネルをそのまま開く。
    LaunchedEffect(isPro) {
        if (isPro) inputViewModel.retryPendingUpgradeIfUnlocked()
    }

    LaunchedEffect(resolved) {
        val channel = resolved ?: return@LaunchedEffect
        inputViewModel.consumeResolvedChannel()
        screen = Screen.Videos(channel)
    }

    // 画面表示を記録する（名前だけ。開いているチャンネルや動画は送らない）。
    LaunchedEffect(screen) {
        container.analytics.logScreen(
            when (screen) {
                is Screen.Input -> Analytics.Screen.INPUT
                is Screen.About -> Analytics.Screen.ABOUT
                is Screen.Pro -> Analytics.Screen.PRO
                is Screen.Videos -> Analytics.Screen.VIDEO_LIST
                is Screen.Play -> Analytics.Screen.PLAYER
                is Screen.WatchQueue -> Analytics.Screen.WATCH_QUEUE
                is Screen.WatchQueuePlay -> Analytics.Screen.WATCH_QUEUE_PLAYER
            }
        )
    }

    // Watch Queue（V2）の Feature Flag。取れないときは「出さない」ままにする。
    val watchQueueEnabled by container.watchQueue.remoteEnabled.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { container.watchQueue.refreshAvailability() }

    // ---- 「チャンネルの追加方法」の案内 ----
    // 出すのは**初めて追加しようとしたとき**だけ。起動のたびには出さない。
    // 判定: まだ見ていない かつ 保存チャンネルが1件も無い（＝まだ1つも追加できていない人）。
    val tutorialDone by container.channelTutorial.isCompleted.collectAsStateWithLifecycle()
    val savedChannels by container.favorites.favorites.collectAsStateWithLifecycle()
    var tutorialShown by rememberSaveable { mutableStateOf(false) }
    var tutorialSource by remember { mutableStateOf(Analytics.Source.FIRST_TIME) }

    LaunchedEffect(tutorialDone, savedChannels.isEmpty(), screen) {
        if (screen !is Screen.Input) return@LaunchedEffect
        if (skipTutorial) return@LaunchedEffect
        if (tutorialDone || savedChannels.isNotEmpty() || tutorialShown) return@LaunchedEffect
        tutorialSource = Analytics.Source.FIRST_TIME
        tutorialShown = true
        container.analytics.log(
            Analytics.Event.CHANNEL_TUTORIAL_VIEW,
            Analytics.Param.SOURCE to Analytics.Source.FIRST_TIME,
        )
    }

    if (tutorialShown) {
        ChannelTutorialSheet(
            onDismiss = { tutorialShown = false },
            onComplete = {
                tutorialShown = false
                // 自分で開き直したときは印を変えない（説明が要る人かどうかが分からなくなる）。
                if (tutorialSource == Analytics.Source.FIRST_TIME) {
                    container.channelTutorial.markCompleted()
                }
                container.analytics.log(Analytics.Event.CHANNEL_TUTORIAL_COMPLETE)
            },
            onSkip = { stepNumber ->
                tutorialShown = false
                // スキップも見終わったのと同じ扱い。同じ案内を二度出さない。
                if (tutorialSource == Analytics.Source.FIRST_TIME) {
                    container.channelTutorial.markCompleted()
                }
                container.analytics.log(
                    Analytics.Event.CHANNEL_TUTORIAL_SKIP,
                    Analytics.Param.VALUE to stepNumber,
                )
            },
        )
    }

    when (val current = screen) {
        is Screen.Input -> ChannelInputScreen(
            viewModel = inputViewModel,
            favorites = container.favorites,
            progressStore = container.progress,
            isApiConfigured = container.isApiConfigured,
            isPro = isPro,
            onOpenAbout = { screen = Screen.About },
            onOpenPro = { screen = Screen.Pro },
            onOpenFavorite = { favorite -> inputViewModel.open(favorite) },
            showWatchQueue = watchQueueEnabled,
            onOpenWatchQueue = { screen = Screen.WatchQueue },
        )

        is Screen.WatchQueue -> com.deskflowlabs.channeltimelineviewer.ui.WatchQueueScreen(
            store = container.watchQueue,
            isPro = isPro,
            savedChannelCount = savedChannels.size,
            onBack = { screen = Screen.Input },
            onOpenQueue = { queue -> screen = Screen.WatchQueuePlay(queue) },
        )

        is Screen.WatchQueuePlay -> {
            val queueViewModel: com.deskflowlabs.channeltimelineviewer.viewmodel.WatchQueuePlayerViewModel = viewModel(
                factory = simpleFactory {
                    com.deskflowlabs.channeltimelineviewer.viewmodel.WatchQueuePlayerViewModel(
                        queue = current.queue,
                        settings = container.settings,
                    )
                },
                key = "watch-queue-${current.queue.queueId}",
            )
            com.deskflowlabs.channeltimelineviewer.ui.WatchQueuePlayerScreen(
                viewModel = queueViewModel,
                settings = container.settings,
                onBack = { screen = Screen.WatchQueue },
            )
        }

        is Screen.About -> AboutScreen(
            analyticsEnabled = container.analyticsSettings.isEnabled,
            onAnalyticsEnabledChange = container::setAnalyticsEnabled,
            onShowTutorial = {
                tutorialSource = Analytics.Source.MANUAL
                tutorialShown = true
                container.analytics.log(
                    Analytics.Event.CHANNEL_TUTORIAL_VIEW,
                    Analytics.Param.SOURCE to Analytics.Source.MANUAL,
                )
            },
            onBack = { screen = Screen.Input },
        )

        is Screen.Pro -> ProScreen(
            billing = container.billing,
            entitlement = container.proEntitlement,
            onBack = { screen = Screen.Input },
        )

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
                        analytics = container.analytics,
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
