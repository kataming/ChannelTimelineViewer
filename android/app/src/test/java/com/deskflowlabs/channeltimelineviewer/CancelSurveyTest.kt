package com.deskflowlabs.channeltimelineviewer

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.deskflowlabs.channeltimelineviewer.analytics.Analytics
import com.deskflowlabs.channeltimelineviewer.billing.CancelSurveyStore
import com.deskflowlabs.channeltimelineviewer.billing.ProPurchaseReporter
import com.deskflowlabs.channeltimelineviewer.billing.ReportedPurchaseStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.UUID

/**
 * 購入をやめた直後の一問アンケート（2026-10-02・1.16〜）。
 * 出しすぎないこと（7 日に 1 回）と、決まった値しか送らないことを確かめる。
 */
@RunWith(RobolectricTestRunner::class)
class CancelSurveyTest {

    private class Recorder : Analytics {
        val entries = mutableListOf<Pair<String, Map<String, Any>>>()
        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) {
            entries += event to params.toMap()
        }
    }

    private fun prefs() = ApplicationProvider.getApplicationContext<Context>()
        .getSharedPreferences("survey_" + UUID.randomUUID(), Context.MODE_PRIVATE)

    private val day = 24L * 60 * 60 * 1000

    @Test
    fun `同じ端末では 7 日に 1 回まで`() {
        var now = 1_000_000_000_000L
        val store = CancelSurveyStore(prefs()) { now }
        assertTrue("初めては聞く", store.tryAsk())
        assertFalse("すぐ次のキャンセルでは聞かない", store.tryAsk())
        now += 6 * day
        assertFalse("6 日後もまだ聞かない", store.tryAsk())
        now += day
        assertTrue("7 日たったら聞く", store.tryAsk())
    }

    @Test
    fun `端末の時計が戻されても聞き直さない`() {
        var now = 2_000_000_000_000L
        val store = CancelSurveyStore(prefs()) { now }
        assertTrue(store.tryAsk())
        now -= 30 * day
        assertFalse(store.tryAsk())
    }

    @Test
    fun `答えは決まった値だけ送る`() {
        val recorder = Recorder()
        val reporter = ProPurchaseReporter(recorder, ReportedPurchaseStore(prefs()))
        Analytics.CancelReason.ALL.forEach(reporter::cancelReason)
        reporter.cancelReason("自由記述は送らない")

        assertEquals(Analytics.CancelReason.ALL.size, recorder.entries.size)
        recorder.entries.forEach { (event, params) ->
            assertEquals(Analytics.Event.PRO_CANCEL_REASON, event)
            assertEquals(setOf(Analytics.Param.REASON), params.keys)
            assertTrue(params[Analytics.Param.REASON] in Analytics.CancelReason.ALL)
        }
    }

    @Test
    fun `アンケートの答えはエラーにも実売にも数えない`() {
        val recorder = Recorder()
        ProPurchaseReporter(recorder, ReportedPurchaseStore(prefs()))
            .cancelReason(Analytics.CancelReason.NO_PAYMENT_METHOD)
        val names = recorder.entries.map { it.first }
        assertFalse(Analytics.Event.PRO_PURCHASE_ERROR in names)
        assertFalse(Analytics.Event.PRO_PURCHASE_SUCCESS in names)
        assertFalse(Analytics.Event.PRO_PURCHASE_CANCEL in names)
    }
}
