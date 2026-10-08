package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.network.YouTubeApiClient
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** 最初の案内「人気動画から選ぶ」の一覧の読み取り（サーバーの答えと、予備の直接の問い合わせ）。 */
class PopularVideoTest {

    private fun parse(text: String) = Json.parseToJsonElement(text) as JsonObject

    @Test
    fun readsServerResponseAndKeepsOneVideoPerChannel() {
        val body = parse(
            """{"region":"JP","items":[
              {"videoId":"v1","title":"a","channelId":"C1","channelTitle":"ch1","thumbnailUrl":"https://i/1.jpg"},
              {"videoId":"v2","title":"b","channelId":"C1","channelTitle":"ch1","thumbnailUrl":null},
              {"videoId":"v3","title":"c","channelId":"C2","channelTitle":"ch2","thumbnailUrl":null}
            ]}""",
        )
        val items = YouTubeApiClient.popularFromServer(body)
        assertEquals(listOf("v1", "v3"), items.map { it.videoId })
        assertNull("JSON の null は文字列 \"null\" にしない", items[1].thumbnailUrl)
    }

    @Test
    fun skipsServerItemsWithoutChannel() {
        val body = parse("""{"items":[{"videoId":"v1","title":"a"},{"videoId":"v2","channelId":"C2"}]}""")
        assertEquals(listOf("v2"), YouTubeApiClient.popularFromServer(body).map { it.videoId })
    }

    @Test
    fun readsMostPopularChartResponse() {
        val body = parse(
            """{"items":[
              {"id":"v1","snippet":{"title":"a","channelId":"C1","channelTitle":"ch1"}},
              {"id":"v2","snippet":{"title":"b","channelId":"C1","channelTitle":"ch1"}},
              {"id":"v3","snippet":{"title":"c","channelId":"C2","channelTitle":"ch2"}}
            ]}""",
        )
        assertEquals(listOf("C1", "C2"), YouTubeApiClient.popularVideos(body).map { it.channelId })
    }

    /** 動画URLから来たときにすぐ再生する1本（videos.list の snippet・statistics）。 */
    @Test
    fun readsVideoForQuickStart() {
        val body = parse(
            """{"items":[{"id":"abcdefghijk","snippet":{"title":"t","description":"d",
              "publishedAt":"2024-01-02T03:04:05Z","channelId":"UC1"},"statistics":{"viewCount":"1234"}}]}""",
        )
        val video = YouTubeApiClient.videoFromVideosList(body)!!
        assertEquals("abcdefghijk", video.id)
        assertEquals("UC1", video.channelId)
        assertEquals(1234L, video.viewCount)
        assertEquals(1704164645L, video.publishedAtEpochSeconds)
        assertNull(YouTubeApiClient.videoFromVideosList(parse("""{"items":[]}""")))
    }
}

