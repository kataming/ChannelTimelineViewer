package com.deskflowlabs.channeltimelineviewer.billing

/**
 * 「Play に繋がってから実行する」の受け付け口。
 *
 * ⚠️ ここが守る約束: **預かった依頼は、必ず [action] か [onUnavailable] のどちらか一方を
 *    1回だけ実行する。**（2026-09-21 追加）
 *
 * 以前は「接続中なら黙って帰る」実装だったため、Pro 画面を開いた直後（接続中）に購入ボタンを
 * 押すと何も起きず、`isBusy` が true のまま戻らなかった。購入ボタンも復元ボタンも押せなくなり、
 * 画面を出入りしないと直らない、という不具合になっていた。
 * いまは接続中の依頼を**列に並べて**おき、接続の成否が分かった時点でまとめて片付ける。
 *
 * 2026-10-03 追加: 接続の結果が**いつまでも返ってこない**場合も片付ける。
 * 「接続中なので列に並ぶ」早期 return は、先に始まった接続が終わる前提に立っている。
 * その接続が返事をしないと、並んだ購入依頼は永久に待ち続け `isBusy` が戻らない。
 * [scheduleTimeout] を渡すと、[timeoutMillis] 経っても結果が無い接続を「繋がらなかった」として
 * 片付ける。遅れて届いた結果・二重に届いた結果は捨てる（依頼が二度実行されないように）。
 *
 * Billing SDK の型を持ち込まないので、そのままユニットテストできる（[ConnectionGateTest]）。
 */
class ConnectionGate(
    /** いま繋がっているか（`BillingClient.isReady`）。 */
    private val isReady: () -> Boolean,
    /** 接続を始める。繋がったかどうかを引数にして呼び戻すこと（2回以上呼ばれても安全）。 */
    private val startConnection: (onFinished: (Boolean) -> Unit) -> Unit,
    /** 一定時間後に処理を予約する（実機では main の Handler）。null なら時間切れを見ない。 */
    private val scheduleTimeout: ((delayMillis: Long, block: () -> Unit) -> Unit)? = null,
    private val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
    /** 時間切れで片付けたときに呼ぶ（診断の記録用）。 */
    private val onTimeout: () -> Unit = {},
) {

    private class Waiting(val action: () -> Unit, val onUnavailable: () -> Unit)

    private val waiting = mutableListOf<Waiting>()
    private var connecting = false

    /** 何回目の接続か。古い接続の結果（遅れて届いた・二重に届いた）を見分けるため。 */
    private var attempt = 0

    /**
     * 繋がっていれば [action] を今すぐ、まだなら繋いでから実行する。
     * 繋がらなかったときは [onUnavailable]（既定では何もしない）。
     */
    fun run(onUnavailable: () -> Unit = {}, action: () -> Unit) {
        if (runCatching { isReady() }.getOrDefault(false)) {
            runCatching(action)
            return
        }

        val myAttempt: Int
        synchronized(waiting) {
            waiting += Waiting(action, onUnavailable)
            if (connecting) return // すでに接続中。結果が出たら（または時間切れで）一緒に片付けられる。
            connecting = true
            myAttempt = ++attempt
        }

        runCatching {
            scheduleTimeout?.invoke(timeoutMillis) {
                if (finish(myAttempt, connected = false)) runCatching(onTimeout)
            }
        }
        // 接続を始められなかった場合も、預かった依頼を必ず片付ける。
        runCatching { startConnection { connected -> finish(myAttempt, connected) } }
            .onFailure { finish(myAttempt, connected = false) }
    }

    /**
     * 接続の結果が出た。待っていた依頼をまとめて片付ける。
     * @return 片付けたら true。すでに片付け済みの接続（時間切れのあとに届いた等）なら false。
     */
    private fun finish(forAttempt: Int, connected: Boolean): Boolean {
        val pending: List<Waiting>
        synchronized(waiting) {
            if (!connecting || forAttempt != attempt) return false
            connecting = false
            pending = waiting.toList()
            waiting.clear()
        }
        pending.forEach { item ->
            runCatching { if (connected) item.action() else item.onUnavailable() }
        }
        return true
    }

    companion object {
        /** 通常は 1〜2 秒で返る。返事が無いまま購入ボタンを固めておく上限。 */
        const val DEFAULT_TIMEOUT_MILLIS = 20_000L
    }
}
