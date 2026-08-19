package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.network.ChannelIdentifier
import com.deskflowlabs.channeltimelineviewer.network.ChannelResolver
import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * iOS 版 `Tests/ChannelResolverTests.swift` と同じケースを通す。
 * URL の解釈が2つのアプリでずれると「iPhone では開けるのに Android では開けない」が起きるため。
 *
 * `android.net.Uri` を使うので Robolectric 上で実行する。
 */
@RunWith(RobolectricTestRunner::class)
class ChannelResolverTest {

    @Test
    fun channelIdUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/channel/UC1234567890123456789012")
        assertEquals(ChannelIdentifier.ChannelId("UC1234567890123456789012"), result)
    }

    @Test
    fun bareChannelId() {
        val result = ChannelResolver.parse("UC1234567890123456789012")
        assertEquals(ChannelIdentifier.ChannelId("UC1234567890123456789012"), result)
    }

    @Test
    fun handleUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/@example")
        assertEquals(ChannelIdentifier.Handle("example"), result)
    }

    @Test
    fun bareHandle() {
        assertEquals(ChannelIdentifier.Handle("example"), ChannelResolver.parse("@example"))
    }

    @Test
    fun userUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/user/oldschool")
        assertEquals(ChannelIdentifier.Username("oldschool"), result)
    }

    @Test
    fun customCUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/c/SomeChannel")
        assertEquals(ChannelIdentifier.CustomName("SomeChannel"), result)
    }

    @Test
    fun customBareNameUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/SomeChannel")
        assertEquals(ChannelIdentifier.CustomName("SomeChannel"), result)
    }

    @Test
    fun withoutScheme() {
        assertEquals(ChannelIdentifier.Handle("example"), ChannelResolver.parse("youtube.com/@example"))
    }

    @Test
    fun watchUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun watchUrlWithExtraQuery() {
        val result = ChannelResolver.parse("https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&list=PL123")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun mobileWatchUrl() {
        val result = ChannelResolver.parse("https://m.youtube.com/watch?v=dQw4w9WgXcQ")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun shortUrl() {
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), ChannelResolver.parse("https://youtu.be/dQw4w9WgXcQ"))
    }

    @Test
    fun shortUrlWithShareParameter() {
        val result = ChannelResolver.parse("https://youtu.be/dQw4w9WgXcQ?si=abcdefg")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun shortsUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/shorts/dQw4w9WgXcQ")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun liveUrl() {
        val result = ChannelResolver.parse("https://www.youtube.com/live/dQw4w9WgXcQ")
        assertEquals(ChannelIdentifier.Video("dQw4w9WgXcQ"), result)
    }

    @Test
    fun invalidWatchUrlWithoutVideoId() {
        assertThrows(YouTubeApiException::class.java) {
            ChannelResolver.parse("https://www.youtube.com/watch?list=PL123")
        }
    }

    @Test
    fun invalidShortUrlWithBrokenId() {
        assertThrows(YouTubeApiException::class.java) {
            ChannelResolver.parse("https://youtu.be/short")
        }
    }

    @Test
    fun extractVideoId() {
        assertEquals("dQw4w9WgXcQ", ChannelResolver.extractVideoId("https://youtu.be/dQw4w9WgXcQ"))
        assertEquals("dQw4w9WgXcQ", ChannelResolver.extractVideoId("dQw4w9WgXcQ"))
        assertNull(ChannelResolver.extractVideoId("https://www.youtube.com/@example"))
    }

    @Test
    fun isVideoId() {
        assertTrue(ChannelResolver.isVideoId("dQw4w9WgXcQ"))
        assertTrue(!ChannelResolver.isVideoId("short"))
        assertTrue(!ChannelResolver.isVideoId("dQw4w9WgXcQ_toolong"))
    }

    @Test
    fun invalidEmpty() {
        assertThrows(YouTubeApiException::class.java) { ChannelResolver.parse("   ") }
    }

    @Test
    fun rejectsNonYouTubeHost() {
        assertThrows(YouTubeApiException::class.java) {
            ChannelResolver.parse("https://example.com/@handle")
        }
    }
}
