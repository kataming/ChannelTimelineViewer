package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.billing.ChannelSlotPolicy
import com.deskflowlabs.channeltimelineviewer.billing.ProEntitlementStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * 無料は1チャンネル、Pro は複数。制限するのは保存件数だけ、という約束のテスト。
 */
@RunWith(RobolectricTestRunner::class)
class ProEntitlementTest {

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>()
        .getSharedPreferences("pro_test_${System.nanoTime()}", Context.MODE_PRIVATE)

    @Test
    fun `無料は1件目を保存できる`() {
        assertTrue(ChannelSlotPolicy.canOpen(emptyList(), "UC_new", isPro = false))
    }

    @Test
    fun `無料は2件目を保存できない`() {
        assertFalse(ChannelSlotPolicy.canOpen(listOf("UC_a"), "UC_new", isPro = false))
    }

    @Test
    fun `無料でも保存済みのチャンネルは開ける`() {
        assertTrue(ChannelSlotPolicy.canOpen(listOf("UC_a"), "UC_a", isPro = false))
    }

    @Test
    fun `Proなら何件でも保存できる`() {
        assertTrue(ChannelSlotPolicy.canOpen(listOf("UC_a", "UC_b"), "UC_new", isPro = true))
    }

    @Test
    fun `以前から複数保存している人も保存済みは開ける`() {
        // 課金を入れる前に3件保存していた利用者。減らすのは本人に任せ、勝手には消さない。
        val saved = listOf("UC_a", "UC_b", "UC_c")
        assertTrue(ChannelSlotPolicy.canOpen(saved, "UC_b", isPro = false))
        assertFalse(ChannelSlotPolicy.canOpen(saved, "UC_new", isPro = false))
    }

    @Test
    fun `入れ替えでは空きを作るぶんだけ古いものを外す`() {
        assertEquals(listOf("UC_a"), ChannelSlotPolicy.idsToRemoveForReplacement(listOf("UC_a")))
        // 以前から2件保存している人が入れ替えを選んだら、空きを作るため両方が外れる。
        assertEquals(
            listOf("UC_b", "UC_c"),
            ChannelSlotPolicy.idsToRemoveForReplacement(listOf("UC_b", "UC_c")),
        )
        assertTrue(ChannelSlotPolicy.idsToRemoveForReplacement(emptyList()).isEmpty())
    }

    @Test
    fun `Proなら保存済みは全部使える`() {
        val saved = listOf("UC_a", "UC_b", "UC_c")
        assertEquals(
            saved.toSet(),
            ChannelSlotPolicy.usableChannelIds(saved, isPro = true, activeChannelId = null),
        )
    }

    @Test
    fun `Proが外れると上限を超えた分はロックされる`() {
        // 返金などで Pro を失った状態。保存は消さないが、使えるのは1つだけにする。
        val saved = listOf("UC_new", "UC_old")
        assertEquals(
            setOf("UC_new"),
            ChannelSlotPolicy.usableChannelIds(saved, isPro = false, activeChannelId = null),
        )
        assertTrue(ChannelSlotPolicy.isLocked(saved, "UC_old", isPro = false, activeChannelId = null))
        assertFalse(ChannelSlotPolicy.isLocked(saved, "UC_new", isPro = false, activeChannelId = null))
    }

    @Test
    fun `選んだチャンネルが使える方になる`() {
        val saved = listOf("UC_new", "UC_old")
        assertEquals(
            setOf("UC_old"),
            ChannelSlotPolicy.usableChannelIds(saved, isPro = false, activeChannelId = "UC_old"),
        )
        assertTrue(ChannelSlotPolicy.isLocked(saved, "UC_new", isPro = false, activeChannelId = "UC_old"))
    }

    @Test
    fun `保存が1件だけならロックは起きない`() {
        val saved = listOf("UC_a")
        assertEquals(
            setOf("UC_a"),
            ChannelSlotPolicy.usableChannelIds(saved, isPro = false, activeChannelId = null),
        )
        assertFalse(ChannelSlotPolicy.isLocked(saved, "UC_a", isPro = false, activeChannelId = null))
    }

    @Test
    fun `選んだチャンネルが消えていても1つは使える`() {
        val saved = listOf("UC_a", "UC_b")
        assertEquals(
            setOf("UC_a"),
            ChannelSlotPolicy.usableChannelIds(saved, isPro = false, activeChannelId = "UC_gone"),
        )
    }

    @Test
    fun `購入前は無料あつかい`() {
        assertFalse(ProEntitlementStore(prefs()).isPro.value)
    }

    @Test
    fun `購入したらProになり、保存し直しても残る`() {
        val prefs = prefs()
        ProEntitlementStore(prefs).grant()
        assertTrue(ProEntitlementStore(prefs).isPro.value)
    }

    @Test
    fun `Playが購入なしと答えたときだけProを外す`() {
        val prefs = prefs()
        val store = ProEntitlementStore(prefs)
        store.grant()
        store.applyPlayQuery(hasEntitlement = true)
        assertTrue(store.isPro.value)

        store.applyPlayQuery(hasEntitlement = false)
        assertFalse(store.isPro.value)
        // 保存もされている（別インスタンスで読んでも false）。
        assertFalse(ProEntitlementStore(prefs).isPro.value)
    }
}
