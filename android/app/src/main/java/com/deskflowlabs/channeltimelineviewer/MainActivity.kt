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
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.res.stringResource
import com.deskflowlabs.channeltimelineviewer.ui.CopyLinkGuide
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import androidx.lifecycle.viewmodel.compose.viewModel
import com.deskflowlabs.channeltimelineviewer.ads.AnchorAdaptiveBanner
import com.deskflowlabs.channeltimelineviewer.ads.MrecAdSlot
import com.deskflowlabs.channeltimelineviewer.ads.rememberMrecAd
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
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * 画面はこの1つの Activity 内で切り替える（3画面なので Navigation ライブラリは使わない）。
 */
class MainActivity : ComponentActivity() {

    private lateinit var container: AppContainer

    /** 共有（ACTION_SEND）で受け取った YouTube URL。 */
    private val sharedUrl = MutableStateFlow<String?>(null)

    /** コピーされていた YouTube の URL（「開きますか？」と聞く）。 */
    private val copiedUrl = MutableStateFlow<String?>(null)

    /** 一度聞いた（開いた・断った）コピーは、二度は聞かない。 */
    private val handledClipPrefs by lazy { getSharedPreferences("copy_link_guide", MODE_PRIVATE) }

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
        //   --ez adsEea true      … 広告の同意フォームを EEA の扱いで試す（エミュレーターのみ有効）
        //   --ez adsResetConsent true … 広告の同意をやり直す
        val adsEea = BuildConfig.DEBUG && intent?.getBooleanExtra("adsEea", false) == true
        val adsResetConsent = BuildConfig.DEBUG && intent?.getBooleanExtra("adsResetConsent", false) == true
        //   --ez noAds true       … 広告を出さない（ストア用スクリーンショットにテスト広告を写さないため）
        val noAds = BuildConfig.DEBUG && intent?.getBooleanExtra("noAds", false) == true
        //   --ez postCopyGuideNotification true … 「アプリに戻る」の通知だけを出して終わる（案内の画像を撮るため）
        if (BuildConfig.DEBUG && intent?.getBooleanExtra("postCopyGuideNotification", false) == true) {
            CopyLinkGuide.postNotification(this)
            finish()
            return
        }

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                container.proEntitlement.isPro.collect { isPro ->
                    // 無料／Pro の区分だけを属性として残す（広告収益・継続率を区分ごとに見るため）。
                    container.analytics.setUserProperty(
                        Analytics.UserProperty.PRO_STATUS,
                        Analytics.ProStatus.of(isPro),
                    )
                    // 広告の準備（同意 → 初期化）。Pro のあいだは何もしない。
                    if (!isPro && !noAds) container.ads.prepare(this@MainActivity, adsEea, adsResetConsent)
                }
            }
        }

        setContent {
            WithLocale(localeTag) {
                ChannelTimelineTheme {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        if (previewName == "badge") {
                            BadgePreviewScreen()
                        } else {
                            AppRoot(
                                container,
                                sharedUrl,
                                skipTutorial,
                                copiedUrl = copiedUrl,
                                onResumedCheckClipboard = ::checkCopiedLink,
                                onCopiedUrlAnswered = { url, open ->
                                    copiedUrl.value = null
                                    markClipHandled(url)
                                    if (open) sharedUrl.value = url else CopyLinkGuide.clearClipboard(this)
                                },
                                openAdsPrivacyOptions = { container.ads.showPrivacyOptions(this) },
                            )
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
     * 前面に来て入力を受け付けられるようになったら、コピーされた YouTube のリンクを見る。
     * Android 10 以降は、前面でフォーカスを持っているときしかクリップボードを読めない。
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) checkCopiedLink()
    }

    /**
     * コピーされた YouTube のリンクを見る。案内のシート（別ウィンドウ）が出ているあいだは
     * Activity 側の onWindowFocusChanged が呼ばれないので、画面側からも前面に戻ったときに呼ぶ。
     */
    private fun checkCopiedLink() {
        // 案内から YouTube へ行っていた人が戻ってきた（戻るボタン・最近使ったアプリのどちらでも）:
        // 新しくコピーしたリンクがあれば、聞かずにそのまま開く。
        CopyLinkGuide.takeNewlyCopiedUrl(this)?.let { url ->
            markClipHandled(url)
            sharedUrl.value = url
            return
        }
        // それ以外で、まだ聞いていない YouTube のリンクがコピーされていれば「開きますか？」と聞く。
        val url = CopyLinkGuide.copiedYouTubeUrl(this) ?: return
        if (url != handledClipPrefs.getString(KEY_LAST_CLIP, null)) copiedUrl.value = url
    }

    private fun markClipHandled(url: String) {
        handledClipPrefs.edit().putString(KEY_LAST_CLIP, url).apply()
    }

    private companion object {
        const val KEY_LAST_CLIP = "last_handled_clip"
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
    /**
     * @param keepSearch 再生画面から戻ったときだけ true。それ以外（チャンネルを開いた・共有から開いた）は
     *   チャンネル内検索を消して全件で出す（別チャンネルの検索を持ち越さない・docs/channel-search.md）。
     */
    data class Videos(val channel: Channel, val keepSearch: Boolean = false) : Screen
    data class Play(val channel: Channel, val videos: List<VideoItem>, val index: Int) : Screen
}

@Composable
private fun AppRoot(
    container: AppContainer,
    sharedUrl: MutableStateFlow<String?>,
    skipTutorial: Boolean = false,
    // Activity が要る（同意フォームは Activity の上に出す）ので、MainActivity から渡す。
    // LocalContext はデバッグの言語切り替えで Activity 以外に差し替わることがあるため使わない。
    openAdsPrivacyOptions: () -> Unit = {},
    copiedUrl: MutableStateFlow<String?> = MutableStateFlow(null),
    onCopiedUrlAnswered: (url: String, open: Boolean) -> Unit = { _, _ -> },
    onResumedCheckClipboard: () -> Unit = {},
) {
    var screen by remember { mutableStateOf<Screen>(Screen.Input) }

    // 前面に戻ったら、少し待ってからコピーされたリンクを見る（フォーカスが戻る前は読めないので数回試す）。
    val resumeState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    LaunchedEffect(resumeState.isAtLeast(Lifecycle.State.RESUMED)) {
        if (!resumeState.isAtLeast(Lifecycle.State.RESUMED)) return@LaunchedEffect
        repeat(3) {
            kotlinx.coroutines.delay(400)
            onResumedCheckClipboard()
        }
    }

    // コピーされていた YouTube のリンク（通知を使わずに自分で戻ってきた人向け）。開くかどうかを聞く。
    val copied by copiedUrl.collectAsStateWithLifecycle()
    copied?.let { url ->
        AlertDialog(
            onDismissRequest = { onCopiedUrlAnswered(url, false) },
            title = { Text(stringResource(R.string.clip_dialog_title)) },
            text = { Text(stringResource(R.string.clip_dialog_body)) },
            confirmButton = {
                TextButton(onClick = { onCopiedUrlAnswered(url, true) }) {
                    Text(stringResource(R.string.clip_dialog_open))
                }
            },
            // 開かないときは、コピーそのものを消す（同じリンクで何度も聞かれないように・2026-10-05 ユーザー指定）。
            dismissButton = {
                TextButton(onClick = { onCopiedUrlAnswered(url, false) }) {
                    Text(stringResource(R.string.clip_dialog_clear))
                }
            },
        )
    }
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
            }
        )
    }

    // ---- 「チャンネルの追加方法」の案内 ----
    // 出すのは**初めて追加しようとしたとき**だけ。起動のたびには出さない。
    // 判定: まだ見ていない かつ 保存チャンネルが1件も無い（＝まだ1つも追加できていない人）。
    val tutorialDone by container.channelTutorial.isCompleted.collectAsStateWithLifecycle()
    val savedChannels by container.favorites.favorites.collectAsStateWithLifecycle()
    var tutorialShown by rememberSaveable { mutableStateOf(false) }
    var tutorialSource by remember { mutableStateOf(Analytics.Source.FIRST_TIME) }
    // 最初の画面の［YouTube の共有から追加する］から開いたときは、案内をその画面から始める。
    var tutorialStartWithCopyGuide by remember { mutableStateOf(false) }

    // 初めての人（まだ1チャンネルも無い人）には、入力画面に戻るたびに出す。YouTube へ行って
    // 共有せずに戻ってきた人も、何もできない画面に取り残さないため（2026-10-05・ユーザー判断）。
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val isResumed = lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
    LaunchedEffect(screen) {
        // 一覧・再生画面の上には重ねない。
        // 自分で開いた案内（［YouTube の共有から追加する］など）も含めて、一覧・再生画面の上には残さない。
        // 残すと、コピーして戻ってチャンネルを開いたあとに案内が前に出てしまう（2026-10-05 に実際に起きた）。
        if (screen !is Screen.Input) tutorialShown = false
    }
    LaunchedEffect(tutorialDone, savedChannels.isEmpty(), screen, isResumed) {
        if (screen !is Screen.Input || !isResumed) return@LaunchedEffect
        if (skipTutorial) return@LaunchedEffect
        if (savedChannels.isNotEmpty() || tutorialShown) return@LaunchedEffect
        tutorialSource = Analytics.Source.FIRST_TIME
        tutorialStartWithCopyGuide = false
        tutorialShown = true
        container.analytics.log(
            Analytics.Event.CHANNEL_TUTORIAL_VIEW,
            Analytics.Param.SOURCE to Analytics.Source.FIRST_TIME,
        )
    }

    // 案内（初めての人には閉じにくくしてある）が出ているときの戻るボタンは、アプリを終了せず
    // 案内だけを閉じて最初の画面に戻す（2026-10-05・ユーザー指摘）。
    androidx.activity.compose.BackHandler(enabled = tutorialShown) { tutorialShown = false }

    // 端末の戻るボタンでも、画面左上の矢印と同じ画面へ戻る（以前は最初の画面以外でもアプリが終了していた）。
    // 再生画面は一覧へ、一覧・Pro・このアプリについては最初の画面へ。最初の画面ではこれまでどおり終了する。
    // 画面ごとの BackHandler（検索を閉じる・全画面を抜ける）はこれより後に登録されるので、そちらが先に効く。
    androidx.activity.compose.BackHandler(enabled = !tutorialShown && screen !is Screen.Input) {
        screen = when (val current = screen) {
            is Screen.Play -> Screen.Videos(current.channel, keepSearch = true)
            else -> Screen.Input
        }
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
            // 端末の国の人気動画（国が分からなければ YouTube の既定）。
            loadPopular = { container.api.fetchPopularVideos(java.util.Locale.getDefault().country) },
            dismissible = tutorialSource != Analytics.Source.FIRST_TIME,
            startWithCopyGuide = tutorialStartWithCopyGuide,
            onPickVideo = { video ->
                tutorialShown = false
                if (tutorialSource == Analytics.Source.FIRST_TIME) {
                    container.channelTutorial.markCompleted()
                }
                inputViewModel.openPopular(video.channelId)
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
            onOpenCopyGuide = {
                tutorialSource = Analytics.Source.MANUAL
                tutorialStartWithCopyGuide = true
                tutorialShown = true
            },
            onOpenPopular = {
                tutorialSource = Analytics.Source.MANUAL
                tutorialStartWithCopyGuide = false
                tutorialShown = true
            },
            // MREC は保存チャンネルの一覧の下にだけ置く（docs/admob-ads.md）。
            // 1件も保存していない人（初回）には読み込みもしない。
            mrecSlot = (if (savedChannels.isNotEmpty()) rememberMrecAd(container.ads) else null)
                ?.let { adView -> @Composable { MrecAdSlot(adView) } },
        )

        is Screen.About -> AboutScreen(
            analyticsEnabled = container.analyticsSettings.isEnabled,
            onAnalyticsEnabledChange = container::setAnalyticsEnabled,
            adsPrivacyOptionsRequired = container.ads.privacyOptionsRequired,
            onOpenAdsPrivacyOptions = openAdsPrivacyOptions,
            onShowTutorial = {
                tutorialSource = Analytics.Source.MANUAL
                tutorialStartWithCopyGuide = false
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
            keepSearch = current.keepSearch,
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
                onBack = { screen = Screen.Videos(current.channel, keepSearch = true) },
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
    keepSearch: Boolean,
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
    // ViewModel はチャンネルごとに Activity の間残るので、再生画面から戻ったとき以外は検索を消す。
    LaunchedEffect(channel.id, keepSearch) { if (!keepSearch) listViewModel.closeSearch() }

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
        // 動画一覧の下に固定するバナー。再生画面には置かない（プレイヤーや操作に重ねない）。
        bottomBar = { AnchorAdaptiveBanner(container.ads) },
    )
}

/** ViewModel を引数付きで作るための最小のファクトリ。 */
private inline fun <reified T : ViewModel> simpleFactory(crossinline create: () -> T) =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = create() as VM
    }
