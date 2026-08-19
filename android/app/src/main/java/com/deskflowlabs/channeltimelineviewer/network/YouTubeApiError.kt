package com.deskflowlabs.channeltimelineviewer.network

import androidx.annotation.StringRes
import com.deskflowlabs.channeltimelineviewer.R

/**
 * YouTube API 関連のエラー。表示文言は iOS 版と同じ翻訳（`Localization/strings.json`）を使う。
 */
enum class YouTubeApiError(@StringRes val messageRes: Int) {
    InvalidUrl(R.string.error_invalidurl),
    InvalidChannelUrl(R.string.error_invalidchannelurl),
    InvalidVideoUrl(R.string.error_invalidvideourl),
    VideoNotFound(R.string.error_videonotfound),
    ChannelNotFound(R.string.error_channelnotfound),
    UploadsPlaylistNotFound(R.string.error_uploadsplaylistnotfound),
    ApiKeyMissing(R.string.error_apikeymissing),
    QuotaExceeded(R.string.error_quotaexceeded),
    NetworkError(R.string.error_network),
    DecodingError(R.string.error_decoding),
    Unknown(R.string.error_unknown),
}

/** 画面に出すエラーを運ぶ例外。メッセージは表示側で文字列リソースから引く。 */
class YouTubeApiException(val error: YouTubeApiError) : Exception(error.name)
