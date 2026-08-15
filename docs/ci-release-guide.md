# Mac なしで App Store に提出する手順（GitHub Actions 版）

開発機が Windows のため、**署名付きアーカイブ〜App Store Connect へのアップロードを GitHub Actions（macOS ランナー）で
実行**します。Xcode / Mac は不要です。

| 使うもの | 役割 |
|---|---|
| [`scripts/asc_setup_signing.py`](../scripts/asc_setup_signing.py) | 配布証明書とプロビジョニングプロファイルを App Store Connect API 経由で作成し、GitHub Secrets に登録（**1回だけ**） |
| [`scripts/asc_add_extension_signing.py`](../scripts/asc_add_extension_signing.py) | **共有シート（Share Extension）用**の Bundle ID とプロファイルを作成し、Secrets に登録（**1回だけ**） |
| [`.github/workflows/ios-release.yml`](../.github/workflows/ios-release.yml) | Release アーカイブ → `.ipa` 書き出し → App Store Connect へアップロード（**毎回**） |

---

## Step 1（人手・1回だけ）App Store Connect API キーを発行する

Apple のサイトへのログインが必要なため、ここだけは手作業です。

1. https://appstoreconnect.apple.com → **ユーザーとアクセス**
2. **統合**（Integrations）タブ → **App Store Connect API** → **チームキー**
3. 「＋」でキーを生成
   - 名前: 任意（例 `CI Release`）
   - **アクセス権: 「App Manager」以上**（証明書とプロファイルを作成するため。確実にしたい場合は `Admin`）
4. **APIキーをダウンロード**（`AuthKey_XXXXXXXXXX.p8`）
   - ⚠️ **ダウンロードは一度きり**。無くしたら再発行になります。安全な場所に保管してください。
5. 同じ画面に表示される次の2つを控える
   - **キーID**（10桁程度の英数字）
   - **Issuer ID**（UUID 形式。ページ上部に表示）

> `.p8` は秘密鍵です。チャットや Git に貼らないでください（`.gitignore` に `*.p8` を登録済み）。

## Step 2（自動）署名アセットを作って GitHub Secrets に登録

ダウンロードした `.p8` のパスを指定して実行します。

```bash
# まず確認だけ（何も作らない）
python scripts/asc_setup_signing.py \
  --key-id <キーID> --issuer-id <Issuer ID> \
  --p8 "C:/path/to/AuthKey_XXXXXXXXXX.p8" --dry-run

# 問題なければ本実行（証明書・プロファイル作成 + Secrets 登録）
python scripts/asc_setup_signing.py \
  --key-id <キーID> --issuer-id <Issuer ID> \
  --p8 "C:/path/to/AuthKey_XXXXXXXXXX.p8"
```

このスクリプトがやること:

1. RSA 2048 の秘密鍵と CSR をローカル生成
2. ASC API で **Apple Distribution 証明書**を発行（`POST /v1/certificates`）
3. 秘密鍵＋証明書から **`.p12`** を作成（ランナーの keychain に入れる形式）
4. Bundle ID `com.deskflowlabs.channeltimelineviewer` を検索
5. **App Store 用プロビジョニングプロファイル**を作成（`POST /v1/profiles`）
6. 以下を GitHub Secrets に登録（値は標準出力に出しません）

| Secret | 中身 |
|---|---|
| `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_PRIVATE_KEY` | ASC API キー（アップロード認証に使用） |
| `BUILD_CERT_P12_BASE64` / `BUILD_CERT_PASSWORD` | 配布証明書（.p12） |
| `PROVISIONING_PROFILE_BASE64` / `PROVISIONING_PROFILE_NAME` | プロビジョニングプロファイル（アプリ本体） |
| `PROVISIONING_PROFILE_EXT_BASE64` / `PROVISIONING_PROFILE_EXT_NAME` | （任意）共有シート拡張用。未登録ならワークフローが自動作成 |

生成物は `build/signing/`（`.gitignore` 済み）にも保存されます。**証明書の秘密鍵はここにしか無い**ため、
別マシンでも使う場合はバックアップしてください（無くしても証明書を再発行すれば復旧できます）。

> Apple Distribution 証明書は**同時に持てる数に上限**（通常3枚）があります。使わなくなった証明書は
> Certificates, Identifiers & Profiles で失効させてください。

## Step 2.5（通常は不要）共有シート（Share Extension）用の署名

共有シート拡張は**アプリ本体とは別の Bundle ID**（`com.deskflowlabs.channeltimelineviewer.shareextension`）を
持つため、**専用のプロビジョニングプロファイルが必要**です。

> ✅ **通常この手順は不要です。** `iOS Release` ワークフローが、Step 2 で登録済みの
> App Store Connect API キーを使って、拡張用の Bundle ID とプロファイルを**実行時に自動で作成・再利用**します
> （`scripts/asc_add_extension_signing.py --ci`）。手元に `.p8` を用意する必要はありません。

固定のプロファイルを使いたい場合（監査上、事前に作っておきたい等）だけ、次を実行して
`PROVISIONING_PROFILE_EXT_BASE64` / `PROVISIONING_PROFILE_EXT_NAME` を登録してください。
登録されていれば、ワークフローは自動作成せずそちらを使います。

```bash
# まず確認だけ
python scripts/asc_add_extension_signing.py \
  --key-id <キーID> --issuer-id <Issuer ID> \
  --p8 "C:/path/to/AuthKey_XXXXXXXXXX.p8" --dry-run

# 本実行（Bundle ID 登録 + プロファイル作成 + Secrets 登録）
python scripts/asc_add_extension_signing.py \
  --key-id <キーID> --issuer-id <Issuer ID> \
  --p8 "C:/path/to/AuthKey_XXXXXXXXXX.p8"
```

やること:

1. `com.deskflowlabs.channeltimelineviewer.shareextension` の Bundle ID を確認し、無ければ登録
2. 有効な Apple Distribution 証明書を取得（Step 2 で作ったもの）
3. 拡張用の App Store プロファイルを作成
4. `PROVISIONING_PROFILE_EXT_BASE64` / `PROVISIONING_PROFILE_EXT_NAME` を Secrets に登録

> 証明書を作り直した場合（Step 2 の再実行）は、このスクリプトも**再実行**してください。
> 新しい証明書を含むプロファイルに更新されます。

## Step 3（人手・1回だけ）本番の YouTube API キーを Secret に入れる

アプリに同梱される本番キーです。**チャットに貼らず**、ご自身で次を実行してください。

```bash
gh secret set YOUTUBE_API_KEY -R kataming/ChannelTimelineViewer
# プロンプトにキーを貼り付け（画面には残りません）
```

キーには本番用の制限をかけておくこと → [`youtube-api-key-production-settings.md`](youtube-api-key-production-settings.md)

## Step 4（自動）リリースワークフローを実行

```bash
# アップロードせずビルドだけ試す（最初はこれを推奨）
gh workflow run ios-release.yml -R kataming/ChannelTimelineViewer -f upload=false

# 本番アップロード（ビルド番号は実行番号が自動で入る）
gh workflow run ios-release.yml -R kataming/ChannelTimelineViewer -f upload=true

# 進行状況
gh run watch -R kataming/ChannelTimelineViewer
```

入力パラメータ:

| 入力 | 既定 | 説明 |
|---|---|---|
| `marketing_version` | 空 | 表示バージョン（例 `1.0`）。空なら `project.yml` の値 |
| `build_number` | 空 | ビルド番号。空なら GitHub の実行番号。**同じ番号は再アップロードできない** |
| `upload` | `true` | `false` にするとアーカイブと `.ipa` 書き出しまで（artifact として取得可能） |

ワークフローの流れ:
一時 keychain に証明書を取り込み → プロファイルを配置 → `xcodegen generate` → 本番 `Config.plist` を作成 →
`xcodebuild archive`（Release / 手動署名）→ `.ipa` 書き出し → `xcrun altool` で検証＆アップロード →
keychain を削除。`.ipa` は workflow artifact としても 14 日間保存されます。

## Step 5（人手）App Store Connect で提出

アップロードから 5〜30 分ほどでビルドが処理されます。

1. **TestFlight** タブにビルドが表示される → 輸出コンプライアンス（暗号化の使用: 「いいえ」）に回答
2. 内部テスターとして自分に配信 → 実機で [`manual-test-checklist.md`](manual-test-checklist.md) を実施
3. 問題なければ **App Store** タブで提出
   - 説明文: [`AppStore/app-description.md`](AppStore/app-description.md)
   - 審査メモ: [`AppStore/review-notes.md`](AppStore/review-notes.md)
   - スクリーンショット: [`screenshot-production-guide.md`](screenshot-production-guide.md) / 文言は [`screenshot-copy.md`](screenshot-copy.md)
   - 各入力欄の下書き: [`app-store-connect-fields.md`](app-store-connect-fields.md)

---

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| `必要な Secret が未設定です` | Step 2・2.5・3 を実行。`gh secret list -R kataming/ChannelTimelineViewer` で確認 |
| `PROVISIONING_PROFILE_EXT_BASE64 が ... 用ではありません` | Step 2.5 を再実行（拡張の Bundle ID 用プロファイルを作り直す） |
| `Share Extension (.appex) が .ipa に含まれていません` | `project.yml` の `ChannelTimelineViewerShareExtension` ターゲットと本体の `dependencies` を確認 |
| TestFlight 版で共有シートに出ない | 共有シートを右端までスクロール →「その他」→ Channel Timeline Viewer をオン。それでも出ない場合はアプリを一度起動してから再試行 |
| `No signing certificate "Apple Distribution" found` | 証明書の期限切れ or 別証明書。Step 2 を再実行して作り直す |
| `Provisioning profile ... doesn't match` | Bundle ID 不一致。`project.yml` と ASC の登録値を照合 |
| `The bundle version must be higher than...` | ビルド番号の重複。`-f build_number=<大きい値>` で再実行 |
| `app-store-connect` で export 失敗 | ワークフローが自動で `method=app-store` にフォールバックする（ログ参照） |
| 証明書が上限に達した | Certificates, Identifiers & Profiles で古い配布証明書を失効させる |
