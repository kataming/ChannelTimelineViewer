# Pro 購入の計測（Android 版）

「Pro が**何人に売れたか**」を Firebase / GA4 で確かめるための決まりごと。
2026-09-13 に、購入の**開始**と**成立**を別のイベントに分けた（1.9 から有効）。

対象は Android 版のみ。iOS 版に解析 SDK は入れていない。
仕組み全体の前提は [`../android-firebase-analytics.md`](../android-firebase-analytics.md)、
課金の実装は [`../android-iap-pro.md`](../android-iap-pro.md)。

---

## 1. なぜ分けたか

1.8 までは `pro_purchase_start`（購入ボタンを押した）しか実質使えず、
**実際に売れた数が分からなかった**。`pro_purchase_end` という定数はあったが、
保留（PENDING）でも同じ名前で送っていたうえ重複防止が無く、実売の数としては使えなかった
（なお 1.8 の時点で購入が1件も無かったため、この名前のデータは存在しない。
1.9 で `pro_purchase_end` は**廃止**し、下の5つに置き換えた）。

---

## 2. イベント一覧

| イベント | いつ出るか | 引数 | 実売に数える |
| --- | --- | --- | --- |
| `pro_purchase_start` | 購入ボタンを押して、購入フローを開こうとした | なし | ❌ |
| **`pro_purchase_success`** | **購入が本当に成立した**（下の条件をすべて満たす） | なし | ✅ **これが実売** |
| `pro_purchase_cancel` | 本人が購入画面をやめた（`USER_CANCELED`） | なし | ❌ |
| `pro_purchase_error` | 購入が失敗した | `reason` | ❌ |
| `pro_purchase_pending` | 保留になった（コンビニ払いなど） | なし | ❌ まだ売れていない |
| `pro_restore` | 「購入を復元」を押した | なし | ❌ 既存客の再適用 |
| `purchase` | `pro_purchase_success` と同時（値段が取れたときだけ） | `value` / `currency` | ✅ GA4 の収益レポート用 |
| `pro_billing_result` | **診断用**。課金の各段階の結果（成功も失敗も） | `stage` / `result` | ❌ 数えない |
| `in_app_purchase` | **Firebase が自動収集**（コードからは送れない・[第9章](#9-in_app_purchasefirebase-の自動収集イベント)） | Google が決める | ✅ Play 側との突き合わせ用 |

### `pro_purchase_success` の発火条件（すべて満たしたときだけ）

1. `PurchasesUpdatedListener`（＝アプリ内で購入した瞬間）の通知である
2. 応答コードが `OK`
3. その購入に対象商品 **`pro_unlock`** が含まれている
4. 購入状態が **`PURCHASED`**（`PENDING` でも `UNSPECIFIED` でもない）
5. **Pro 権限の付与が確定している**（`ProEntitlementStore.grant()` を実行した）
6. **その購入をまだ実売として数えていない**（重複防止）

### 絶対に出さない場面

- `PENDING`（保留）
- `USER_CANCELED`（本人がやめた）
- Billing のエラー全般
- 「購入を復元」
- アプリ起動時の既購入検出（`queryPurchasesAsync`）
- `ITEM_ALREADY_OWNED`（すでに持っている＝この場の購入ではない）
- 同じ購入の2回目以降の通知
- 権限付与が確定していない状態

### `reason` に入る値（これ以外は入らない）

`service_unavailable` / `billing_unavailable` / `item_unavailable` /
`developer_error` / `generic_error`

Play が返す応答コードの数値や `debugMessage` は**送らない**（ログには出す）。

---

### `pro_billing_result`（診断用・2026-09-21 追加）

Play Console の購入者コンバージョンで「購入画面は出ているのに誰も買っていない」と分かったとき、
**どこで止まっているか**を切り分けるために足した。**売上の数には一切関わらない**
（実売はこれまでどおり `pro_purchase_success` だけ）。

`stage`（どの段階か）:

| 値 | 意味 |
| --- | --- |
| `connect` | Play への接続 |
| `query_product` | 商品情報（価格・オファー）の取得 |
| `launch` | 購入画面を開く指示（`launchBillingFlow` の戻り値） |
| `purchase_callback` | 購入画面のあとに届く結果（`PurchasesUpdatedListener`） |
| `acknowledge` | 購入の確認 |

`result`（何が起きたか）: `ok` / `user_canceled` / `pending` / `empty_purchase_list` /
`billing_unavailable` / `item_unavailable` / `service_unavailable` / `service_disconnected` /
`network_error` / `developer_error` / `feature_not_supported` / `item_already_owned` /
`item_not_owned` / `error` / `unknown`

これで**今まで見えなかった3つ**が見えるようになる。

- `purchase_callback` + `empty_purchase_list` … 応答は成功なのに購入が1件も入っていない
- `purchase_callback` + `item_already_owned` … すでに持っている人が買おうとした
- `launch` の失敗 … 購入画面を**開く前**に落ちた（`pro_purchase_error` だけでは
  「開く前」か「開いたあと」かを見分けられなかった）

⚠️ 送るのは `stage` と `result` の決まった文字だけ。応答コードの数値・`debugMessage`・
購入トークン・注文IDは**入れない**（第5章のとおり）。

## 3. PURCHASED / PENDING / CANCEL / ERROR / RESTORE の違い

| 状態 | 意味 | お金 | 送るイベント |
| --- | --- | --- | --- |
| **PURCHASED** | 支払いが完了し、商品が付与された | **入る** | `pro_purchase_success` |
| **PENDING** | 支払い待ち（コンビニ払い・保護者承認など） | まだ入らない | `pro_purchase_pending` |
| **USER_CANCELED** | 購入画面を閉じた | 入らない | `pro_purchase_cancel` |
| **ERROR 系** | 通信不良・商品未公開・設定誤りなど | 入らない | `pro_purchase_error` |
| **RESTORE** | 前に買った人が別端末などで権限を戻した | 新たには入らない | `pro_restore` |

**実売として数えてよいのは `pro_purchase_success` だけ。**
売上金額を見たいときは GA4 標準の `purchase` を使う。

---

## 4. 重複防止

同じ購入で `pro_purchase_success` が複数回出ると**売上が水増し**される。
Play は同じ購入を何度も通知してくるので、次の経路すべてに対策している。

| 経路 | 対策 |
| --- | --- |
| `PurchasesUpdatedListener` の再通知 | 購入トークンごとに1回だけ |
| `queryPurchasesAsync`（起動時・復元） | そもそも success を送らない。加えて「見た」印を付ける |
| アプリ再起動 | 印は `SharedPreferences` に残る |
| acknowledge の前後 | acknowledge とは無関係に、トークン単位で判定 |
| Billing の再接続 | 同上 |

仕組み: `ReportedPurchaseStore` が購入トークンの **SHA-256** を端末内に控える。
`reportOnce(token)` は「まだなら控えて true / すでにあれば false」を返すので、
呼ぶ側は戻り値を見るだけでよい。

> ⚠️ **purchaseToken そのものは保存しない**（ハッシュのみ）。
> ハッシュ化したものも含め、**Analytics へは一切送らない**。照合は端末の中だけ。

### 数え落ちる場合（承知のうえ）

保留（PENDING）の支払いが**アプリを閉じている間に**成立した場合、次の起動時に
`queryPurchasesAsync` で見つかるが、これは「起動時の既購入検出」なので実売としては数えない。
水増しより数え落としを選んでいる。コンビニ払いが増えるようなら、
[第10章の RTDN](#10-将来の強化案サーバー側での購入検証) で正確に取る。

---

## 5. Analytics へ送ってはいけないもの

- `purchaseToken`（ハッシュ化したものも含む）
- `orderId`
- メールアドレス / Google アカウント情報 / ユーザーID
- Play が返す生の `debugMessage` や例外の内容
- 応答コードの数値
- チャンネルID・チャンネル名・動画ID・動画タイトル・メモ・入力URL

`ProPurchaseAnalyticsTest` がこれらを機械的に検査している。

---

## 6. Analytics は fail-open

記録の失敗で、購入・Pro 権限付与・復元・起動・保存・再生が壊れてはいけない。

- `ProBillingManager.onPurchasesUpdated` は、**先に権限とメッセージを確定**させ、記録はそのあと
- `ProPurchaseReporter` の外向きの関数はすべて `runCatching` で包んである
- `FirebaseAnalyticsTracker` も `logEvent` / `setAnalyticsCollectionEnabled` を包んである

`記録が失敗しても Pro 権限は付与される` というテストで守っている。

---

## 7. Firebase での確認方法

### すぐ見る（DebugView）

```
adb shell setprop debug.firebase.analytics.app com.deskflowlabs.channeltimelineviewer
adb shell setprop debug.firebase.analytics.app .none.   # 解除
```

Firebase コンソール → Analytics → **DebugView**。
購入テストは Play Console の**ライセンステスター**に登録したアカウントで行う
（実際の課金なしで購入フローを最後まで通せる）。

見る順番:

1. 購入ボタン → `pro_purchase_start`
2. 購入完了 → **`pro_purchase_success` が1回だけ**、続けて `purchase`
3. アプリを再起動 → `pro_purchase_success` が**増えないこと**（ここが重要）
4. 「購入を復元」→ `pro_restore` だけ。success は増えない

### 実売人数を見る（通常レポート）

Firebase コンソール → Analytics → **イベント** に `pro_purchase_success` が出る。
「ユーザー数」の列が**買った人数**、「イベント数」が購入回数（返金→再購入があると差が出る）。

反映は最大24時間。それより早く見たいときは DebugView。

### 収益で見る

GA4 の **収益化 → 収益化の概要**。`purchase` イベントの `value` / `currency` から
売上が積み上がる。金額は Play が返した商品情報からのみ取っており、コードに価格は持っていない。

> `transaction_id` は送っていない（`orderId` は送信禁止のため）。
> GA4 側の重複排除は効かないが、アプリ側でトークン単位の重複防止をしているので問題ない。

---

## 8. 国別に見る（Nigeria / South Africa / Japan の比較）

### 8-1. GA4 の探索レポートで作る

GA4（Firebase コンソール → Analytics →「Google アナリティクスで表示」）→ **探索** → 空白。

| 設定 | 値 |
| --- | --- |
| ディメンション | **国**（Country） |
| 指標 | **アクティブ ユーザー数**、**イベント数** |
| 行 | 国 |
| 値 | イベント数 |
| フィルタ | イベント名 = `pro_purchase_success` |

これで国別の購入人数が並ぶ。Nigeria / South Africa / Japan だけを見たいときは、
フィルタに「国 が次のいずれかに完全一致: Nigeria, South Africa, Japan」を足す。

### 8-2. 有料転換率の出し方

転換率は **購入した人 ÷ 見に来た人**。同じ探索で指標を2本並べる。

| 見たいもの | 作り方 |
| --- | --- |
| 分母 | イベント名 = `screen_view` かつ `screen_name` = `pro` の **ユーザー数**（Pro 画面まで来た人） |
| 分子 | イベント名 = `pro_purchase_success` の **ユーザー数** |
| 転換率 | 分子 ÷ 分母 |

より手前から見たいなら、分母を `first_open` のユーザー数（インストールした人）にする。
両方を国別に並べると、「アフリカ圏は入口まで来るが買わない」のような差が読める。

### 8-3. ファネルで見る（脱落地点が分かる）

**探索 → 目標到達プロセスデータ探索**（ファネル）。ステップをこの順に置く:

1. `first_open`
2. `screen_view`（`screen_name` = `pro`）
3. `pro_purchase_start`
4. `pro_purchase_success`

「内訳」に **国** を入れると、Nigeria / South Africa / Japan が並んで比較できる。

- **3 → 4 の脱落が大きい国**は、決済手段が無い・カードが通らない可能性が高い。
  `pro_purchase_error` の `reason` 別内訳と、`pro_purchase_cancel` の比率を併せて見る
- **2 → 3 の脱落が大きい国**は、値段が高すぎる可能性。Play Console の国別価格を見直す材料になる

> 通貨が違うので、**金額の合計で国を比べない**こと（`purchase` の `value` は現地通貨）。
> 人数と転換率で比べ、金額は GA4 が換算する「収益」列を使う。

---

## 9. `in_app_purchase`（Firebase の自動収集イベント）

2026-09-15 に「`in_app_purchase` も取りたい」という要望が出たので、調べた結果をここに残す。

### 結論: **コードでは送れない。設定で取る。**

`in_app_purchase` は Firebase が**自動で集めるイベント**で、アプリから `logEvent` で送るものではない。

| 項目 | 状況 |
| --- | --- |
| 予約語か | **はい。** 予約されたイベント名を `logEvent` に渡すと拒否される |
| 手動送信できるか | **本アプリでは不可。** 手動送信は Analytics SDK **23.2.0+**（Firebase BoM 34.10.0+）が要る |
| 本アプリの SDK 版 | **22.1.2**（BoM 33.7.0 由来）＝**条件を満たさない** |
| 自動収集の SDK 条件 | 17.3.0+ → **満たしている** |
| 自動収集の設定条件 | **Firebase アプリを Google Play にリンクする**（Firebase コンソールの操作） |

### なぜ SDK を上げて手動送信しないのか

2つ理由がある。

1. **必要ない。** 手動送信は「Play ストア以外での購入」用。本アプリの購入はすべて Play Billing 経由なので、
   リンクさえすれば自動で記録される
2. **上げられない。** BoM 34.10.0 へ上げるには先に Kotlin を上げる必要がある
   （33.8.0 以降が Kotlin 2.1 メタデータの `play-services-measurement` を連れてくる。
   本プロジェクトは Kotlin 2.0.21。詳細は [`../android-firebase-analytics.md`](../android-firebase-analytics.md) 第6章）。
   Kotlin を上げるなら Compose コンパイラも一緒に動くので、**単独の作業**にすること

### 取るための手順（Firebase コンソール・人の操作）

1. Firebase コンソール → プロジェクト `channel-timeline` → **プロジェクトの設定** → **統合**タブ
2. **Google Play** の「リンク」を押す
3. 同じ Google アカウントで Play Console のデベロッパーアカウントを選び、
   `com.deskflowlabs.channeltimelineviewer` を結びつける

リンク後、**新しく発生した購入から** `in_app_purchase` が自動で記録される。
過去にさかのぼっては入らない。

### 送られる引数（こちらでは選べない）

`product_id` / `price` / `value` / `currency` / `quantity` /
`subscription` / `free_trial` / `introductory_price`

`product_id` は `pro_unlock` という商品IDで、個人を特定するものではない。
⚠️ ただし**引数の内容は Google が決める**ので、こちらの「送ってよいものだけ送る」方針の外にある。
仕様が変わっていないか、たまに DebugView で中身を見ること。

### 3つのイベントの使い分け

リンク後は購入1件につき3つ記録される。**同じものを3回数えないよう**、用途を分ける。

| イベント | 出どころ | 使いどころ |
| --- | --- | --- |
| **`pro_purchase_success`** | アプリ（こちらの実装） | **実売人数の正**。重複防止つき。これを基準にする |
| `purchase` | アプリ（こちらの実装） | GA4 の収益レポート（収益化の概要） |
| `in_app_purchase` | Firebase の自動収集 | GA4 の「アプリ内購入」レポート。Play 側の数字との突き合わせ |

数が食い違ったときの読み方:

- `in_app_purchase` > `pro_purchase_success` … アプリを閉じている間に成立した購入
  （保留の解消など）。第4章の「数え落ち」がこれで見える
- `pro_purchase_success` > `in_app_purchase` … リンクが効いていないか、Play 側の反映待ち
- 金額が合わない … Play の手数料・税・返金の扱いが違う。**売上の正は Play Console**

### ⚠️ データセーフティの申告を見直すこと

購入イベント（`pro_purchase_success` / `purchase` / `in_app_purchase`）は、
Play の「データセーフティ」の分類では **「金融情報 → 購入履歴」** に当たる可能性が高い。

現在の申告は「アプリのアクティビティ」と「デバイスまたはその他のID」だけなので、
**申告の追加が必要かを確認すること**。これは 1.9 で `purchase` を出し始めた時点で
すでに当てはまっている論点で、`in_app_purchase` を足すかどうかとは別に確認が要る。

判断に迷うなら Play Console のデータセーフティのヘルプを見るか、
「購入履歴」を収集すると申告しておく方が安全（申告漏れの方が重い）。

---

## 10. 将来の強化案（サーバー側での購入検証）

**今回は実装していない。外部設定も行っていない。** 必要になったときの選択肢として残す。

### Real-time Developer Notifications（RTDN）

Play Console → 収益化のセットアップ → RTDN で Pub/Sub トピックを指定すると、
購入・返金・保留の解消などが**サーバーへ push** される。

利点:

- **アプリを開いていなくても**購入の成立が分かる（第4章の「数え落ち」が無くなる）
- **返金・チャージバック**を検知でき、実売から差し引ける
- 端末側の細工に影響されない正確な数字が得られる

必要なもの: GCP の Pub/Sub トピックとサブスクリプション、受け口のサーバー（Cloud Run 等）、
サービスアカウント。**このアプリはサーバーを持たない方針**なので、導入するなら
「アカウント不要・端末内だけ」という説明との整合を先に検討すること。

### Google Play Developer API での購入検証

`purchases.products.get` で購入トークンを検証し、`purchaseState` と `acknowledgementState` を
サーバー側で確かめる方式。RTDN と組み合わせるのが定石。

導入する場合も、**購入トークンを Analytics へ送らない**という原則は変えない。

---

## 11. 関連ファイル

| ファイル | 役割 |
| --- | --- |
| `analytics/Analytics.kt` | イベント名・引数名・`ErrorReason` の定義 |
| `billing/ProPurchaseReporter.kt` | **何を実売として数えるかの判断はここだけ** |
| `billing/ReportedPurchaseStore.kt` | 重複防止（トークンの SHA-256 を端末に控える） |
| `billing/ProBillingManager.kt` | Play とのやり取り。数え方の分岐は持たない |
| `AppContainer.kt` | 上記の配線 |
| `app/src/test/.../ProPurchaseAnalyticsTest.kt` | 上の約束を機械的に検査する |
