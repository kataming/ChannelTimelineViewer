package com.deskflowlabs.channeltimelineviewer.network

import android.net.Uri

/**
 * 共有（ACTION_SEND）で受け取ったテキスト / URL から YouTube の URL を取り出す。
 *
 * iOS 版 `Services/SharedLinkParser.swift` の移植。
 * Android は共有からアプリを直接開けるので、iOS のようなカスタムURLスキームでの受け渡しは不要。
 * 「YouTube の URL かどうかの判定」と「テキストからの抽出」だけを担う。
 */
object SharedLinkParser {

    /** YouTube と認識するホスト（完全一致、またはサブドメイン）。 */
    private val youTubeHosts = listOf(
        "youtube.com",
        "youtu.be",
        "youtube-nocookie.com",
    )

    /** 前後についてくる引用符・括弧・句読点。 */
    private const val EDGE_PUNCTUATION = "<>\"'`(){}[]｢｣「」『』（）、。,;:！？!?…・​"

    /** 文字列が YouTube の URL として解釈できるか。スキーム省略（`youtube.com/@x`）も許容する。 */
    fun isYouTubeUrl(string: String): Boolean = hostOf(string) != null

    /**
     * 共有テキスト（URL 単体・タイトル＋URL の複数行テキストなど）から最初の YouTube URL を取り出す。
     *
     * YouTube アプリは「動画タイトル\nhttps://youtu.be/xxxx?si=yyyy」のような
     * プレーンテキストを渡してくることがあるため、テキストからの抽出に対応する。
     */
    fun extractYouTubeUrl(text: String): String? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        // 1) 全体がひとつの URL の場合
        normalizedYouTubeUrl(trimmed)?.let { return it }

        // 2) 空白・改行区切りのトークンから探す
        for (token in trimmed.split(Regex("\\s+"))) {
            for (candidate in urlCandidates(token)) {
                normalizedYouTubeUrl(candidate)?.let { return it }
            }
        }
        return null
    }

    /**
     * スキームを補い、余分な記号を落とした YouTube URL 文字列。YouTube でなければ null。
     */
    fun normalizedYouTubeUrl(string: String): String? {
        val token = string.trim().trim { it in EDGE_PUNCTUATION }
        if (token.isEmpty() || token.any { it.isWhitespace() } || hostOf(token) == null) return null
        return if (token.contains("://")) token else "https://$token"
    }

    /**
     * 1トークンから URL になりうる部分文字列を候補として並べる。
     * 「これ見て→https://youtu.be/xxx」のように記号が前置きされていても拾えるようにする。
     */
    private fun urlCandidates(token: String): List<String> {
        if (token.isEmpty()) return emptyList()
        val candidates = mutableListOf(token)
        for (marker in listOf("https://", "http://") + youTubeHosts) {
            val index = token.indexOf(marker, ignoreCase = true)
            if (index > 0) candidates.add(token.substring(index))
        }
        return candidates
    }

    /** URL 文字列のホストを返す（YouTube でなければ null）。 */
    private fun hostOf(string: String): String? {
        val candidate = if (string.contains("://")) string else "https://$string"
        val uri = runCatching { Uri.parse(candidate) }.getOrNull() ?: return null
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return null
        val host = uri.host?.lowercase() ?: return null
        val matched = youTubeHosts.any { host == it || host.endsWith(".$it") }
        return if (matched) host else null
    }
}
