package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deskflowlabs.channeltimelineviewer.data.FavoriteChannelStore
import com.deskflowlabs.channeltimelineviewer.model.Channel
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiError
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * チャンネル入力画面の状態。iOS 版 `ViewModels/ChannelInputViewModel.swift` の移植。
 *
 * URL の解析はローカル、チャンネルの特定は公式 API。取得できたらお気に入り（最近使った）に記録する。
 */
class ChannelInputViewModel(
    private val api: YouTubeApiClient,
    private val favorites: FavoriteChannelStore,
) : ViewModel() {

    private val _urlText = MutableStateFlow("")
    val urlText: StateFlow<String> = _urlText.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorRes = MutableStateFlow<Int?>(null)
    val errorRes: StateFlow<Int?> = _errorRes.asStateFlow()

    /** 取得できたチャンネル。画面はこれを見て一覧へ遷移する。 */
    private val _resolvedChannel = MutableStateFlow<Channel?>(null)
    val resolvedChannel: StateFlow<Channel?> = _resolvedChannel.asStateFlow()

    fun setUrlText(value: String) {
        _urlText.value = value
        _errorRes.value = null
    }

    fun clearError() {
        _errorRes.value = null
    }

    /** 遷移が終わったら呼ぶ（同じチャンネルへ二重遷移しないように）。 */
    fun consumeResolvedChannel() {
        _resolvedChannel.value = null
    }

    /** 入力欄の URL からチャンネルを特定する。 */
    fun fetch() {
        val input = _urlText.value.trim()
        if (input.isEmpty()) {
            _errorRes.value = YouTubeApiError.InvalidChannelUrl.messageRes
            return
        }
        resolve(input)
    }

    /** 共有で受け取った URL からチャンネルを開く（動画URLなら投稿チャンネルを特定する）。 */
    fun openSharedLink(url: String) {
        _urlText.value = url
        resolve(url)
    }

    /** お気に入り（最近使った）から開く。 */
    fun open(channel: Channel) {
        favorites.touch(channel)
        _resolvedChannel.value = channel
    }

    private fun resolve(input: String) {
        if (_isLoading.value) return
        _errorRes.value = null
        _isLoading.value = true
        viewModelScope.launch {
            try {
                val channel = api.resolveChannel(input)
                favorites.touch(channel)
                _resolvedChannel.value = channel
            } catch (e: YouTubeApiException) {
                _errorRes.value = e.error.messageRes
            } catch (e: Exception) {
                _errorRes.value = YouTubeApiError.Unknown.messageRes
            } finally {
                _isLoading.value = false
            }
        }
    }
}
