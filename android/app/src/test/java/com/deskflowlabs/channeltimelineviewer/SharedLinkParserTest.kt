package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.network.SharedLinkParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * iOS 版 `Tests/SharedLinkParserTests.swift` と同じケース。
 * 共有されたテキストからの URL 抽出は、YouTube アプリの共有内容に合わせた処理なので
 * プラットフォーム間で挙動を揃えておく。
 */
@RunWith(RobolectricTestRunner::class)
class SharedLinkParserTest {

    @Test
    fun acceptsChannelUrls() {
        assertTrue(SharedLinkParser.isYouTubeUrl("https://www.youtube.com/@example"))
        assertTrue(SharedLinkParser.isYouTubeUrl("https://m.youtube.com/channel/UC1234567890123456789012"))
        assertTrue(SharedLinkParser.isYouTubeUrl("youtube.com/@example"))
    }

    @Test
    fun acceptsVideoUrls() {
        assertTrue(SharedLinkParser.isYouTubeUrl("https://youtu.be/dQw4w9WgXcQ"))
        assertTrue(SharedLinkParser.isYouTubeUrl("https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
    }

    @Test
    fun rejectsNonYouTubeUrls() {
        assertFalse(SharedLinkParser.isYouTubeUrl("https://example.com/watch?v=dQw4w9WgXcQ"))
        assertFalse(SharedLinkParser.isYouTubeUrl("notyoutube.com/@example"))
        assertFalse(SharedLinkParser.isYouTubeUrl(""))
    }

    @Test
    fun extractsUrlFromSharedTextWithTitle() {
        val text = "すごい動画\nhttps://youtu.be/dQw4w9WgXcQ?si=abc123"
        assertEquals("https://youtu.be/dQw4w9WgXcQ?si=abc123", SharedLinkParser.extractYouTubeUrl(text))
    }

    @Test
    fun extractsUrlFromTextWithTrailingPunctuation() {
        val text = "これ見て→「https://youtu.be/dQw4w9WgXcQ」"
        assertEquals("https://youtu.be/dQw4w9WgXcQ", SharedLinkParser.extractYouTubeUrl(text))
    }

    @Test
    fun extractsChannelUrlFromText() {
        val text = "おすすめのチャンネル https://www.youtube.com/@example です"
        assertEquals("https://www.youtube.com/@example", SharedLinkParser.extractYouTubeUrl(text))
    }

    @Test
    fun extractsUrlWithoutScheme() {
        assertEquals("https://youtube.com/@example", SharedLinkParser.extractYouTubeUrl("youtube.com/@example"))
    }

    @Test
    fun returnsNullWhenTextHasNoYouTubeUrl() {
        assertNull(SharedLinkParser.extractYouTubeUrl("ただのテキスト"))
        assertNull(SharedLinkParser.extractYouTubeUrl("https://example.com/watch?v=dQw4w9WgXcQ"))
    }
}
