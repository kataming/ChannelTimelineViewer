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
 * Billing SDK の型を持ち込まないので、そのままユニットテストできる（[ConnectionGateTest]）。
 */
class ConnectionGate(
    /** いま繋がっているか（`BillingClient.isReady`）。 */
    private val isReady: () -> Boolean,
    /** 接続を始める。繋がったかどうかを引数にして呼び戻すこと。 */
    private val startConnection: (onFinished: (Boolean) -> Unit) -> Unit,
) {

    private class Waiting(val action: () -> Unit, val onUnavailable: () -> Unit)

    private val waiting = mutableListOf<Waiting>()
    private var connecting = false

    /**
     * 繋がっていれば [action] を今すぐ、まだなら繋いでから実行する。
     * 繋がらなかったときは [onUnavailable]（既定では何もしない）。
     */
    fun run(onUnavailable: () -> Unit = {}, action: () -> Unit) {
        if (runCatching { isReady() }.getOrDefault(false)) {
            runCatching(action)
            return
        }

        val shouldStart: Boolean
        synchronized(waiting) {
            waiting += Waiting(action, onUnavailable)
            shouldStart = !connecting
            if (shouldStart) connecting = true
        }
        if (!shouldStart) return // すでに接続中。結果が出たら一緒に片付けられる。

        // 接続を始められなかった場合も、預かった依頼を必ず片付ける。
        runCatching { startConnection { connected -> finish(connected) } }
            .onFailure { finish(connected = false) }
    }

    /** 接続の結果が出た。待っていた依頼をまとめて片付ける。 */
    private fun finish(connected: Boolean) {
        val pending: List<Waiting>
        synchronized(waiting) {
            connecting = false
            pending = waiting.toList()
            waiting.clear()
        }
        pending.forEach { item ->
            runCatching { if (connected) item.action() else item.onUnavailable() }
        }
    }
}
