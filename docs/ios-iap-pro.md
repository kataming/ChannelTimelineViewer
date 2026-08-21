# iOS 版の課金（Pro 買い切り）— 実装と App Store Connect 設定

Channel Timeline Viewer iPhone 版の収益化は **アプリ本体は無料＋Pro の買い切り（非消費型 App 内課金）** とする。
サブスクリプションは使わない。アフィリエイト・紹介報酬・成果報酬の仕組みも入れない。

- 無料: **保存チャンネル1件**。その1件の中では主要機能を**一切制限しない**
- Pro: **複数チャンネル保存**と、チャンネルごとの視聴済み・進捗・メモの保持

「視聴者さんが貴チャンネルを無料で保存できる」と YouTuber に説明できることが、この設計の中心価値。
Android 版（[`android-iap-pro.md`](android-iap-pro.md)）と挙動を揃えてある。

---

## 1. 無料でできること / Pro で解放されること

| 機能 | 無料 | Pro |
| --- | --- | --- |
| チャンネル保存 | **1件** | 複数 |
| 古い順 / 新しい順の並べ替え | ○ | ○ |
| 視聴済み管理 | ○ | ○ |
| 続きから再生 | ○ | ○ |
| 移動ボタン | ○ | ○ |
| メモ | ○ | ○ |
| 進捗表示 | ○ | ○ |
| 公式埋め込みプレイヤーでの再生 | ○ | ○ |
| 複数チャンネルの視聴済み・進捗・メモの保持 | — | ○ |
| チャンネル一覧の管理 | — | ○ |
| 今後追加する上位の管理機能 | — | ○ |

制限するのは **同時に保存できるチャンネル数だけ**。視聴体験そのものは削らない。

## 2. アプリ側の実装

| 役割 | ファイル |
| --- | --- |
| 保存件数とロックの判定（純ロジック・テスト対象） | `Services/ChannelSlotPolicy.swift` |
| Pro 所有状態（StoreKit 2） | `Services/ProEntitlementStore.swift` |
| チャンネル単位の記録削除 | `Services/ChannelDataRemover.swift` |
| 無料時に使う1チャンネルの記憶 | `Services/ActiveChannelStore.swift` |
| 購入画面 | `Views/ProView.swift` |
| 確認シート（入れ替え・削除・ロック・無料枠の選択） | `Views/ChannelLimitSheets.swift` |
| 画面の組み立て | `Views/ChannelInputView.swift` / `Views/FavoriteChannelsView.swift` |
| 判定の呼び出し | `ViewModels/ChannelInputViewModel.swift` |
| テスト | `Tests/ProEntitlementTests.swift` |

決めごと:

- **StoreKit 2**（`Product` / `Transaction`）。商品は `pro_unlock` の1つだけ、**非消費型**。
- **ローカルのフラグだけを信用しない。** 正は常に `Transaction.currentEntitlements`。
  端末内（`pro_unlocked_v1`）に持つのは前回の写しで、起動直後の一瞬だけ使う。
- **返金・購入取消（revoked）に追随する。** `currentEntitlements` から消える／`revocationDate` が入る
  ので、そのとき Pro を落とす。`Transaction.updates` も購読しているため、アプリを開いたままでも反映される。
- 確認するのは **起動時・前面復帰時（`scenePhase == .active`）・購入画面表示時**の3か所。
- **価格はコードに持たない**。`product.displayPrice` をそのまま表示するので、
  App Store Connect 側で $4.99 → $9.99 に変えてもアプリの更新は要らない。
- 購入失敗・キャンセル・保留（`.pending`）・検証失敗・復元失敗のどれでも落とさない。メッセージを返すだけ。
  キャンセルは何も表示しない。

### 2件目を保存しようとしたとき（無料）

1. 上限に当たると**開かずに**確認シートを出す
2. 消えることを **大きめ・太字・赤** で表示する（小さな注意書きにしない）
3. ボタンは上から **「Proの内容を見る」（塗りボタン）→「入れ替える」（赤い枠線）→「キャンセル」**
4. 「入れ替える」を選ぶと、外すチャンネルの
   **視聴済み・スキップ・進捗・メモ・再生位置・一覧キャッシュを削除する**（元に戻せない）
5. Pro を買えば、入れ替えずに両方を保存したまま使える

### 削除（無料・Pro 共通）

削除も**記録ごと消える**。同じ警告を出す（無料の場合は「Proの内容を見る」も並べる）。
「削除しても視聴済みの記録は残る」「開き直せば進捗が戻る」という**旧仕様の文言と挙動は撤廃した**。
削除して枠を空ければ履歴を持ったまま乗り換えられてしまうため。

### Pro が外れたとき（返金・取消・失効）

**保存済みチャンネルは削除しない。上限を超える分をロックする。**

- 一覧には全チャンネルが残り、ロック中の行には 🔒 と「ロック中」が付く
- ロック中を開こうとすると、Pro の案内と「このチャンネルを無料で使う」を出す
- ホームに「Proが無効になりました」の案内と **「無料で使う1チャンネルを選ぶ」** を出す
- **視聴済み・進捗・メモ・再生位置は消さない**。Pro を買い直す／復元すればすべて元通り
- ロック中のチャンネルを削除することはできる（そのときは記録も消える旨を警告する）

> **入れ替え・削除（記録を消す）** と **ロック（記録を残す）** は別物。混同しないこと。
> 判定は `ChannelSlotPolicy.usableChannelIds()` / `isLocked()`。

---

## 3. App Store Connect で人が行う設定

### 3-1. App 内課金アイテム（**登録済み・API で行う**）

`python scripts/asc_iap.py --mode create` で作成・更新できる。**画面での手入力は不要**。
GitHub → Actions → **App Store IAP** からも実行できる（`mode=create`, `dry_run=false`）。

| 項目 | 値 |
| --- | --- |
| 製品ID | `pro_unlock`（**変更不可**。アプリのコードと一致） |
| タイプ | **非消費型（NON_CONSUMABLE）** ＝買い切り |
| 参照名 | `Channel Timeline Viewer Pro` |
| 表示名・説明 | 7言語（ja / en-US / zh-Hans / es-ES / de-DE / fr-FR / ko）登録済み |
| 価格 | **$4.99（USA 基準）**。他国は Apple の対応表で自動 |
| 配信地域 | **175 の国と地域**＋今後増える国も自動で対象 |
| ファミリー共有 | しない |
| 審査メモ | 買い切り・サブスクではない旨を英語で登録済み |

値上げ（$9.99 など）は `BASE_PRICE` を書き換えて再実行すればよい。**アプリの更新は不要**
（価格はコードに持っていないため）。ただし既に価格が付いている場合は上書きしない作りなので、
値上げのときは意図して価格スケジュールを作り直すこと。

> API の癖: 作成は `POST /v2/inAppPurchases`。`availableInAllTerritories` という属性は無く、
> 配信地域は `inAppPurchaseAvailabilities` で別途作る。商品にぶら下がる情報
> （表示名・価格スケジュール・配信地域）は **`/v2/inAppPurchases/{id}/...`** から読む
> （`/v1/...` は関係名が存在しない）。

**状態は `MISSING_METADATA`** のまま残る。審査用スクリーンショットが未添付のため。

### 3-2. アプリ情報の申告

| 項目 | 値 |
| --- | --- |
| App 内課金 | **あり** |
| 価格（本体） | **無料** |
| App のプライバシー | **データを収集していません**（購入処理は Apple が行い、当方のサーバーは介在しない） |

### 3-3. オファーコード（YouTuber 向け）

**App Store Connect → App 内課金 → `pro_unlock` → オファーコード**

- YouTuber 本人へ Pro を無償提供したいときに使う
- **アプリ内にコード発行・引き換え画面は作らない**（App Store Connect の運用として行う）
- 引き換えは App Store の「コードを使う」から行える。発行数には上限がある

### 3-4. 審査メモに書くこと

```
本アプリは無料で利用できます。無料の状態でも、保存した1チャンネル内の全機能
（古い順/新しい順の並べ替え、視聴済み管理、続きから再生、メモ、進捗表示、
公式埋め込みプレイヤーでの再生）が制限なく使えます。

App 内課金は「pro_unlock」1つのみで、非消費型の買い切りです。
サブスクリプションではありません。購入すると複数チャンネルの保存と、
チャンネルごとの視聴済み・進捗・メモの保持が解放されます。
購入画面には「購入を復元」を用意しており、同じ Apple ID で復元できます。

動画の再生は YouTube 公式の IFrame Player を WKWebView で表示する方式のみで、
ダウンロード・独自プレイヤー・広告回避・バックグラウンド再生は実装していません。
```

---

## 4. テスト購入のしかた

### CI で撮る審査用スクリーンショット

`.github/workflows/appstore-iap-screenshot.yml` を実行すると、購入画面を撮って
1242x2688 に整え、`scripts/asc_iap.py --mode screenshot` で課金アイテムに添付するところまで自動で行う。

> **既知の制約**: シミュレーターでは価格が出ず「価格を確認しています…」のまま撮れる。
> StoreKit のテスト設定（`StoreKit/ProStoreKit.storekit`）はスキームに書き出せている
> （XcodeGen が run/test の両方に参照を出す）が、シミュレーターが商品を読み込めていない。
> 参照パスの解決かファイル形式が原因と見ているが未解決。
> 審査に必要なのは「課金がどこで提供されるか分かる画像」なので、この状態で提出できる。

### Xcode（実機・シミュレーター）

1. Xcode で **StoreKit Configuration File** を作り（File → New → File → StoreKit Configuration File）、
   `pro_unlock` を **Non-Consumable** として追加する
2. Scheme → Run → Options → **StoreKit Configuration** にそのファイルを指定
3. 実際の請求なしで購入・復元・返金（Debug → StoreKit → Manage Transactions）が試せる

> このファイルはローカル検証用なのでリポジトリには入れていない。必要になった人が作れば足りる。

### TestFlight

App Store Connect に `pro_unlock` を登録して審査に出すと、TestFlight では **Sandbox 購入**になる。
請求は発生しない。Sandbox アカウントは App Store Connect → ユーザーとアクセス → Sandbox で作る。

確認する項目:

- [ ] 購入前は2件目のチャンネルで確認シートが出る（赤い大きな警告・Proボタンが上）
- [ ] 「入れ替える」で前のチャンネルの視聴済み・進捗・メモが消えている
- [ ] 削除でも同じ警告が出て、記録が消える
- [ ] 購入後は2件以上保存でき、それぞれの進捗が残る
- [ ] アプリを削除して入れ直しても、同じ Apple ID なら「購入を復元」で戻る
- [ ] 機内モードで起動しても Pro が消えない
- [ ] 返金（Manage Transactions で Refund）すると Pro が外れ、超過分がロックされる
- [ ] ロック中のチャンネルの記録は消えていない。再購入で元通り使える

---

## 5. 再提出の手順

1. `Localization/strings.json` を変えたら `python scripts/build_localizations.py` を実行する
2. GitHub Actions **iOS Build** が緑であることを確認する
3. App Store Connect で `pro_unlock` を作る（3-1）
4. 本体価格を **無料** に設定する
5. 新しいビルドをアップロードし、**App 内課金をこのバージョンに紐づけて**審査に提出する
6. 審査メモに 3-4 の文面を貼る

App Store のメタデータ（説明文・スクリーンショット）は `docs/AppStore/` にある。
「アプリ内購入・サブスクリプション・広告はありません」という旧い記述が残っていたら、
Android 版と同じく「広告なし・サブスクなし・Pro は買い切り」に直すこと。
