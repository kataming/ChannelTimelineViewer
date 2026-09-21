# 新興国 50%OFF の実験（2026-09-21 開始）

「購入画面までは出ているのに実売が0件」の原因が**価格**かどうかを確かめるための実験。
判断はユーザー（2026-09-21）。ここに条件・見るもの・期限をまとめておく。

## 条件

| 項目 | 内容 |
| --- | --- |
| オファー ID | `emerging-50off-2026-09` |
| 商品 / 購入オプション | `pro_unlock` / `pro-unlock` |
| 対象国 | BD（バングラデシュ）・IN（インド）・PK（パキスタン）・NG（ナイジェリア）・PH（フィリピン）・VN（ベトナム） |
| 割引 | 50%OFF（`relativeDiscount: 0.5`） |
| 期間 | 2026-09-21 開始 〜 **2026-10-21 終了（自動）** |
| 状態 | ACTIVE |
| 必要なアプリ版 | **Android 1.11 (15) 以降**。それ以前は通常価格のまま |

操作はすべて `scripts/play_offer.py`（`gh workflow run play-metadata.yml -f mode=offer-show|offer-create|offer-activate|offer-deactivate`）。

## 見るもの（2026-10-21 までに）

| 指標 | どこで | 意味 |
| --- | --- | --- |
| `pro_purchase_success` / `purchase` | GA4 | 実売。対象国で出れば割引が効いた |
| `pro_billing_result`（`stage=purchase_callback`） | GA4 | `ok` が増えるか、`user_canceled` のままか |
| 購入者コンバージョン | Play Console | 「ユーザーの意図」が 0% から動くか |

**割引でも `user_canceled` のままなら、原因は価格ではない。** その場合は
「そもそも Pro の価値が伝わっていない」「複数チャンネル保存の需要が無い」側を疑う。

## 期限のある作業

- **2026-10-21 ごろ**: オファーが自動で終わる。延長するなら `offer-create`（時刻を取り直して上書き）→ `offer-activate`。
  途中で止めるなら `offer-deactivate`。
- **2026-10-21 までに**: 上の3指標を見て、価格が原因かどうかを判断する。

## 未了（2026-09-21 時点）

- **GA4 のカスタムディメンション未登録**: `stage` と `result` を登録しないと `pro_billing_result` を
  パラメータ別に分解できない。**登録した時点以降のデータにしか効かない**ので早いほどよい。
  Firebase/GA4 の管理画面での操作（本人ログインが要るため代行できない）。
- **Play RTDN 未デプロイ**（`cloud/play-rtdn/`）: Analytics とは別経路で購入を確かめる手段。
  実装とテストは済んでいて、デプロイだけが残っている。
