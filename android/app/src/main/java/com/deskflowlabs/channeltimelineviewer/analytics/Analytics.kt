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

    /**
     * ユーザー属性。名前は [UserProperty] を使う。値は区分（free / pro など）だけにする。
     * 既定は何もしない（テスト用の偽物が実装しなくて済むように）。
     */
    fun setUserProperty(name: String, value: String) = Unit

    /** 何もしない実装。設定ファイルが無いビルドとテストで使う。 */
    object Noop : Analytics {
        override fun setCollectionEnabled(enabled: Boolean) = Unit
        override fun logScreen(screenName: String) = Unit
        override fun log(event: String, vararg params: Pair<String, Any>) = Unit
    }

    /**
     * ユーザー属性の名前（24文字以内・英小文字と数字と _）。
     *
     * 広告の収益（AdMob と Firebase を連携すると自動で記録される `ad_impression`）や継続率を
     * 無料／Pro で分けて見るために使う。値は [ProStatus] の2つだけ。
     */
    object UserProperty {
        const val PRO_STATUS = "pro_status"
    }

    object ProStatus {
        const val FREE = "free"
        const val PRO = "pro"

        fun of(isPro: Boolean): String = if (isPro) PRO else FREE
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

        /**
         * 購入が失敗した。[Param.REASON] に [ErrorReason] の決まった文字、
         * [Param.ERROR_STAGE] に [ErrorStage]（どの段階か）、分かるときは
         * [Param.BILLING_RESPONSE_CODE] に Play の応答コード（整数）を入れる（2026-10-02〜）。
         */
        const val PRO_PURCHASE_ERROR = "pro_purchase_error"

        /** 購入が保留になった（コンビニ払いなど）。**まだ売れていない。** */
        const val PRO_PURCHASE_PENDING = "pro_purchase_pending"

        /**
         * 購入をやめた直後の一問アンケートの答え（2026-10-02〜）。[Param.REASON] に [CancelReason] の決まった文字だけ。
         * Play はキャンセルの理由をアプリに教えないので、「支払い方法が無い」のか「価格」なのかを本人に聞く。
         * 同じ端末では 7 日に 1 回まで（[com.deskflowlabs.channeltimelineviewer.billing.CancelSurveyStore]）。
         */
        const val PRO_CANCEL_REASON = "pro_cancel_reason"

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

        // GA4 標準の `purchase` は 1.14 で廃止した（定数も削除）。Google Play とリンク済みの
        // Firebase が同じ購入を `in_app_purchase` として自動で記録し、両方に金額があると
        // 総収益が二重になるため。**戻さないこと**（docs/analytics/CTV_PURCHASE_ANALYTICS.md 第9章）。

        /**
         * 課金まわりの**診断用**。どの段階（[Param.STAGE] = [Stage]）で
         * 何が起きたか（[Param.CATEGORY] = [BillingOutcome]）を、成功も失敗も同じ形で残す。
         * 応答コードがあるときは [Param.BILLING_RESPONSE_CODE] も付ける（2026-10-03〜）。
         * [Param.RESULT] には [Param.CATEGORY] と同じ値を入れ続ける（2026-09-21〜10-02 の版との比較用）。
         *
         * ⚠️ これは**売上の数ではない**。実売は [PRO_PURCHASE_SUCCESS] だけで数える。
         * 上の `pro_purchase_*` の意味は変えていない（これは別口の記録）。
         *
         * 「購入画面までは出ているのに誰も買っていない」のように、Play Console の
         * 購入者コンバージョンだけでは切り分けられないときに使う。
         */
        const val PRO_BILLING_RESULT = "pro_billing_result"
    }

    /** [Event.PRO_BILLING_RESULT] の段階（[Param.STAGE]）。 */
    object Stage {
        /** Play への接続。 */
        const val CONNECT = "connect"

        /** 商品情報（価格・オファー）の取得。 */
        const val QUERY_PRODUCT = "query_product"

        /** 購入画面を開く指示（`launchBillingFlow` の戻り値）。 */
        const val LAUNCH = "launch"

        /** 購入画面のあとに届く結果（`PurchasesUpdatedListener`）。 */
        const val PURCHASE_CALLBACK = "purchase_callback"

        /** 購入の確認（acknowledge）。 */
        const val ACKNOWLEDGE = "acknowledge"

        /**
         * 購入状態の問い合わせ（`queryPurchasesAsync`）。2026-10-03〜。
         * 「購入を復元」・すでに所有していた後の問い直し・失敗したときだけ記録する
         * （起動や前面復帰のたびの成功は記録しない）。
         */
        const val QUERY_PURCHASES = "query_purchases"
    }

    /**
     * [Event.PRO_BILLING_RESULT] の分類（[Param.CATEGORY]）。
     * Play の応答コードを**決まった短い文字**に置き換えたもの。応答コードの整数は
     * [Param.BILLING_RESPONSE_CODE] に別に入れる（Play が決めた固定の番号だけ。文面は送らない）。
     */
    object BillingOutcome {
        const val OK = "ok"
        const val USER_CANCELED = "user_canceled"
        const val PENDING = "pending"

        /** 応答は OK なのに購入の一覧が空（購入せずに画面を閉じた等）。 */
        const val EMPTY_PURCHASE_LIST = "empty_purchase_list"

        /** 応答は OK なのに購入の一覧そのものが無い（null）。2026-10-03〜。 */
        const val NULL_PURCHASE_LIST = "null_purchase_list"

        /** 応答は OK で購入もあるが、pro_unlock が入っていない。2026-10-03〜（以前は empty_purchase_list に含めていた）。 */
        const val NO_PRO_ITEM = "no_pro_item"

        /** pro_unlock はあるが、購入済みでも保留でもない状態（UNSPECIFIED_STATE）。2026-10-03〜。 */
        const val UNSPECIFIED_STATE = "unspecified_state"

        /** こちらの処理が例外で止まった（Play の応答コードは無い）。2026-10-03〜。 */
        const val EXCEPTION = "exception"

        /** 接続の返事が時間内に来なかった（Play の応答コードは無い）。2026-10-03〜。 */
        const val TIMEOUT = "timeout"

        const val BILLING_UNAVAILABLE = "billing_unavailable"
        const val ITEM_UNAVAILABLE = "item_unavailable"
        const val SERVICE_UNAVAILABLE = "service_unavailable"
        const val SERVICE_DISCONNECTED = "service_disconnected"
        const val NETWORK_ERROR = "network_error"
        const val DEVELOPER_ERROR = "developer_error"
        const val FEATURE_NOT_SUPPORTED = "feature_not_supported"
        const val ITEM_ALREADY_OWNED = "item_already_owned"
        const val ITEM_NOT_OWNED = "item_not_owned"

        /** Play が返した一般のエラー。 */
        const val ERROR = "error"

        /** こちらが知らない応答コード。 */
        const val UNKNOWN = "unknown"
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

        /** 失敗の種類。値は [ErrorReason] に列挙したものだけ。生の例外文は入れない。 */
        const val REASON = "reason"

        /** 課金のどの段階か。値は [Stage]（[Event.PRO_BILLING_RESULT] 専用）。 */
        const val STAGE = "stage"

        /** 課金の診断の分類。値は [BillingOutcome]（[Event.PRO_BILLING_RESULT] 専用・2026-10-03〜）。 */
        const val CATEGORY = "category"

        /** 購入が失敗した段階。値は [ErrorStage]（[Event.PRO_PURCHASE_ERROR] 専用）。 */
        const val ERROR_STAGE = "error_stage"

        /**
         * Play の応答コード（`BillingClient.BillingResponseCode` の整数）。
         * [Event.PRO_PURCHASE_ERROR] と [Event.PRO_BILLING_RESULT]（2026-10-03〜）で使う。
         * Play が決めた固定の番号で、利用者や購入を特定する情報は含まない。
         * 例外などでコードが無いときは**入れない**（推測の値を入れない）。
         * ⚠️ Play の `debugMessage`・購入トークン・注文IDは引き続き送らない。
         */
        const val BILLING_RESPONSE_CODE = "billing_response_code"
    }

    /** [Event.PRO_CANCEL_REASON] の答え（[Param.REASON]）。 */
    object CancelReason {
        /** 使える支払い方法が無い。 */
        const val NO_PAYMENT_METHOD = "no_payment_method"

        /** 価格が高い。 */
        const val PRICE_TOO_HIGH = "price_too_high"

        /** あとで買う。 */
        const val LATER = "later"

        /** その他。 */
        const val OTHER = "other"

        /** 答えずに閉じた（回答率を出すために残す）。 */
        const val DISMISSED = "dismissed"

        val ALL = setOf(NO_PAYMENT_METHOD, PRICE_TOO_HIGH, LATER, OTHER, DISMISSED)
    }

    /** [Event.PRO_PURCHASE_ERROR] の段階（[Param.ERROR_STAGE]）。 */
    object ErrorStage {
        /** Play への接続（購入ボタンを押したときに繋がらなかった）。 */
        const val BILLING_CONNECT = "billing_connect"

        /** 商品情報（価格・オファー）の取得。 */
        const val PRODUCT_QUERY = "product_query"

        /** 購入画面を開く（`launchBillingFlow`）。 */
        const val LAUNCH_BILLING = "launch_billing"

        /** 購入画面のあとに届いた結果（`PurchasesUpdatedListener`）。 */
        const val PURCHASE_UPDATE = "purchase_update"
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

        /**
         * すでに所有している（ITEM_ALREADY_OWNED）。2026-10-03〜。
         * この場での購入ではないので売上でもキャンセルでもないが、「購入できなかった」終わり方として数える
         * （以前はどのイベントも出ず、購入開始だけが残って原因が見えなかった）。
         */
        const val ITEM_ALREADY_OWNED = "item_already_owned"

        /**
         * 応答は OK なのに、購入済みも保留も届かなかった（一覧が null／空／pro_unlock 無し／状態不明）。2026-10-03〜。
         * 細かい形は `pro_billing_result` の category で見る。
         */
        const val OK_WITHOUT_PURCHASE = "ok_without_purchase"

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

        /** 最初の案内に並べた人気の動画から選んで開いた。 */
        const val POPULAR = "popular"

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
