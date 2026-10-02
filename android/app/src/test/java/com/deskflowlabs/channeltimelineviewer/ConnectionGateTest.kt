package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.billing.ConnectionGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 接続待ちの受け付け口のテスト（2026-09-21）。
 *
 * ここが守れないと、Pro 画面で**購入ボタンを押しても何も起きず、ぐるぐる表示のまま
 * 操作できなくなる**（画面を出入りしないと直らない）。以前それが起きていたので、
 * 「預かった依頼は必ずどちらか一方を1回だけ実行する」を機械的に確かめる。
 */
class ConnectionGateTest {

    /** 接続の成否を後から決められる、テスト用の接続役。 */
    private class FakeConnection {
        var ready = false
        var startCount = 0
        private var finish: ((Boolean) -> Unit)? = null

        fun gate() = ConnectionGate(
            isReady = { ready },
            startConnection = { onFinished ->
                startCount++
                finish = onFinished
            },
        )

        fun complete(connected: Boolean) {
            ready = connected
            val callback = finish
            finish = null
            callback?.invoke(connected)
        }
    }

    /** 画面の状態（ぐるぐる表示）を真似たもの。 */
    private class Busy {
        var value = false
        fun start() { value = true }
        fun stop() { value = false }
    }

    @Test
    fun runsImmediatelyWhenAlreadyConnected() {
        val fake = FakeConnection().apply { ready = true }
        var actions = 0
        fake.gate().run(onUnavailable = { fail() }) { actions++ }
        assertEquals(1, actions)
        assertEquals("繋がっていれば接続しない", 0, fake.startCount)
    }

    @Test
    fun waitsForTheConnectionThenRuns() {
        val fake = FakeConnection()
        val gate = fake.gate()
        var actions = 0
        gate.run(onUnavailable = { fail() }) { actions++ }
        assertEquals(0, actions)
        fake.complete(connected = true)
        assertEquals(1, actions)
    }

    /** ⚠️ 本題: 接続中に来た依頼も必ず片付く（ぐるぐる表示が残らない）。 */
    @Test
    fun requestArrivingWhileConnectingIsNotDropped() {
        val fake = FakeConnection()
        val gate = fake.gate()
        val busy = Busy()

        // 画面を開いた直後の読み直し（接続が始まる）。
        gate.run { /* 価格の読み直し */ }
        // その最中に購入ボタンを押した。
        busy.start()
        var launched = 0
        gate.run(onUnavailable = { busy.stop() }) {
            busy.stop()
            launched++
        }

        assertEquals("接続は1回だけ", 1, fake.startCount)
        fake.complete(connected = true)
        assertEquals("購入は始まる", 1, launched)
        assertFalse("ぐるぐる表示が残らない", busy.value)
    }

    @Test
    fun busyIsClearedWhenTheConnectionFails() {
        val fake = FakeConnection()
        val gate = fake.gate()
        val busy = Busy()
        busy.start()
        var launched = 0
        gate.run(onUnavailable = { busy.stop() }) { launched++ }
        fake.complete(connected = false)
        assertEquals("購入は始まらない", 0, launched)
        assertFalse("ぐるぐる表示が残らない", busy.value)
    }

    /** 失敗したあと、もう一度購入できる（接続をやり直せる）。 */
    @Test
    fun canTryAgainAfterAFailure() {
        val fake = FakeConnection()
        val gate = fake.gate()
        val busy = Busy()

        busy.start()
        gate.run(onUnavailable = { busy.stop() }) { fail() }
        fake.complete(connected = false)
        assertFalse(busy.value)

        busy.start()
        var launched = 0
        gate.run(onUnavailable = { busy.stop() }) {
            busy.stop()
            launched++
        }
        assertEquals("接続をやり直す", 2, fake.startCount)
        fake.complete(connected = true)
        assertEquals(1, launched)
        assertFalse(busy.value)
    }

    @Test
    fun everyWaitingRequestIsFinishedExactlyOnce() {
        val fake = FakeConnection()
        val gate = fake.gate()
        var actions = 0
        var unavailable = 0
        repeat(5) { gate.run(onUnavailable = { unavailable++ }) { actions++ } }
        fake.complete(connected = true)
        assertEquals(5, actions)
        assertEquals(0, unavailable)
        // 二重に呼ばれない。
        fake.complete(connected = true)
        assertEquals(5, actions)
    }

    @Test
    fun startingTheConnectionCanFailWithoutLeavingBusy() {
        val gate = ConnectionGate(
            isReady = { false },
            startConnection = { error("Play ストアが無い") },
        )
        val busy = Busy()
        busy.start()
        gate.run(onUnavailable = { busy.stop() }) { fail() }
        assertFalse(busy.value)
    }

    @Test
    fun oneBrokenRequestDoesNotBlockTheOthers() {
        val fake = FakeConnection()
        val gate = fake.gate()
        var actions = 0
        gate.run { error("壊れた依頼") }
        gate.run { actions++ }
        fake.complete(connected = true)
        assertEquals(1, actions)
    }

    @Test
    fun brokenReadinessCheckIsTreatedAsNotConnected() {
        val gate = ConnectionGate(
            isReady = { error("判定できない") },
            startConnection = { onFinished -> onFinished(true) },
        )
        var actions = 0
        gate.run { actions++ }
        assertEquals(1, actions)
    }

    // ---- 2026-10-03: 接続の返事が来ない・二重に来る ----

    /** 予約した処理を手で進められる時計。 */
    private class FakeTimer {
        val scheduled = mutableListOf<() -> Unit>()
        fun schedule(@Suppress("UNUSED_PARAMETER") delay: Long, block: () -> Unit) { scheduled += block }
        fun fireAll() { scheduled.toList().also { scheduled.clear() }.forEach { it() } }
    }

    private class Recall {
        var finish: ((Boolean) -> Unit)? = null
        var startCount = 0
    }

    private fun timedGate(recall: Recall, timer: FakeTimer, onTimeout: () -> Unit = {}) = ConnectionGate(
        isReady = { false },
        startConnection = { onFinished ->
            recall.startCount++
            recall.finish = onFinished
        },
        scheduleTimeout = timer::schedule,
        onTimeout = onTimeout,
    )

    /** ⚠️ 本題: 先に始まった接続が返事をしないまま。並んだ購入依頼も時間切れで必ず片付く。 */
    @Test
    fun requestWaitingBehindAHungConnectionIsFinishedByTimeout() {
        val recall = Recall()
        val timer = FakeTimer()
        var timeouts = 0
        val gate = timedGate(recall, timer) { timeouts++ }
        val busy = Busy()

        gate.run { /* 起動時の読み直し（ここで接続が始まり、返事が来ない） */ }
        busy.start()
        gate.run(onUnavailable = { busy.stop() }) { fail() } // 接続中なので列に並ぶ（早期 return）
        assertTrue(busy.value)

        timer.fireAll()
        assertFalse("時間切れでぐるぐる表示が戻る", busy.value)
        assertEquals(1, timeouts)

        // 時間切れのあとに遅れて届いた結果は捨てる（購入が勝手に始まらない）。
        recall.finish?.invoke(true)
    }

    @Test
    fun timeoutAfterSuccessDoesNothing() {
        val recall = Recall()
        val timer = FakeTimer()
        var timeouts = 0
        var actions = 0
        val gate = timedGate(recall, timer) { timeouts++ }
        gate.run(onUnavailable = { fail() }) { actions++ }
        recall.finish?.invoke(true)
        timer.fireAll()
        assertEquals(1, actions)
        assertEquals("成功したあとの時間切れは記録しない", 0, timeouts)
    }

    /** 切断の通知（false）と接続結果（true）が両方届いても、依頼は1回だけ片付く。 */
    @Test
    fun doubleResultFinishesEachRequestOnce() {
        val recall = Recall()
        val timer = FakeTimer()
        val gate = timedGate(recall, timer)
        var actions = 0
        var unavailable = 0
        gate.run(onUnavailable = { unavailable++ }) { actions++ }
        val finish = recall.finish!!
        finish(false)
        finish(true)
        assertEquals(0, actions)
        assertEquals(1, unavailable)
    }

    /** 古い接続の遅れた結果が、次の接続を待っている依頼を巻き込まない。 */
    @Test
    fun staleResultDoesNotFinishTheNextAttempt() {
        val recall = Recall()
        val timer = FakeTimer()
        val gate = timedGate(recall, timer)
        gate.run(onUnavailable = {}) { fail() }
        val stale = recall.finish!!
        timer.fireAll() // 1回目は時間切れ

        var actions = 0
        gate.run(onUnavailable = { fail() }) { actions++ }
        assertEquals("やり直しの接続が始まる", 2, recall.startCount)
        stale(false) // 1回目の遅れた返事
        assertEquals(0, actions)
        recall.finish!!(true)
        assertEquals(1, actions)
    }

    private fun fail(): Unit = assertTrue("呼ばれてはいけない", false)
}
