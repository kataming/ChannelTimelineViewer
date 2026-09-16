# Watch Queue Sync（Cloudflare Worker + D1）

Watch Queue V2 の同期 API。**稼働中の公式サイト（Cloudflare Pages `channel-timeline-viewer`）とは別のデプロイ**で、
サイトに手を触れずに増減・巻き戻しができる。設計の全体像は
[`../../youtube-watch-queue/docs/WATCH_QUEUE_V2_ARCHITECTURE.md`](../../youtube-watch-queue/docs/WATCH_QUEUE_V2_ARCHITECTURE.md)。

## これは何をするか

| 機能 | 内容 |
|---|---|
| ペアリング | 拡張がコードを表示 → アプリ（iOS / Android / Web）で入力 → 以後は自動同期。QR もカメラ権限も要らない |
| キュー同期 | 編集の正本は Chrome 拡張。`PUT /v2/queues/:id` で丸ごと置き換え、`GET /v2/queues` で取得 |
| 課金判定 | 正本は App Store / Google Play の購入。アプリが `POST /v2/entitlement` で報告し、拡張は `GET` で参照する |
| Feature Flag | `WATCH_QUEUE_V2_ENABLED`。OFF なら `/v2/config` 以外は 503 を返し、全クライアントが pre-V2 の挙動に戻る |

## 保存するもの・しないもの

保存する: queueId / videoId / 再生順（position）/ キュー名 / 画面に出す最小限の文字（タイトル・チャンネル名・再生時間）/
ペアリングの識別子 / 端末の種類と能力 / 日時。

保存しない: Google アカウント情報・パスワード・YouTube の Cookie・閲覧履歴・検索履歴・
キューに入れていない検索結果・**トークンやペアリングコードの平文**（SHA-256 のハッシュのみ。ログにも出さない）。

## セットアップ（初回だけ）

```bash
cd sync
npm install
npx wrangler d1 create watch_queue_sync          # 出力された database_id を wrangler.toml の2か所へ
npx wrangler d1 migrations apply watch_queue_sync --remote
npx wrangler secret put TOKEN_PEPPER             # 32文字以上のランダム文字列（表示しない）
npx wrangler secret put ADMIN_TOKEN              # Feature Flag 切替用（省略可。未設定なら /v2/admin/flag は 404）
npx wrangler deploy
```

拡張を Chrome Web Store に出したら、その ID を `wrangler.toml` の `ALLOWED_ORIGINS` に
`chrome-extension://<id>` として追記して再デプロイする（ローカル読み込み中の ID も同様）。

## 運用

```bash
npm test                     # 純粋ロジックの単体テスト（vitest）
npm run dev                  # ローカル（--local, D1 はローカルファイル）
npm run migrate:local
npx wrangler deployments list --name watch-queue-sync
npm run tail                 # 本番ログ（秘密情報は出していない）
```

### Feature Flag の切り替え（再デプロイ不要）

```bash
curl -X POST https://<worker-url>/v2/admin/flag \
  -H "authorization: Bearer <ADMIN_TOKEN>" -H "content-type: application/json" \
  -d '{"enabled":true}'
```

`/v2/config` の `watchQueueV2Enabled` で現在値を確認できる。**OFF が既定**。
モバイルの新しいバージョンがストアで入手可能になるまで ON にしない。

### ロールバック

1. **まず Flag を OFF**（上のコマンド）。これだけで全クライアントが pre-V2 の挙動に戻る
2. Worker 自体を戻す場合: `npx wrangler rollback --name watch-queue-sync`（直前のデプロイへ）
3. D1 は破壊的変更をしない運用（列の削除・改名をしない）。キューの削除は論理削除（`deleted_at`）

## エンドポイント

| メソッド | パス | 誰が | 内容 |
|---|---|---|---|
| GET | `/v2/config` | 全員 | Feature Flag と上限値。Flag OFF でもこれだけは答える |
| POST | `/v2/pairing/start` | 拡張 | コード発行（10分・1回限り） |
| POST | `/v2/pairing/claim` | アプリ | コードを入力して承認。端末トークンを受け取る |
| POST | `/v2/pairing/complete` | 拡張 | 承認されたら端末トークンを受け取る（ポーリング） |
| GET | `/v2/queues` | 認証済み | キュー一覧（items は position 順）＋ entitlement |
| PUT | `/v2/queues/:queueId` | 拡張のみ | 丸ごと置き換え。`baseVersion` 不一致は 409 |
| DELETE | `/v2/queues/:queueId` | 認証済み | 論理削除 |
| GET/POST | `/v2/entitlement` | 参照は全員 / 報告はアプリのみ | Collection 数と Pro 判定 |
| GET | `/v2/devices` / POST `/v2/devices/revoke` | 認証済み | 接続端末の一覧と解除 |
| POST | `/v2/admin/flag` | ADMIN_TOKEN | Feature Flag の切り替え |

エラーは `{ "error": "<code>" }`。主なコード: `disabled` / `unauthorized` / `forbidden` / `notFound` /
`expired` / `alreadyUsed` / `tooManyAttempts` / `rateLimited` / `conflict` / `proRequired` / `tooManyQueues`。

## 本番の現況（2026-09-16）

- デプロイ済み: `https://watch-queue-sync.atamitrading.workers.dev`（D1 `watch_queue_sync` にマイグレーション適用済み）
- **Feature Flag は OFF**。`/v2/config` 以外は 503 を返し、全クライアントが pre-V2 の挙動のままになる。
- `TOKEN_PEPPER` / `ADMIN_TOKEN` は Worker のシークレットとして登録済み。
  値はこのリポジトリにも README にも書かない（端末内の保管場所は手元のバックアップ台帳に記載）。
- Flag を ON にする前に、`ALLOWED_ORIGINS` へ公開後の拡張 origin を追記すること（無いとペアリングが 403 になる）。
