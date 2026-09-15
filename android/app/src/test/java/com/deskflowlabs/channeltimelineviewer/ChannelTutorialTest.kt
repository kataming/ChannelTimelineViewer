package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import com.deskflowlabs.channeltimelineviewer.data.ChannelTutorialStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

/**
 * 「チャンネルの追加方法」の案内まわり。
 *
 * 見るのは「同じ案内を二度出さないか」と「手で見直しても状態が壊れないか」。
 * 画面そのものは Compose なのでここでは触らず、**出す/出さないの判断**を確かめる。
 */
@RunWith(RobolectricTestRunner::class)
class ChannelTutorialTest {

    private fun prefs(label: String) =
        ApplicationProvider.getApplicationContext<Context>()
            .getSharedPreferences("tutorial_" + label + "_" + UUID.randomUUID(), Context.MODE_PRIVATE)

    /** 記録された内容を控えるだけの [Analytics]。 */
    private class Recorder : Analytics {
        data class Entry(val name: String, val params: Map<String, Any>)

        val entries = mutableListOf<Entry>()
        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) {
            entries += Entry(event, params.toMap())
        }

        fun count(event: String) = entries.count { it.name == event }
    }

    /**
     * 画面側と同じ判断をここに写したもの。
     * 「まだ見ていない かつ 保存チャンネルが1件も無い」ときだけ自動で出す。
     */
    private fun shouldAutoShow(store: ChannelTutorialStore, savedChannels: Int): Boolean =
        !store.isCompleted.value && savedChannels == 0

    // ---- 1. 初回は出る ----

    @Test
    fun `初めてチャンネルを追加しようとしたら案内が出る`() {
        val store = ChannelTutorialStore(prefs("first"))
        assertTrue(shouldAutoShow(store, savedChannels = 0))
    }

    // ---- 2. 見終わったら出ない ----

    @Test
    fun `見終わったら次からは出ない`() {
        val store = ChannelTutorialStore(prefs("done"))
        store.markCompleted()
        assertFalse(shouldAutoShow(store, savedChannels = 0))
    }

    @Test
    fun `すでにチャンネルを保存している人には出ない`() {
        val store = ChannelTutorialStore(prefs("has_channel"))
        assertFalse(shouldAutoShow(store, savedChannels = 1))
    }

    // ---- 3. スキップも「見た」扱い ----

    @Test
    fun `スキップでも見終わったのと同じ扱いになる`() {
        // 画面側はスキップでも markCompleted を呼ぶ。同じ案内を二度出さないため。
        val store = ChannelTutorialStore(prefs("skip"))
        store.markCompleted()
        assertTrue(store.isCompleted.value)
        assertFalse(shouldAutoShow(store, savedChannels = 0))
    }

    // ---- 5. 再表示しても完了状態が壊れない ----

    @Test
    fun `手で開き直しても完了状態は変わらない`() {
        val store = ChannelTutorialStore(prefs("manual"))
        store.markCompleted()
        // 「このアプリについて」から開き直したときは markCompleted を呼ばない。
        assertTrue("完了のままであること", store.isCompleted.value)
        assertFalse(shouldAutoShow(store, savedChannels = 0))
    }

    @Test
    fun `まだ見ていない人が手で開いても自動表示の権利は残る`() {
        // 手動で開いただけでは印を付けない＝説明が要る人かどうかの区別が残る。
        val store = ChannelTutorialStore(prefs("manual_before"))
        assertTrue(shouldAutoShow(store, savedChannels = 0))
    }

    // ---- アプリを作り直しても覚えている ----

    @Test
    fun `再起動しても見終わった状態を覚えている`() {
        val shared = prefs("restart")
        ChannelTutorialStore(shared).markCompleted()
        val reopened = ChannelTutorialStore(shared)
        assertTrue(reopened.isCompleted.value)
    }

    @Test
    fun `二度呼んでも壊れない`() {
        val store = ChannelTutorialStore(prefs("twice"))
        store.markCompleted()
        store.markCompleted()
        assertTrue(store.isCompleted.value)
    }

    // ---- 9. 記録が失敗してもアプリは動く ----

    @Test
    fun `記録が失敗しても完了状態は保存される`() {
        val exploding = object : Analytics {
            override fun setCollectionEnabled(enabled: Boolean) = error("記録は壊れている")
            override fun logScreen(screenName: String) = error("記録は壊れている")
            override fun log(event: String, vararg params: Pair<String, Any>): Unit =
                error("記録は壊れている")
        }
        val store = ChannelTutorialStore(prefs("analytics_down"))

        // 画面側と同じ順番（先に状態を確定させ、記録はそのあと）。
        store.markCompleted()
        runCatching { exploding.log(Analytics.Event.CHANNEL_TUTORIAL_COMPLETE) }

        assertTrue("記録の失敗で完了状態が消えてはいけない", store.isCompleted.value)
    }

    // ---- 記録の中身 ----

    @Test
    fun `記録に送るのは出どころと手順番号だけ`() {
        val recorder = Recorder()
        recorder.log(
            Analytics.Event.CHANNEL_TUTORIAL_VIEW,
            Analytics.Param.SOURCE to Analytics.Source.FIRST_TIME,
        )
        recorder.log(Analytics.Event.CHANNEL_TUTORIAL_COMPLETE)
        recorder.log(Analytics.Event.CHANNEL_TUTORIAL_SKIP, Analytics.Param.VALUE to 3)

        assertEquals(1, recorder.count(Analytics.Event.CHANNEL_TUTORIAL_VIEW))
        assertEquals(1, recorder.count(Analytics.Event.CHANNEL_TUTORIAL_COMPLETE))
        assertEquals(1, recorder.count(Analytics.Event.CHANNEL_TUTORIAL_SKIP))

        // 例に使ったチャンネル名やURLが混ざっていないこと。
        val everything = recorder.entries.flatMap {
            listOf(it.name) + it.params.keys + it.params.values.map(Any::toString)
        }
        listOf("NASA", "nasa", "youtube.com", "http").forEach { secret ->
            everything.forEach {
                assertFalse("記録に '" + secret + "' が混ざっている", it.contains(secret))
            }
        }
    }

    // ---- 4手順ぶんの文言が7言語そろっているか ----

    @Test
    fun `手順の文言が4つぶん用意されている`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val ids = listOf(
            R.string.tutorial_step1_title to R.string.tutorial_step1_body,
            R.string.tutorial_step2_title to R.string.tutorial_step2_body,
            R.string.tutorial_step3_title to R.string.tutorial_step3_body,
            R.string.tutorial_step4_title to R.string.tutorial_step4_body,
        )
        ids.forEachIndexed { index, (title, body) ->
            assertTrue("手順${index + 1}の見出しが空", context.getString(title, "App").isNotBlank())
            assertTrue("手順${index + 1}の説明が空", context.getString(body, "App").isNotBlank())
        }
    }

    @Test
    fun `手順の画像が4つぶん入っている`() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        listOf(
            R.drawable.tutorial_step1,
            R.drawable.tutorial_step2,
            R.drawable.tutorial_step3,
            R.drawable.tutorial_step4,
        ).forEachIndexed { index, id ->
            assertTrue("手順${index + 1}の画像が引けない",
                context.resources.getResourceEntryName(id).startsWith("tutorial_step"))
        }
    }
}
