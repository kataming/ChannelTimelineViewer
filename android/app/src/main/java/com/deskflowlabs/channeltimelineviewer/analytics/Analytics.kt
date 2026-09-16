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
        const val WATCH_QUEUE = "watch_queue"
        const val WATCH_QUEUE_PLAYER = "watch_queue_player"
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

        /**
         * Pro の購入フローを始めた（＝購入ボタンを押した）。
         * **売れた数ではない。** 実売は [PRO_PURCHASE_SUCCESS] で数える。
         */
        const val PRO_PURCHASE_START = "pro_purchase_start"

        /**
         * ★実売★ Pro の購入が本当に成立した。
         *
         * Play が PURCHASED を返し、対象商品で、Pro 権限を付与した瞬間だけ送る。
         * 保留・キャンセル・エラー・復元・起動時の既購入検出では**送らない**。
         * 同じ購入で二重に送らないよう [com.deskflowlabs.channeltimelineviewer.billing.ReportedPurchaseStore]
         * で端末に控えている。詳しくは docs/analytics/CTV_PURCHASE_ANALYTICS.md。
         */
        const val PRO_PURCHASE_SUCCESS = "pro_purchase_success"

        /** 購入画面を本人がやめた（USER_CANCELED）。エラーとは区別する。 */
        const val PRO_PURCHASE_CANCEL = "pro_purchase_cancel"

        /** 購入が失敗した。[Param.REASON] に [ErrorReason] の決まった文字だけを入れる。 */
        const val PRO_PURCHASE_ERROR = "pro_purchase_error"

        /** 購入が保留になった（コンビニ払いなど）。**まだ売れていない。** */
        const val PRO_PURCHASE_PENDING = "pro_purchase_pending"

        /** 「購入を復元」を押した。**実売ではない**（すでに買った人の再適用）。 */
        const val PRO_RESTORE = "pro_restore"

        /**
         * 「チャンネルの追加方法」の案内を開いた。
         * [Param.SOURCE] に [Source.FIRST_TIME]（初回の自動表示）か
         * [Source.MANUAL]（「このアプリについて」から開き直した）。
         */
        const val CHANNEL_TUTORIAL_VIEW = "channel_tutorial_view"

        /** 案内を最後まで見て、CTA を押した。 */
        const val CHANNEL_TUTORIAL_COMPLETE = "channel_tutorial_complete"

        /** 案内を途中でやめた。[Param.VALUE] に、やめた時点の手順の番号。 */
        const val CHANNEL_TUTORIAL_SKIP = "channel_tutorial_skip"

        /**
         * GA4 標準の購入イベント。収益レポートに載せるために
         * [PRO_PURCHASE_SUCCESS] と**同じ瞬間・同じ重複防止**で併送する。
         * 金額は Play が返す商品情報からのみ取る（コードに価格を持たない）。
         */
        const val PURCHASE = "purchase"
    }

    /** 引数の名前。値は列挙した短い文字列か数値だけにする。 */
    object Param {
        /** どこから始めたか。値は [Source]。 */
        const val SOURCE = "source"

        /** 結果。値は [Result]。 */
        const val RESULT = "result"

        /** 設定の名前。値は [Setting]。 */
        const val SETTING = "setting"

        /**
         * 設定の値（オン/オフは "on" / "off"、繰り返しは [RepeatValue]）。
         * [Event.PURCHASE] では GA4 標準の売上金額としても使う。
         */
        const val VALUE = "value"

        /** 一覧の本数（1本ずつではなく、規模を知るために使う）。 */
        const val VIDEO_COUNT = "video_count"

        /** 失敗の種類。値は [ErrorReason] に列挙したものだけ。生の例外文は入れない。 */
        const val REASON = "reason"

        /** 通貨コード（GA4 標準の [Event.PURCHASE] 用。Play が返す値をそのまま使う）。 */
        const val CURRENCY = "currency"
    }

    /**
     * 購入が失敗した理由。**決まった短い文字だけ**を送る。
     *
     * Play が返す `debugMessage` や例外の中身は、端末やアカウントの事情が混ざるため
     * Analytics へは絶対に出さない（ログには出してよい）。
     */
    object ErrorReason {
        /** Play ストアに繋がらない・切断された。 */
        const val SERVICE_UNAVAILABLE = "service_unavailable"

        /** その端末/アカウントで課金そのものが使えない。 */
        const val BILLING_UNAVAILABLE = "billing_unavailable"

        /** 商品が見つからない（Play Console 側で未公開など）。 */
        const val ITEM_UNAVAILABLE = "item_unavailable"

        /** こちらの実装・設定の誤り。 */
        const val DEVELOPER_ERROR = "developer_error"

        /** 上のどれでもない失敗。 */
        const val GENERIC_ERROR = "generic_error"
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

        /** 初めてチャンネルを追加しようとしたので、こちらから出した。 */
        const val FIRST_TIME = "first_time"

        /** 「このアプリについて」から、自分で開き直した。 */
        const val MANUAL = "manual"
    }

    object Result {
        /** 自動再生で次の動画へ進んだ。 */
        const val AUTO_NEXT = "auto_next"

        /** 1本リピートでもう一度再生した。 */
        const val REPEAT_ONE = "repeat_one"

        /** そこで止まって次の案内を出した。 */
        const val STOPPED = "stopped"
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
