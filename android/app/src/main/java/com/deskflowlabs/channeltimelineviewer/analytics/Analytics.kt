package com.deskflowlabs.channeltimelineviewer.analytics

/**
 * 利用状況の記録（Google Analytics for Firebase）への入り口。
 *
 * アプリ側のコードは Firebase の型を直接触らず、必ずこの窓口を通す。理由は3つ。
 *   1. 設定ファイル（google-services.json）が無いビルドでも動くようにするため
 *      （その場合は [Noop] が入り、呼んでも何も起きない）
 *   2. ViewModel のユニットテストで Firebase を持ち込まないため
 *   3. **何を送っているかをこのファイルだけ見れば分かる**ようにするため
 *
 * ⚠️ 送ってよいのは「アプリの使われ方」だけ。次は**絶対に送らない**:
 *   - チャンネルID / 動画ID / 動画タイトル / チャンネル名（＝その人が何を見ているか）
 *   - 入力された URL、メモの中身
 *   - 端末を特定できる識別子（広告ID は manifest 側で無効化済み）
 * 迷ったら送らない。数を数えるだけで足りるように [Event] を設計してある。
 */
interface Analytics {

    /** 計測そのものの入り切り。ユーザーが「このアプリについて」で切り替える。 */
    fun setCollectionEnabled(enabled: Boolean)

    /** 画面表示。[Screen] の値を渡す。 */
    fun logScreen(screenName: String)

    /** 出来事。名前は [Event]、引数の名前は [Param] を使う。 */
    fun log(event: String, vararg params: Pair<String, Any>)

    /** 何もしない実装。設定ファイルが無いビルドとテストで使う。 */
    object Noop : Analytics {
        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) = Unit
    }

    /** 画面の名前。Firebase の `screen_view` に渡す。 */
    object Screen {
        const val INPUT = "channel_input"
        const val ABOUT = "about"
        const val PRO = "pro"
        const val VIDEO_LIST = "video_list"
        const val PLAYER = "player"
    }

    /**
     * 出来事の名前。
     * Firebase の制限に合わせて **40文字以内・英小文字と数字と _ のみ・先頭は英字**にする
     * （`firebase_` / `google_` / `ga_` で始まる名前は使えない）。
     * 制限は `AnalyticsNamingTest` で機械的に確認している。
     */
    object Event {
        /** チャンネルの一覧を開いた。[Param.SOURCE] にどこから開いたか。 */
        const val CHANNEL_OPEN = "channel_open"

        /** 無料の保存上限に当たって案内を出した。 */
        const val CHANNEL_LIMIT_HIT = "channel_limit_hit"

        /** 保存中のチャンネルを外して入れ替えた（記録が消える操作）。 */
        const val CHANNEL_REPLACE = "channel_replace"

        /** 保存を解除した。 */
        const val CHANNEL_REMOVE = "channel_remove"

        /** 動画を開いた。[Param.SOURCE] にどうやって開いたか。 */
        const val VIDEO_OPEN = "video_open"

        /** 動画を最後まで見た。[Param.RESULT] に、そのあとどうなったか。 */
        const val VIDEO_FINISH = "video_finish"

        /** 再生設定を切り替えた。[Param.SETTING] と [Param.VALUE]。 */
        const val PLAYBACK_SETTING = "playback_setting"

        /** 「YouTubeで開く」を押した。 */
        const val OPEN_IN_YOUTUBE = "open_in_youtube"

        /** Pro の購入を始めた。 */
        const val PRO_PURCHASE_START = "pro_purchase_start"

        /** Pro の購入が終わった。[Param.RESULT] に purchased / pending。 */
        const val PRO_PURCHASE_END = "pro_purchase_end"

        /** 「購入を復元」を押した。 */
        const val PRO_RESTORE = "pro_restore"

    }

    /** 引数の名前。値は列挙した短い文字列か数値だけにする。 */
    object Param {
        /** どこから始めたか。値は [Source]。 */
        const val SOURCE = "source"

        /** 結果。値は [Result]。 */
        const val RESULT = "result"

        /** 設定の名前。値は [Setting]。 */
        const val SETTING = "setting"

        /** 設定の値（オン/オフは "on" / "off"、繰り返しは [RepeatValue]）。 */
        const val VALUE = "value"

        /** 一覧の本数（1本ずつではなく、規模を知るために使う）。 */
        const val VIDEO_COUNT = "video_count"
    }

    object Source {
        /** URL を入力して開いた。 */
        const val URL = "url"

        /** 他アプリからの共有で開いた。 */
        const val SHARE = "share"

        /** 保存済みの一覧から開いた。 */
        const val SAVED = "saved"

        /** ロック中のチャンネルへ切り替えて開いた。 */
        const val SWITCH = "switch"

        /** 一覧で選んで開いた。 */
        const val LIST = "list"

        /** 自動再生で次に進んだ。 */
        const val AUTO_ADVANCE = "auto_advance"

        /** 移動ボタン（次/前/最初/最後/戻す）で移動した。 */
        const val NAVIGATION = "navigation"
    }

    object Result {
        /** 自動再生で次の動画へ進んだ。 */
        const val AUTO_NEXT = "auto_next"

        /** 1本リピートでもう一度再生した。 */
        const val REPEAT_ONE = "repeat_one"

        /** そこで止まって次の案内を出した。 */
        const val STOPPED = "stopped"

        /** 購入できた。 */
        const val PURCHASED = "purchased"

        /** 保留中（コンビニ払いなど）。 */
        const val PENDING = "pending"
    }

    object Setting {
        const val AUTOPLAY_NEXT = "autoplay_next"
        const val RESUME = "resume"
        const val REPEAT = "repeat"
        const val UNWATCHED_ONLY = "unwatched_only"
    }

    object RepeatValue {
        const val OFF = "off"
        const val ONE = "one"
        const val ALL = "all"
    }

    companion object {
        /** オン/オフを表す値（[Param.VALUE] に使う）。 */
        fun onOff(enabled: Boolean): String = if (enabled) "on" else "off"
    }
}
