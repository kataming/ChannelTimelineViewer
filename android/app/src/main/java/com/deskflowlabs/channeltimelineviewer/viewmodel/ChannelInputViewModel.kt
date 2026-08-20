package com.deskflowlabs.channeltimelineviewer.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.deskflowlabs.channeltimelineviewer.billing.ChannelSlotPolicy
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
 *
 * 保存できるチャンネル数だけは [ChannelSlotPolicy] で制限する（無料は1件、Pro は無制限）。
 * 制限に当たったときは開かずに [pendingUpgrade] を立て、画面が案内を出す。
 */
class ChannelInputViewModel(
    private val api: YouTubeApiClient,
    private val favorites: FavoriteChannelStore,
    private val isPro: StateFlow<Boolean>,
) : ViewModel() {

    /** 保存上限に当たったチャンネルと、いま保存しているチャンネル名。 */
    data class PendingUpgrade(val channel: Channel, val savedChannelTitle: String)

    private val _urlText = MutableStateFlow("")
    val urlText: StateFlow<String> = _urlText.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorRes = MutableStateFlow<Int?>(null)
    val errorRes: StateFlow<Int?> = _errorRes.asStateFlow()

    /** 取得できたチャンネル。画面はこれを見て一覧へ遷移する。 */
    private val _resolvedChannel = MutableStateFlow<Channel?>(null)
    val resolvedChannel: StateFlow<Channel?> = _resolvedChannel.asStateFlow()

    private val _pendingUpgrade = MutableStateFlow<PendingUpgrade?>(null)
    val pendingUpgrade: StateFlow<PendingUpgrade?> = _pendingUpgrade.asStateFlow()

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
        openResolved(channel)
    }

    fun dismissPendingUpgrade() {
        _pendingUpgrade.value = null
    }

    /**
     * 保存中のチャンネルを外して、新しいチャンネルに入れ替える。
     * 視聴済み・進捗・メモ・再生位置は消さないので、戻せば続きから見られる。
     */
    fun replaceSavedChannel() {
        val pending = _pendingUpgrade.value?.channel ?: return
        val savedNewestFirst = favorites.favorites.value.map { it.id }
        ChannelSlotPolicy.idsToRemoveForReplacement(savedNewestFirst).forEach(favorites::remove)
        _pendingUpgrade.value = null
        openResolved(pending)
    }

    /** Pro を買ったあとに、保留していたチャンネルをそのまま開く。 */
    fun retryPendingUpgradeIfUnlocked() {
        val pending = _pendingUpgrade.value?.channel ?: return
        if (!isPro.value) return
        _pendingUpgrade.value = null
        openResolved(pending)
    }

    private fun openResolved(channel: Channel) {
        favorites.touch(channel)
        _resolvedChannel.value = channel
    }

    /** 保存上限に当たっていないか見て、開くか案内を出すか決める。 */
    private fun openOrAskForPro(channel: Channel) {
        val saved = favorites.favorites.value
        if (ChannelSlotPolicy.canOpen(saved.map { it.id }, channel.id, isPro.value)) {
            openResolved(channel)
            return
        }
        _pendingUpgrade.value = PendingUpgrade(
            channel = channel,
            savedChannelTitle = saved.firstOrNull()?.title.orEmpty(),
        )
    }

    private fun resolve(input: String) {
        if (_isLoading.value) return
        _errorRes.value = null
        _isLoading.value = true
        viewModelScope.launch {
            try {
                openOrAskForPro(api.resolveChannel(input))
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
