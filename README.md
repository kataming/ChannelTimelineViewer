# Channel Timeline Viewer

チャンネルの投稿動画を **公開日順（古い順）** に整理し、公式の埋め込みプレイヤーで順番に視聴できる
iPhone 向けの **「チャンネル動画の時系列視聴・進捗管理アプリ」** です。

単なる YouTube 視聴アプリの代替ではなく、**過去動画の最初からの視聴・シリーズ視聴・学習教材としての進捗管理**を
しやすくすることに特化しています（チャンネルごとの進捗率、未視聴フィルター、続きから見る、動画メモ など）。

> プロジェクト名・ターゲット/モジュール名・表示名・製品名・Bundle ID をすべて `Channel Timeline Viewer`
> 系に統一しています。

## ⚠️ 重要な注意事項（ディスクレーマー）

- **このアプリは YouTube 公式アプリではありません。**
- **動画再生には YouTube 公式の埋め込みプレイヤー（IFrame Player）を使用しています。**
- **動画のダウンロードは行いません。**
- **広告回避は行いません。**
- **バックグラウンド再生は行いません。**

このアプリは YouTube 公式アプリの代替ではなく、チャンネル動画を公開日順に整理し、**学習・過去動画視聴・
シリーズ視聴**をしやすくする補助アプリです。動画一覧の取得は **YouTube Data API v3**、再生は
**YouTube IFrame Player API（WKWebView 経由の公式埋め込み）** を使用し、スクレイピング・独自プレイヤーでの
再生・再生制限の回避は一切行いません。これらの注意事項はアプリ内の「ⓘ このアプリについて」画面にも表示されます。

---

## 主な機能

### 基本（MVP）
- チャンネルURL入力（`@handle` / `/channel/UC...` / `/c/name` / `/user/name`）
- **共有シート対応（Share Extension）**：YouTube アプリ / Safari の共有ボタンから
  「Channel Timeline Viewer」を選ぶだけでチャンネルを開ける（後述）
- チャンネル解決 → アップロード動画一覧の取得（ページネーション対応）
- **publishedAt 昇順（古い順）** での一覧表示、古い順 / 新しい順の切り替え
- サムネイル・タイトル・公開日・視聴済みマーク付きリスト
- 公式 IFrame プレイヤーでの再生、前へ / 次へ / 視聴済み切替 / YouTubeで開く
- お気に入りチャンネル・視聴履歴（videoId 単位）のローカル保存
- APIキー未設定・通信エラー時の日本語エラー表示

### 差別化（MVP+）— 時系列視聴・進捗管理
- **チャンネルごとの進捗管理**：視聴済み数 / 総本数・進捗率（%）・`ProgressView` の進捗バー
- **「次に見る／続きから見る」導線**：最も古い未視聴動画（または最後に開いた未視聴動画）を目立つ位置に表示
- **フィルター**：古い順 / 新しい順 ＋ すべて / 未視聴のみ / 視聴済みのみ
- **続きから見る**：チャンネルごとに最後に開いた動画（`lastOpenedVideoId` / `lastOpenedAt`）を保存
- **前回の停止位置から再生**：動画ごとの再生位置を端末内に保存し、次に開いたとき続きから再生（既定オン）。
  再生画面の「続きから再生する」トグルでオフにでき、「最初から」ボタンで頭出しもできる
- **終了したら次を自動再生（任意機能・既定オフ）**：再生画面に常時表示されるトグルを
  **ユーザーが自分でオンにしたときだけ**、一覧の次の動画へ続けて再生する。
  既定のオフのままなら終了時に停止し、「次の動画を再生」ボタンを表示する
- **複数チャンネルのお気に入り管理**：一覧に進捗バー表示・削除機能
- **動画ごとのメモ**：再生画面で videoId 単位のメモを保存（学習・シリーズ視聴用、日本語可）

> データはすべて端末内（UserDefaults）に保存します。将来 SwiftData へ移行しやすいよう、
> 保存処理は `WatchHistoryStore` / `FavoriteChannelStore` / `ChannelProgressStore` / `VideoMemoStore` に分離しています。

---

## 共有シートから開く（Share Extension）

チャンネルURLを手で入力しなくても、**YouTube アプリや Safari の共有ボタン**から直接開けます。

### 使い方

1. YouTube アプリ（または Safari）でチャンネル、または動画のページを開く
2. **共有** ボタンをタップ
3. 共有先の一覧から **Channel Timeline Viewer** をタップ
4. Channel Timeline Viewer が起動し、共有されたURLを解析して動画一覧（古い順）を開く
   - チャンネルURL（`@handle` / `/channel/UC...` / `/c/name` / `/user/name`）→ そのチャンネルの一覧
   - 動画URL（`watch?v=...` / `youtu.be/...` / `/shorts/...` / `/live/...`）→ **その動画を投稿した
     チャンネル**を `videos.list` で特定して一覧を開く
5. 開いたチャンネルはこれまでどおり「最近使ったチャンネル」に保存され、進捗管理の対象になる

> 共有シートに **Channel Timeline Viewer が見当たらない場合**：共有シートを一番右まで
> スクロールして **「その他」／「アクションを編集…」** をタップし、Channel Timeline Viewer の
> スイッチをオンにしてください（初回のみ必要なことがあります）。並べ替えて上位に固定もできます。

### 仕組みと制約（重要）

- Share Extension は**受け取ったURLをメインアプリへ渡すだけ**です。
  `channeltimelineviewer://share?url=<共有されたURL>` でメインアプリを開きます。
- **Extension 側では YouTube API を呼びません。** APIキーの管理・API 取得・エラー表示・画面遷移は
  すべてメインアプリ側に集約しています（キーを複数バンドルに配らないため）。
- 受け取れるのは **`public.url`（URL）と `public.plain-text`（テキスト）** の両方です。
  YouTube アプリは URL ではなく「動画タイトル + URL」のテキストとして共有してくることがあるため、
  テキストからも YouTube の URL を抽出します（`Services/SharedLinkParser.swift`）。
- YouTube 以外のURLは受け取っても無視します（誤爆防止）。
- 従来どおりの**手入力の導線もそのまま使えます**。

関連ファイル:

| ファイル | 役割 |
| --- | --- |
| `ShareExtension/ShareViewController.swift` | 共有されたURL/テキストを取り出してメインアプリを開く |
| `ShareExtension/Info.plist` | 共有シートに出す条件（`NSExtensionActivationRule`）と表示名 |
| `Services/SharedLinkParser.swift` | URL抽出・カスタムURLの組み立て（アプリ／拡張の両方に同梱） |
| `Services/SharedLinkRouter.swift` | メインアプリ側の受け口（`onOpenURL` → 画面へ） |
| `App/Info.plist` | カスタムURLスキーム `channeltimelineviewer` の定義 |

---

## 必要環境

- macOS + **Xcode 15 以降**（iOS 17.0 以降をターゲット）
- iPhone 実機またはシミュレータ（iOS 17+）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`.xcodeproj` を生成するために使用）
  - 未インストールなら: `brew install xcodegen`
- YouTube Data API v3 の APIキー

> 注: 本リポジトリには `.xcodeproj` を含めず、`project.yml` から XcodeGen で生成する方式です。
> Xcode で「新規 App プロジェクトを作成し、各 Swift ファイルを取り込む」手順でも構いません。

---

## YouTube Data API v3 APIキーの取得

1. [Google Cloud Console](https://console.cloud.google.com/) でプロジェクトを作成
2. 「APIとサービス」→「ライブラリ」で **YouTube Data API v3** を有効化
3. 「認証情報」→「認証情報を作成」→「APIキー」でキーを発行
4. （推奨）APIキーに「iOSアプリ」制限・「YouTube Data API v3」制限をかける

> 無料枠は1日あたり 10,000 quota units です。`search.list`（カスタムURL解決時）は100 units、
> `playlistItems.list` は1ページ1 unit 程度です。大きなチャンネルは消費に注意してください。

---

## Config.plist の作り方

APIキーはコードに直書きしません。`Resources/Config.example.plist` をコピーして
`Resources/Config.plist` を作成し、APIキーを設定します。

```bash
cp Resources/Config.example.plist Resources/Config.plist
```

`Resources/Config.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>YOUTUBE_API_KEY</key>
    <string>（取得した実APIキー）</string>
</dict>
</plist>
```

`Config.plist` は `.gitignore` 済みでコミットされません。
（CI・デバッグ用に、環境変数 `YOUTUBE_API_KEY` でも読み込めます。）

---

## ビルド方法

```bash
# 1) プロジェクトを生成
xcodegen generate

# 2) Xcode で開く
open ChannelTimelineViewer.xcodeproj

# 3) ターゲット ChannelTimelineViewer をシミュレータで実行（Cmd+R）
#    テスト実行は Cmd+U
#    ※ シミュレータなら Apple Developer 登録・署名は不要（実機実行のみ署名が要る）
```

コマンドラインからのビルド例（署名なし・シミュレーター向け）:

```bash
# ビルド（コンパイル確認）
xcodebuild -project ChannelTimelineViewer.xcodeproj \
  -scheme ChannelTimelineViewer \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build

# テスト
xcodebuild -project ChannelTimelineViewer.xcodeproj \
  -scheme ChannelTimelineViewer \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  CODE_SIGNING_ALLOWED=NO test
```

> App Store 提出に必要な署名・Bundle ID・Team ID は **まだ設定していません**。Apple Developer Program
> 加入後に `project.yml` の `DEVELOPMENT_TEAM` と `PRODUCT_BUNDLE_IDENTIFIER` を差し替えて移行します。

---

## GitHub Actions でのビルド確認（CI）

ローカルが Windows などで Xcode を使えない場合でも、**GitHub Actions の macOS ランナー**で
コンパイル確認ができます。ワークフロー: [`.github/workflows/ios-build.yml`](.github/workflows/ios-build.yml)

やっていること:

1. `macos-14` ランナー（Xcode 15.x / iOS 17 SDK）で実行
2. `brew install xcodegen` → `xcodegen generate` で `.xcodeproj` を生成
3. `Resources/Config.example.plist` を `Config.plist` にコピーし、`YOUTUBE_API_KEY` に **CI用ダミー値** を設定
4. **署名なし・シミュレーター向けに Debug ビルド**（`CODE_SIGNING_ALLOWED=NO`、`generic/platform=iOS Simulator`）
5. 続けて **ユニットテスト** を実行（`iPhone 15` シミュレーター）

使い方:

```bash
# このフォルダ(ChannelTimelineViewer)を GitHub リポジトリのルートとして push する
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/<your-account>/<repo>.git
git push -u origin main
```

- push（または PR）すると自動でビルドが走ります。**Actions タブ**から手動実行（Run workflow）も可能です。
- 結果・ログは GitHub の **Actions** タブで確認できます。失敗時はログにビルドエラーがそのまま出るので、
  内容を共有いただければ修正できます。
- App Store 配布・実機配布・Apple Developer Program の設定は不要です（CIはコンパイル確認のみ）。
- テストは実在する iPhone シミュレーターの UDID を `xcrun simctl` で**自動選択**するため、Xcode/ランナーの
  バージョンが変わってもデバイス名の調整は不要です。

> 注: `.xcodeproj` と `Config.plist` は `.gitignore` 済みでコミットされません。CI 側でその都度生成・作成します。
> リポジトリには Swift ソース・`project.yml`・`Config.example.plist` があれば十分です。

---

## ディレクトリ構成

```
ChannelTimelineViewer/
  App/        ChannelTimelineViewerApp.swift / Info.plist（カスタムURLスキーム）
  Models/     Channel.swift / VideoItem.swift / WatchHistory.swift
  Services/   ConfigLoader / YouTubeAPIError / ChannelResolver /
              YouTubeAPIClient / WatchHistoryStore / FavoriteChannelStore /
              SharedLinkParser / SharedLinkRouter（共有シート用）
  ViewModels/ ChannelInputViewModel / VideoListViewModel / PlayerViewModel
  Views/      ChannelInputView / FavoriteChannelsView / VideoListView /
              PlayerView / YouTubePlayerWebView
  ShareExtension/ ShareViewController.swift / Info.plist（共有シート拡張）
  Resources/  Config.example.plist（Config.plist は各自作成）
  Tests/      ChannelResolverTests / SharedLinkParserTests / VideoChannelLookupTests /
              VideoSortTests / WatchHistoryStoreTests
  project.yml（XcodeGen 用）
```

ターゲット構成:

| ターゲット | Bundle ID | 役割 |
| --- | --- | --- |
| `ChannelTimelineViewer` | `com.deskflowlabs.channeltimelineviewer` | アプリ本体 |
| `ChannelTimelineViewerShareExtension` | `com.deskflowlabs.channeltimelineviewer.shareextension` | 共有シート（URLを本体へ渡すだけ） |

技術スタック: Swift / SwiftUI / MVVM / async-await / WKWebView / YouTube Data API v3 / UserDefaults。

---

## 注意事項（YouTube規約への配慮）

- 動画は **必ず公式の IFrame Player（WKWebView 埋め込み）** で再生します。独自プレイヤーや
  ダウンロードは行いません。
- **自動再生は任意機能で、既定はオフ**です。再生終了時は停止し、「次の動画を再生」ボタンを表示します。
  再生画面に常時表示される「終了したら次を自動再生」トグルを**ユーザーが明示的にオンにしたときだけ**、
  続けて再生します（オン状態は端末内に保存されます）。
- 自動再生をオンにした場合でも、進む先は**ユーザーが開いているチャンネル一覧の次の動画だけ**です。
  YouTube の関連動画・おすすめへ進むことはありません（`rel=0`）。
- **バックグラウンド再生は行いません**。アプリを閉じる・画面をロックすると再生も止まるため、
  自動再生が裏で走り続けることはありません。
- 広告・YouTube UI・再生制限の回避は行いません。
- 動画一覧の取得は Data API v3 のみで、スクレイピングはしません。
- 公開する場合は、最新の [YouTube API サービス利用規約](https://developers.google.com/youtube/terms/api-services-terms-of-service)
  と [ブランドガイドライン](https://developers.google.com/youtube/terms/branding-guidelines) を必ず再確認してください。

---

## 既知の制約

- アップロードプレイリストは新しい順で返るため、**古い順表示には全ページの取得が必要**です。
  動画数の多いチャンネルでは初回読み込みに時間がかかり、quota も消費します（安全のため最大100ページ）。
- カスタムURL（`/c/name` や `/name`）は `search.list`（100 units）で channelId を解決するため、
  ヒット精度は YouTube 検索に依存します。`@handle` / `/channel/UC...` が最も確実です。
- IFrame の `ended` イベントが取得できない場合は、「次へ」ボタンで手動遷移してください。
- 共有シートに拡張が出てくるのは、**アプリを1回起動した後**になることがあります。また、共有先の一覧に
  出ない場合は「その他」からオンにする必要があります（iOS の仕様）。
- 共有されたURLに**非ASCII文字**（日本語のカスタムURL等）が含まれる場合は解析できません。
  その場合は従来どおりURLを手入力してください。
- 動画URLからチャンネルを開く場合、非公開・削除済みの動画では投稿チャンネルを特定できません。

---

## 動作確認（ビルド以外・Mac なしでも可）

ビルド成功に加えて「YouTube API で動画一覧が取れるか」「公式埋め込みプレイヤーで再生できるか」を確認する手段です。

### A. 公式プレイヤーの再生確認（APIキー不要・ブラウザ）
[`tools/player-test.html`](tools/player-test.html) をブラウザで開く → 動画が再生され、状態イベント（特に
`ended`）がログに出れば、アプリ内 `YouTubePlayerWebView` と同じ公式 IFrame Player の仕組みが動作しています。

### B. 動画一覧取得の確認（ローカル・要 APIキー）
アプリ本体と同じ流れ（チャンネル解決 → uploads → 全ページ取得 → 古い順ソート）を Python で確認します。

```bash
# キーは Resources/Config.plist か環境変数 YOUTUBE_API_KEY で渡す（コマンドラインに直書きしない）
python tools/verify_youtube_api.py "https://www.youtube.com/@ハンドル"
```
→ 取得本数・最も古い5本/新しい5本・古い順ソートOK が表示されれば、API 取得ロジックは妥当です。

### C. 本体(Swift)を実APIで検証（CI・要 GitHub Secret）
実際の `YouTubeAPIClient` を本物の API に当てる統合テスト（[`Tests/YouTubeAPIIntegrationTests.swift`](Tests/YouTubeAPIIntegrationTests.swift)）。

1. YouTube Data API v3 のキーを用意（取得方法は上記参照）
2. GitHub リポジトリ → Settings → Secrets and variables → Actions → **New repository secret**
   - Name: `YOUTUBE_API_KEY` / Value: 実際のキー
3. push すると CI が実 API に当ててチャンネル解決・動画取得を検証（Secret 未登録ならスキップ＝通常は緑のまま）

> いずれも実機/シミュレーターでの UI 操作確認の代替です。実アプリの画面操作確認は Mac/Xcode が必要です。

## 実機確認・App Store 提出準備

提出を見据えた資料：

- [`docs/manual-test-checklist.md`](docs/manual-test-checklist.md) — **Mac/実機での実画面確認チェックリスト**（MVP+全機能）
- [`docs/app-store-preparation.md`](docs/app-store-preparation.md) — **公開準備の地図**（現在の名称/ID、加入後の差し替え場所、本番Config、誤push防止）
- [`docs/privacy-policy.md`](docs/privacy-policy.md) — **プライバシーポリシー**（GitHub Pages で公開 → 下記URL）
- [`docs/app-store-description.md`](docs/app-store-description.md) — **App Store 説明文**（時系列視聴・進捗管理・学習補助として表現／日英）
- [`docs/screenshot-copy.md`](docs/screenshot-copy.md) — **スクリーンショット用キャプション文言**
- [`docs/testflight-checklist.md`](docs/testflight-checklist.md) — **TestFlight 実機確認チェックリスト**
- [`docs/youtube-api-key-production-settings.md`](docs/youtube-api-key-production-settings.md) — **APIキー本番制限**（iOS Bundle ID 制限・YouTube Data API v3 制限）
- [`docs/app-icon-requirements.md`](docs/app-icon-requirements.md) — **アプリアイコン要件**（1024px/透過なし/ロゴ不使用）
- [`docs/screenshot-production-guide.md`](docs/screenshot-production-guide.md) — **スクリーンショット作成手順**（サイズ・撮影・キャプション）
- [`docs/app-store-connect-fields.md`](docs/app-store-connect-fields.md) — **App Store Connect 入力項目の下書き**
- [`docs/support.md`](docs/support.md) — **サポートページ**（GitHub Pages で公開 → `/support/`）
- [`docs/monetization-plan.md`](docs/monetization-plan.md) — **収益化方針**（初回は無料・広告なし・IAPなし。将来Proはアプリ独自機能のみ課金）

参考（初期ドラフト）:
- [`docs/AppStore/README.md`](docs/AppStore/README.md) — 索引・プライバシーポリシーURLの設定場所
- [`docs/AppStore/app-description.md`](docs/AppStore/app-description.md) — App Store 説明文の下書き（日本語/英語）
- [`docs/AppStore/review-notes.md`](docs/AppStore/review-notes.md) — 審査向けメモ（公式プレイヤー使用・禁止実装なしの説明）
- [`docs/AppStore/testflight-checklist.md`](docs/AppStore/testflight-checklist.md) — TestFlight 前チェックリスト
- [`docs/AppStore/privacy-policy-template.md`](docs/AppStore/privacy-policy-template.md) — プライバシーポリシー雛形

提出前に必要な主な設定:

- **アプリ名（表示名）**: `Channel Timeline Viewer`（`project.yml` の `INFOPLIST_KEY_CFBundleDisplayName`）
- **Bundle ID**: `com.deskflowlabs.channeltimelineviewer`（App Store Connect 登録済み・設定済み）
- **DEVELOPMENT_TEAM**: `project.yml` に自分の Team ID を設定（未設定）
- **プライバシーポリシーURL**: `Resources/Config.plist` の `PRIVACY_POLICY_URL` に設定（アプリ内「ⓘ」画面に表示）。
  App Store Connect 側にも同じURLを登録する。

### 公開URL（GitHub Pages）と App Store Connect 用URL候補

GitHub Pages（`main` ブランチの `/docs` フォルダ）で公開。`docs/*.md` の front matter `permalink` でパス固定。
公開反映は push 後 1〜2分（Pages ビルド）。

| 用途 | URL（公開済み） | 設定先 |
|---|---|---|
| **プライバシーポリシーURL** | https://kataming.github.io/ChannelTimelineViewer/privacy/ | `Config.plist` の `PRIVACY_POLICY_URL` ＋ App Store Connect |
| **サポートURL** | https://kataming.github.io/ChannelTimelineViewer/support/ | App Store Connect「サポートURL」 |
| マーケティングURL（任意） | https://kataming.github.io/ChannelTimelineViewer/ | App Store Connect「マーケティングURL」 |

> サポートURLの代替候補：GitHub リポジトリURL（`https://github.com/kataming/ChannelTimelineViewer`）や
> 問い合わせ用メール（`mailto:atamitrading@wind.ocn.ne.jp`）でも可。App Store Connect は到達可能なWebページURLを推奨。

> 設定の再現方法（別アカウント等）: リポジトリ Settings → Pages → Source を「Deploy from a branch」、
> Branch を `main` / フォルダ `/docs` に設定。`docs/_config.yml`（テーマ）が描画に使われます。
> 公開前に `docs/privacy-policy.md` の `[ ]`（日付・連絡先・提供者）を実際の情報に置き換えてください。

### TestFlight 提出までの手順（Apple Developer Program 加入後）

> 現状は署名なし。以下は **加入後**に行う。コードは差し替えだけで移行できる形にしてある。

1. ~~**Apple Developer Program 加入**（年額 約$99）~~ ✅ 完了
2. **名称・ID を本番値に**（`project.yml`、詳細は [`docs/app-store-preparation.md`](docs/app-store-preparation.md)）
   - `DEVELOPMENT_TEAM` に自分の Team ID（10桁） ← **未設定**
   - ~~`PRODUCT_BUNDLE_IDENTIFIER`~~ ✅ `com.deskflowlabs.channeltimelineviewer` に設定済み
   - 変更後 `xcodegen generate`
3. ~~**アプリアイコン 1024px**~~ ✅ `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` 配置済み
   （`scripts/generate_app_icon.py` で生成。差し替える場合は同スクリプトを編集して再実行）
4. **本番 `Config.plist`** を作成（`YOUTUBE_API_KEY` 実キー＋`PRIVACY_POLICY_URL`）
5. **App Store Connect でアプリ作成**（Bundle ID を一致させる）→ プライバシーポリシーURL・年齢区分等を設定
6. **Xcode でアーカイブ**：Product → Archive（署名は Automatic signing 推奨）
7. **Organizer から Distribute App → App Store Connect → Upload**
8. App Store Connect の **TestFlight** タブでビルドを選び、内部テスターに配信 → 実機で動作確認
9. 問題なければ審査提出（説明文・スクショ・[`review-notes.md`](docs/AppStore/review-notes.md) のメモを記載）

実機での実画面確認は [`docs/manual-test-checklist.md`](docs/manual-test-checklist.md) に沿って行う。

## 今後の改善案

- プレイリスト単位の古い順再生
- 複数チャンネルのお気に入り管理の強化
- 視聴進捗率（途中までの再生位置）の保存
- 動画検索・絞り込み
- iPad 対応
- CloudKit による端末間同期
- App Store 提出前の YouTube API ポリシー再確認
