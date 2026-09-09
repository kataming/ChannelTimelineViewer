# Android 版の利用状況の記録（Google Analytics for Firebase）

Android 版だけに入れている **Google Analytics for Firebase** の仕組み・置き方・確認の仕方・
ストア申告のまとめ。iOS 版には入れていない（入れる予定も無い）。

- 実装の入り口: `android/app/src/main/java/com/deskflowlabs/channeltimelineviewer/analytics/Analytics.kt`
- Firebase 実装: 同 `analytics/FirebaseAnalyticsTracker.kt`
- オプトアウトの保存: `data/AnalyticsSettingsStore.kt`
- テスト: `app/src/test/.../AnalyticsTest.kt`

---

## 1. 方針（ここを崩さないこと）

このアプリは「アカウント不要・端末内だけ」を売りにしている。計測を足したあとも、その説明が
**嘘にならない範囲**に閉じる。

- **送ってよいのは「アプリの使われ方」だけ。** 画面名と操作の種類、一覧の本数まで。
- **送らないもの**: チャンネルID／チャンネル名／動画ID／動画タイトル／メモの中身／入力されたURL。
  つまり「その人が何を見ているか」は一切出さない。
- **広告IDは使わない。** `AndroidManifest.xml` で `com.google.android.gms.permission.AD_ID` を
  `tools:node="remove"` で外し、`google_analytics_adid_collection_enabled` などを `false` にしている。
- **オプトアウトを必ず用意する。** 「ⓘ このアプリについて」の一番下の切り替え（既定オン）。
  オフにすると `setAnalyticsCollectionEnabled(false)` で Firebase ごと止まる。
- 新しいイベントを足すときは `Analytics.Event` に名前を足し、**引数に個人の視聴内容を入れない**。
  `AnalyticsTest` が「動画IDやタイトルが記録に混ざっていないか」を機械的に見ている。

プライバシーポリシー（7言語・`site/src/i18n/translations.js` の `privacy` と
`docs/privacy-policy.md`）にも同じ内容を書いてある。**送る中身を変えたら必ず両方を直すこと。**

---

## 2. 何を送っているか（イベント一覧）

| イベント | いつ | 引数 |
| --- | --- | --- |
| `screen_view` | 画面を開いたとき | `screen_name` = `channel_input` / `about` / `pro` / `video_list` / `player` |
| `channel_open` | チャンネルの一覧を開いた | `source` = `url` / `share` / `saved` / `switch` |
| `channel_limit_hit` | 無料の保存上限に当たって案内を出した | `source` |
| `channel_replace` | 保存中のチャンネルを外して入れ替えた | なし |
| `channel_remove` | 保存を解除した | なし |
| `video_open` | 動画を開いた | `source` = `list` / `auto_advance` / `navigation`、1本目のみ `video_count` |
| `video_finish` | 動画を最後まで見た | `result` = `auto_next` / `repeat_one` / `stopped` |
| `playback_setting` | 再生設定を切り替えた | `setting` = `autoplay_next` / `resume` / `repeat` / `unwatched_only`、`value` = `on` / `off` / `one` / `all` |
| `open_in_youtube` | 「YouTubeで開く」を押した | なし |
| `pro_purchase_start` | Pro の購入を始めた | なし |
| `pro_purchase_end` | Pro の購入が終わった | `result` = `purchased` / `pending` |
| `pro_restore` | 「購入を復元」を押した | なし |

このほかに Google アナリティクスが自動で集めるもの（`first_open`・`session_start`・
アプリのバージョン・OSのバージョン・機種・国などの大まかな地域・アプリごとの識別子）がある。
自動収集は個別に切れないので、**オフにしたい人にはオプトアウトを使ってもらう**。

> 「記録をオンに戻した」イベントは**あえて置いていない**。`setAnalyticsCollectionEnabled(true)` の反映は非同期で、直後に `logEvent` しても
> 「まだ無効」と判定されて捨てられるため（実機で確認済み）。待ち時間を入れれば通るが、
> タイミング頼みの記録は入れない方針。オンに戻ったことは `screen_view` が再開することで分かる。

---

## 3. 設定ファイル（google-services.json）の置き方

YouTube API キーと同じ扱いで、**リポジトリには入れない**（`android/.gitignore` 済み）。
無くてもビルドは通り、その場合 Firebase は初期化されない＝計測は完全に止まる。

### 3-1. 使っているプロジェクト（2026-09-09 に作成済み）

**新しく作る必要は無い。** 既に次の構成で用意してある。

| 項目 | 値 |
| --- | --- |
| GCP / Firebase プロジェクト | `channel-timeline`（プロジェクト番号 `925484759907`） |
| Firebase の Android アプリ | `1:925484759907:android:15fd9ae57a27e97798b156` |
| パッケージ名 | `com.deskflowlabs.channeltimelineviewer` |
| GA4 プロパティ | `553416503`（アナリティクス アカウント `407372302`） |
| APK に載る API キー | Firebase が自動作成したもの。**Firebase 系 API のみに制限**されており、同じプロジェクトの `youtube.googleapis.com` は呼べない |

`channel-timeline` は YouTube Data API のキーが入っている**アプリ本体のプロジェクト**。
Web体験版用の `channel-timeline-web` とは別なので取り違えないこと。

設定ファイルを取り直したいときは Firebase コンソール →「プロジェクトの設定」→「マイアプリ」→
`google-services.json` をダウンロード。

> 別プロジェクトで1から作る場合の注意: **Firebase 利用規約への同意と Google アナリティクス
> アカウントの作成は API では行えない**（本人の同意が要るため）。コンソールの
> 「プロジェクトを追加」から進め、**Google アナリティクスは必ず有効**にすること。
> そこから先（Android アプリの登録・設定ファイルの取得）は Firebase Management API で自動化できる。

### 3-2. 自分の端末に置く

```
android/app/google-services.json
```

置くだけでよい（`app/build.gradle.kts` がファイルの有無を見て google-services プラグインを
適用する）。置かない場合はプラグインごと適用されず、`Analytics.Noop` が入る。

### 3-3. CI（GitHub Actions）に渡す

リリース用ワークフロー `android-release.yml` は Secrets の `GOOGLE_SERVICES_JSON_B64` から
復元する。**未設定だとリリースビルドはわざと失敗する**（計測が入らないアプリを気づかずに
出さないため）。登録は次のとおり。中身は画面に出ない。

```powershell
# PowerShell（リポジトリのルートで）
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/google-services.json")) `
  | Out-File -Encoding ascii -NoNewline "$env:TEMP\gs.b64"
gh secret set GOOGLE_SERVICES_JSON_B64 < "$env:TEMP\gs.b64"
Remove-Item "$env:TEMP\gs.b64"
```

`android-build.yml`（PR / push のビルド）は **本物を使わない**。この workflow が作る APK は
公開リポジトリの成果物として誰でも落とせるため、偽物の見本
`android/app/google-services.json.example` をコピーして、
「設定ファイルがある側のビルド経路が壊れていないか」だけを見ている。

---

## 4. 動きの確かめ方

計測は送信までに時間がかかる（通常のレポートは最大24時間）。すぐ確かめたいときは **DebugView**。

```powershell
# 実機・エミュレーターを繋いだ状態で
adb shell setprop debug.firebase.analytics.app com.deskflowlabs.channeltimelineviewer
# 解除
adb shell setprop debug.firebase.analytics.app .none.
```

Firebase コンソール →「Analytics」→「DebugView」に、画面遷移や操作がその場で並ぶ。

確認したい観点:

1. アプリを起動 → `screen_view (channel_input)` が出る
2. チャンネルを開く → `channel_open (source=url)` が出て、**チャンネル名やIDが引数に無い**
3. 「ⓘ このアプリについて」→「利用状況の記録を許可する」をオフ → **以降なにも出なくなる**
4. アプリを再起動してもオフのまま（Firebase が端末に覚えるため）
5. オンに戻す → 次の画面移動から `screen_view` がまた出るようになる

---

## 5. Play Console の「データセーフティ」の申告

Analytics を入れたので、**申告の更新が必要**。次の内容で申告する（実装と一致している）。

- 収集する: **アプリのアクティビティ**（アプリの操作 / App interactions）
  - 目的: 分析（Analytics）
  - 収集は **必須ではない（ユーザーがオフにできる）** → 「データ収集は任意」を選ぶ
  - 共有: **していない**（Google はこちらの代理として処理する処理者であり、第三者提供ではない）
  - 転送時に暗号化: **はい**
  - 削除の依頼: サポートページの「データの削除をリクエストする」節で受け付ける。
    Play に入れる URL は `https://channeltimeline.jewelrysunflower.com/en/support/#data-deletion`
    （7言語ぶん同じ節がある。文言は `site/src/i18n/translations.js` の `support.deletion`）
- 収集する: **アプリの情報とパフォーマンス**（クラッシュログは入れていないので、
  Crashlytics を入れるまでは申告不要）
- **広告ID: 収集しない**（`AD_ID` 権限を外してあるので、Play の自動チェックとも一致する）
- 端末IDやおおよその位置は、Google アナリティクスが自動で集める範囲にとどまる。
  「デバイスまたはその他の ID」は**収集する**として申告しておくのが安全
  （アプリインスタンスID が該当するため）。

> ⚠️ Play は `AD_ID` 権限の有無を自動で見ている。将来 Firebase の別のライブラリ（広告系）を
> 足すと権限が復活することがある。足したときは必ずマージ後のマニフェストを確認すること。
> 確認: `android/app/build/intermediates/merged_manifest/*/AndroidManifest.xml` を
> `AD_ID` で検索し、`com.google.android.gms.permission.AD_ID` が**無い**こと。

---

## 6. バージョンの縛り（重要）

`gradle/libs.versions.toml` の `firebaseBom` は **33.7.0 で止めてある**。理由は Kotlin の版。

- Firebase BOM 33.8.0 以降は `play-services-measurement` 22.2.0 以上を連れてくる
- その中身は **Kotlin 2.1 以降のメタデータ**で作られている
- 本プロジェクトの Kotlin は **2.0.21** なので、
  `Module was compiled with an incompatible version of Kotlin` でコンパイルできない

上げたいときは、先に `kotlin` を上げること（最新の BOM を使うなら 2.2 以上）。
Kotlin を上げると Compose コンパイラプラグインも一緒に上がるので、**上げるなら単独の作業**にして
CI を通してから Firebase を上げる。

---

## 7. 関連ファイル

| ファイル | 役割 |
| --- | --- |
| `android/gradle/libs.versions.toml` | Firebase BOM と google-services プラグインの版 |
| `android/build.gradle.kts` | google-services プラグインを classpath に載せる |
| `android/app/build.gradle.kts` | 設定ファイルがある時だけプラグインを適用／依存の追加 |
| `android/app/src/main/AndroidManifest.xml` | AD_ID 権限の除去・広告系シグナルの無効化 |
| `android/app/google-services.json.example` | CI 用の偽物の見本（本物はコミットしない） |
| `.github/workflows/android-build.yml` | 見本を置いてビルド経路を確認 |
| `.github/workflows/android-release.yml` | Secrets から本物を復元（未設定なら失敗させる） |
| `Localization/strings.json` | 画面の文言（`about.analytics.*`・Android 専用） |
| `docs/privacy-policy.md` / `site/src/i18n/translations.js` | プライバシーポリシー（7言語） |
