package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import com.deskflowlabs.channeltimelineviewer.data.ChannelProgressStore
import com.deskflowlabs.channeltimelineviewer.data.FavoriteChannelStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackPositionStore
import com.deskflowlabs.channeltimelineviewer.data.PlaybackSettingsStore
import com.deskflowlabs.channeltimelineviewer.data.SkippedVideoStore
import com.deskflowlabs.channeltimelineviewer.data.VideoListCache
import com.deskflowlabs.channeltimelineviewer.data.VideoMemoStore
import com.deskflowlabs.channeltimelineviewer.data.WatchHistoryStore
import com.deskflowlabs.channeltimelineviewer.data.storePrefs
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient

/**
 * アプリ全体で共有するストアと API クライアント。
 *
 * DI ライブラリを入れるほどの規模ではないので、ここで一度だけ作って持ち回る
 * （iOS 版で `@EnvironmentObject` に入れているものと同じ顔ぶれ）。
 */
class AppContainer(context: Context) {
    private val prefs = context.applicationContext.storePrefs()

    val api = YouTubeApiClient()
    val watchStore = WatchHistoryStore(prefs)
    val skipStore = SkippedVideoStore(prefs)
    val memoStore = VideoMemoStore(prefs)
    val positionStore = PlaybackPositionStore(prefs)
    val settings = PlaybackSettingsStore(prefs)
    val favorites = FavoriteChannelStore(prefs)
    val progress = ChannelProgressStore(prefs)
    val videoListCache = VideoListCache(prefs)

    /** APIキーが設定されているか（未設定なら入力画面で警告を出す）。 */
    val isApiConfigured: Boolean get() = BuildConfig.YOUTUBE_API_KEY.isNotBlank()
}
