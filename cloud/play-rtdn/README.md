# Play RTDN 受信（診断用・最小）

Google Play の RTDN（リアルタイム デベロッパー通知）を受け取り、**ログに1行残すだけ**の関数。

**目的**: Firebase Analytics の `in_app_purchase` が 0 のままなので、Analytics とは別の経路で
「Play 側で `pro_unlock` の購入成功が実際に起きているか」を確かめる。
アプリの挙動・Pro の付与・売上の数え方には**一切関わらない**（読んで記録するだけ）。

> 状態（2026-09-19）: **ローカル実装とテストまで。まだデプロイしていない。**

### 未完了・残作業（2026-09-19 時点）

| 項目 | 状態 | 誰が・いつ |
| --- | --- | --- |
| ローカル実装・テスト12件 | 完了 | — |
| コミット | ローカルのみ（`66a3670`）。**未 push** | push の指示があれば Claude |
| Google Cloud へのデプロイ（下の手順 1〜4） | **未実施** | デプロイの指示があれば Claude（gcloud の認証が要る） |
| テスト通知での動作確認（手順 5） | **未実施**（デプロイ後） | Claude（Play Console の「テスト通知を送信」だけ人） |
| 既存の pull サブスクリプション `ctv-play-billing-rtdn-sub` の扱い | **未決定** | 人の判断 |
| 購入が起きているかのログ確認（手順 6） | **未実施**（実購入が起きてから） | Claude |
| Developer API による purchaseToken 検証・重複排除 | **未実装**（次フェーズ） | 指示があれば |
| CI でこのテストを自動実行 | **未設定**（手動で `python cloud/play-rtdn/tests/test_rtdn.py -v`） | 必要なら追加 |
| 実際の Cloud Functions ランタイム（functions-framework 本物）での起動確認 | **未確認**（テストは入口を差し替えて実施） | デプロイ時に確認 |

## 構成

| ファイル | 役割 |
| --- | --- |
| `rtdn.py` | 本体。Base64 → JSON → 判定 → 構造化ログ1行。標準ライブラリだけ |
| `main.py` | Cloud Run functions の入口（`on_play_rtdn`）。`rtdn.handle_message` に渡すだけ |
| `requirements.txt` | `functions-framework` のみ |
| `tests/test_rtdn.py` | テスト（外部依存なし） |

```
python cloud/play-rtdn/tests/test_rtdn.py -v
```

## 何をログに出すか

1通知につき1行の JSON を標準出力へ出す（Cloud Logging が `jsonPayload` として読む）。
`message` は固定ラベル。

| message | severity | 出す項目 |
| --- | --- | --- |
| `RTDN_TEST_RECEIVED` | INFO | なし（固定ログだけ） |
| `ONE_TIME_PRODUCT_PURCHASED` | INFO | packageName / eventTimeMillis / sku / isProUnlock / notificationType(=1) |
| `ONE_TIME_PRODUCT_CANCELED` | INFO | 同上（notificationType=2） |
| `RTDN_UNKNOWN_ONE_TIME_TYPE` | WARNING | 同上（未知の notificationType） |
| `RTDN_UNHANDLED_KIND` | INFO | packageName / eventTimeMillis / kind（subscription / voided） |
| `RTDN_UNKNOWN_KIND` | WARNING | packageName / eventTimeMillis |
| `RTDN_WRONG_PACKAGE` | WARNING | packageName（形が崩れていれば null）。**以降は処理しない** |
| `RTDN_DECODE_ERROR` / `RTDN_MALFORMED_JSON` / `RTDN_HANDLER_ERROR` | ERROR | errorType（例外の**種類名だけ**） |

⚠️ 次は**絶対に出さない**（テストで確認している）:
- `purchaseToken`（購入の鍵そのもの。キー名すら出さない）
- Pub/Sub の生メッセージ・RTDN の JSON 全文
- 例外の文面（受け取った中身の断片が混ざりうるため）

受け取った packageName / sku / eventTimeMillis は、決まった文字種・長さに合うときだけ出す。

### 重複について

Play も Pub/Sub も「少なくとも1回」配信なので、**同じ通知が2回以上ログに出ることがある**。
いまは診断用なので重複排除はしていない。件数を数えるときは、同じ `eventTimeMillis` の行を
1件とみなすこと（厳密にはトークン単位の重複排除が要る → 次フェーズ）。

### 例外を投げない理由

関数が失敗すると Pub/Sub が同じ通知を再送し続ける。壊れた通知は何度来ても壊れているので、
「読めなかった」とログに残して受け取り済みにする。

## デプロイ手順（将来。まだ実行しない）

前提: プロジェクト `channel-timeline`、トピック `ctv-play-billing-rtdn`（作成済み・Play からのテスト通知の受信を確認済み）。

1. API を有効にする（未有効のものだけ）
   ```
   gcloud services enable cloudfunctions.googleapis.com run.googleapis.com \
     cloudbuild.googleapis.com eventarc.googleapis.com artifactregistry.googleapis.com \
     --project=channel-timeline
   ```
2. 関数専用のサービスアカウントを作る（**ロールは付けない**。ログを標準出力に書くだけなので不要）
   ```
   gcloud iam service-accounts create ctv-play-rtdn --project=channel-timeline \
     --display-name="Play RTDN receiver (diagnostic)"
   ```
3. Eventarc が関数を呼べるようにする（トリガー用のサービスアカウントに Cloud Run の起動権限）
   ```
   gcloud projects add-iam-policy-binding channel-timeline \
     --member="serviceAccount:ctv-play-rtdn@channel-timeline.iam.gserviceaccount.com" \
     --role="roles/run.invoker"
   ```
   2021-04-08 より前に Pub/Sub を使い始めたプロジェクトでは、Pub/Sub のサービス エージェントに
   `roles/iam.serviceAccountTokenCreator` も要る（新しいプロジェクトでは不要）。
4. デプロイ（リポジトリのルートで実行）
   ```
   gcloud functions deploy ctv-play-rtdn --gen2 --project=channel-timeline \
     --region=asia-northeast1 --runtime=python312 \
     --source=cloud/play-rtdn --entry-point=on_play_rtdn \
     --trigger-topic=ctv-play-billing-rtdn \
     --service-account=ctv-play-rtdn@channel-timeline.iam.gserviceaccount.com \
     --trigger-service-account=ctv-play-rtdn@channel-timeline.iam.gserviceaccount.com \
     --no-allow-unauthenticated --max-instances=1 --memory=256Mi
   ```
   - `--trigger-topic` を指定すると、Eventarc が**このトピックに専用の push サブスクリプションを自動で作る**。
     既存の `ctv-play-billing-rtdn-sub`（手で pull して確認する用）とは別物で、そちらはそのまま残る。
     ただし既存の方は誰も pull しないとメッセージが溜まり続けて7日で消えるだけなので、
     関数が動いたら削除してよい（削除は人の判断で）。
   - `--retry` は付けない（関数は例外を投げない設計なので不要）。
5. 動作確認: Play Console →「収益化のセットアップ」→「テスト通知を送信」。
   ```
   gcloud logging read 'resource.type="cloud_run_revision" AND resource.labels.service_name="ctv-play-rtdn" AND jsonPayload.message="RTDN_TEST_RECEIVED"' \
     --project=channel-timeline --limit=5 --freshness=1h
   ```
6. 購入が起きているかの確認
   ```
   gcloud logging read 'resource.labels.service_name="ctv-play-rtdn" AND jsonPayload.message="ONE_TIME_PRODUCT_PURCHASED" AND jsonPayload.isProUnlock=true' \
     --project=channel-timeline --freshness=30d --format='value(timestamp,jsonPayload.eventTimeMillis)'
   ```
   Cloud Logging の既定の保持期間は30日。

費用の目安: RTDN は購入1件につき数通なので、Cloud Run functions の無料枠に収まる。

## 次フェーズ: Developer API での購入検証（未実装）

RTDN は「通知が来た」ことしか分からない（通知自体は偽装できないが、中身の状態は通知時点のもの）。
購入の実態を確かめるには、受け取った `purchaseToken` で Play Developer API に問い合わせる:

1. `purchases.products.get`（または `purchases.productsv2.getproductpurchasev2`）を
   `packageName` / `productId=pro_unlock` / `token` で呼ぶ
2. 見る項目: `purchaseState`（0=購入済み）・`acknowledgementState`（1=確認済み）・
   `purchaseType`（0=テスト購入。**テスト購入を実売と区別**できる）・`regionCode`
3. ログに足してよいのは上の状態値と国コードだけ。**トークンと orderId は引き続き出さない**
4. 重複排除: トークンの SHA-256 を Firestore などに控え、同じ購入を1回だけ数える
   （Android アプリ側の `ReportedPurchaseStore` と同じ考え方）
5. 権限: 関数のサービスアカウントを Play Console に招待し、このアプリの
   「売上データ、注文、解約アンケートの回答の閲覧」だけを付ける（払い戻しができる
   「注文と定期購入の管理」は付けない）。鍵ファイルは作らず、関数の実行 ID で呼ぶ
6. Developer API が一時的に失敗したときだけ例外を投げて Pub/Sub に再送させる
   （このときは `--retry` を付け、再送の上限をデッドレター トピックで区切る）
