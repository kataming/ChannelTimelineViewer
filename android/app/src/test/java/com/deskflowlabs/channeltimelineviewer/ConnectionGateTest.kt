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

    private fun fail(): Unit = assertTrue("呼ばれてはいけない", false)
}
