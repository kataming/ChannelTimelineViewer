package com.deskflowlabs.channeltimelineviewer.network

import android.net.Uri

/**
 * 入力URLから解決したチャンネル識別子。
 *
 * iOS 版 `Services/ChannelResolver.swift` の移植。挙動を変えないこと
 * （どちらのアプリでも同じURLが同じように開ける必要がある）。
 */
sealed interface ChannelIdentifier {
    /** UCxxxx 形式のチャンネルID。 */
    data class ChannelId(val value: String) : ChannelIdentifier

    /** @ を除いたハンドル。 */
    data class Handle(val value: String) : ChannelIdentifier

    /** 旧 /user/ 形式。 */
    data class Username(val value: String) : ChannelIdentifier

    /** /c/name または /name のカスタムURL。 */
    data class CustomName(val value: String) : ChannelIdentifier

    /** 動画URL（videoId）。チャンネルIDは API で解決する。 */
    data class Video(val videoId: String) : ChannelIdentifier
}

/**
 * YouTube チャンネルURL（または handle / channelId）を解析する。
 * ネットワークアクセスをしない純粋関数なのでテストしやすい。
 */
object ChannelResolver {

    @Throws(YouTubeApiException::class)
    fun parse(rawInput: String): ChannelIdentifier {
        val input = rawInput.trim()
        if (input.isEmpty()) throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)

        // 1) 先頭が @ のハンドル単体
        if (input.startsWith("@")) return makeHandle(input.drop(1))

        // 2) channelId 単体（UC + 22文字）
        if (isChannelId(input)) return ChannelIdentifier.ChannelId(input)

        // 3) URLとして解析（スキーム省略も許容）
        val normalized = if (input.contains("://")) input else "https://$input"
        val uri = runCatching { Uri.parse(normalized) }.getOrNull()
        val host = uri?.host?.lowercase()
        if (host == null || !(host.contains("youtube.com") || host.contains("youtu.be"))) {
            throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)
        }

        val segments = (uri.path ?: "").split("/").filter { it.isNotEmpty() }

        // 短縮URL（youtu.be/VIDEOID）は常に動画。
        if (host == "youtu.be" || host.endsWith(".youtu.be")) {
            val id = segments.firstOrNull()
            if (id == null || !isVideoId(id)) throw YouTubeApiException(YouTubeApiError.InvalidVideoUrl)
            return ChannelIdentifier.Video(id)
        }

        val first = segments.firstOrNull() ?: throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)

        return when (first.lowercase()) {
            "watch" -> {
                val v = runCatching { uri.getQueryParameter("v") }.getOrNull()
                if (v == null || !isVideoId(v)) throw YouTubeApiException(YouTubeApiError.InvalidVideoUrl)
                ChannelIdentifier.Video(v)
            }

            "shorts", "live", "embed", "v" -> {
                val id = segments.getOrNull(1)
                if (id == null || !isVideoId(id)) throw YouTubeApiException(YouTubeApiError.InvalidVideoUrl)
                ChannelIdentifier.Video(id)
            }

            "channel" -> {
                val id = segments.getOrNull(1)
                if (id == null || !isChannelId(id)) throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)
                ChannelIdentifier.ChannelId(id)
            }

            "user" -> {
                val name = segments.getOrNull(1) ?: throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)
                ChannelIdentifier.Username(name)
            }

            "c" -> {
                val name = segments.getOrNull(1) ?: throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)
                ChannelIdentifier.CustomName(name)
            }

            else ->
                if (first.startsWith("@")) makeHandle(first.drop(1))
                // youtube.com/SomeName のような旧カスタムURL
                else ChannelIdentifier.CustomName(first)
        }
    }

    /** UC で始まる24文字の channelId かどうか。 */
    fun isChannelId(value: String): Boolean =
        value.startsWith("UC") &&
            value.length == 24 &&
            value.all { it.isLetterOrDigit() || it == '_' || it == '-' }

    /** YouTube の videoId（11文字の英数字 + `_` `-`）かどうか。 */
    fun isVideoId(value: String): Boolean =
        value.length == 11 &&
            value.all { it.code < 128 && (it.isLetterOrDigit() || it == '_' || it == '-') }

    /**
     * 動画URL（または videoId 単体）から videoId を取り出す。動画URLでなければ null。
     */
    fun extractVideoId(rawInput: String): String? {
        val input = rawInput.trim()
        if (isVideoId(input) && !input.contains("/") && !input.contains(".")) return input
        val identifier = runCatching { parse(input) }.getOrNull()
        return (identifier as? ChannelIdentifier.Video)?.videoId
    }

    private fun makeHandle(handle: String): ChannelIdentifier {
        val clean = handle.trim()
        if (clean.isEmpty()) throw YouTubeApiException(YouTubeApiError.InvalidChannelUrl)
        return ChannelIdentifier.Handle(clean)
    }
}
