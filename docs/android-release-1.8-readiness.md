# Android 1.8 (10) リリース前チェック（Firebase Analytics 入りの初回）

2026-09-12 実施。**実リリース・GitHub Actions 実行・Play アップロード・git push は行っていない。**
確認とローカル検証だけ。結論は「**リリース可**（ユーザー操作が2件残る）」。

対象コミット: `6dc1145`（Android のコードは `690912c` のまま。以後の変更は `site/` のみ）

---

## 1. 何を出すことになるか

| 項目 | 値 |
| --- | --- |
| versionName | **1.8**（Android Release の `version_name` に手入力する） |
| versionCode | **10**（`github.run_number` から自動。前回 run #9 = 1.7(9)） |
| 直前の製品版 | 1.6 (8) |
| 直前の内部テスト | 1.7 (9) |
| 中身 | Google Analytics for Firebase の導入＋Play Console の指摘3件（R8 難読化・fragment 1.8.9・エッジツーエッジ） |

`versionCode` / `versionName` は `android/app/build.gradle.kts:101-102` が環境変数から読む。
リポジトリには数値を持たない。供給元は `.github/workflows/android-release.yml:93-94`。

---

## 2. ローカル検証の結果（このリポジトリの実ファイルで実施）

`ANDROID_VERSION_CODE=10` / `ANDROID_VERSION_NAME=1.8` を与えて、CI と同じ Gradle タスクを流した。

| 検証 | 結果 |
| --- | --- |
| `testDebugUnitTest` | **81 件すべて成功**（失敗0・エラー0・スキップ0）。うち `AnalyticsTest` が 9 件 |
| `lintDebug` | エラー1件だが**ローカル環境由来**（下記 4-1）。アプリのコードにエラーは無い |
| `bundleRelease` / `assembleRelease`（R8 有効） | **成功**（5分49秒）。AAB 4.8MB / APK 2.3MB |
| APK の versionCode / versionName | `versionCode='10' versionName='1.8'` ✅ 環境変数が正しく通っている |
| 署名 | アップロード鍵で署名済み（`CN=Deskflow Labs`） |
| `docs/player.html` の回帰テスト | `node tools/player_nearend_test.js` すべて通過 |

### R8（難読化）で壊れていないこと

CLAUDE.md が「壊すと再生が止まる／利用者の記録が読めなくなる」と警告している2点を、
実際の `mapping.txt` で確認した。

- **JS ブリッジ**: `ui.PlayerBridge` → `ui.m` にクラス名は変わるが、
  **メソッド名 `postMessage` は保持**されている。JS は `window.ytAndroid.postMessage(...)` と
  メソッド名でしか呼ばないので問題ない
- **保存データのモデル**: `model.Channel` / `ChannelProgress` / `FavoriteChannel` /
  `PlaybackPosition` / `VideoItem` と、その `$$serializer` `$Companion` が
  **すべて元の名前のまま**。既存ユーザーの視聴済み・進捗・メモは更新後も読める
- AAB に `BUNDLE-METADATA/.../proguard.map` が入っている＝Play にクラッシュの対応表が自動で渡る

### Firebase が実際に入っていること

- DEX に `com/google/firebase/analytics/FirebaseAnalytics` と
  `com/google/android/gms/measurement` が含まれる
- リソースに `google_app_id` がある＝`google-services.json` が処理されている
  （`app/build.gradle.kts` がファイルの有無を見てプラグインを適用する作り。配置先は
  `android/app/google-services.json` で正しい。ローカルにも本物が置いてあり、
  パッケージ名 `com.deskflowlabs.channeltimelineviewer` はアプリの applicationId と一致）

---

## 3. 既存機能への影響

コードの変更はすべて**追加**で、既存の分岐を書き換えていない。

- `Analytics` は interface で、既定引数が `Analytics.Noop`。設定ファイルが無い環境では
  `FirebaseAnalyticsTracker.create` が `Noop` を返し、**今までとまったく同じ動作**になる
- **Pro 課金**: `ProBillingManager` の変更は `analytics.log(...)` の追加のみ。商品ID `pro_unlock`・
  買い切り・consume しない、はそのまま。APK に `com.android.vending.BILLING` 権限あり
- **チャンネル保存**: `ChannelInputViewModel` は `PendingUpgrade` に `source` を足しただけ。
  無料1件・入れ替えで記録が消える・Pro で複数、の判断（`ChannelSlotPolicy`）は変えていない
- **再生設定**: `PlayerScreen` が `settings.*` を直接呼ぶのをやめ `viewModel.*` 経由にしたが、
  中では同じ `settings.*` を呼んでいる。**自動再生の既定オフは維持**（`autoPlayStaysOffByDefault`
  テストが機械的に守っている）
- 計測に渡している値は、全12イベントを呼び出し元まで追って確認した。
  **チャンネルID・チャンネル名・動画ID・動画タイトル・メモ・入力URLは1か所も渡していない。**
  `AnalyticsTest.videoIdsAndTitlesAreNeverRecorded` がこれを機械的に検査している

---

## 4. 気づいた点（リリースを止めるものではない）

### 4-1. `lintDebug` のエラーはローカル環境由来

`android/local.properties:1` の `sdk.dir=C:/Users/...` を lint が
`PropertyEscape`（ドライブレターの `:` を escape せよ）と判定してエラーにする。
このファイルは **gitignore 済みで CI には存在しない**ため、CI の `lintDebug` は通っている
（Android Build run `34389243043` 成功）。アプリのコードのエラーは0件。
残り78件は警告で、いずれも今回の変更で増えたものではない。

### 4-2. AdServices 系の権限が2つ入る（`gms.permission.AD_ID` は正しく消えている）

リリース APK のマージ後マニフェストを確認した結果:

- `com.google.android.gms.permission.AD_ID` … **無し**（`tools:node="remove"` が効いている）✅
- `android.permission.ACCESS_ADSERVICES_AD_ID` … **有り**
- `android.permission.ACCESS_ADSERVICES_ATTRIBUTION` … **有り**

後者2つは `play-services-measurement` が自動で足す Privacy Sandbox 用の権限で、
Play の「広告ID」自動チェックが見ている `gms.permission.AD_ID` とは別物。
`google_analytics_adid_collection_enabled=false` も入れてあるので、
**「広告IDを収集しない」の申告は維持してよい**と判断している。

ただし `docs/android-firebase-analytics.md` の確認手順は
「マージ後マニフェストを `AD_ID` で検索」と書いてあり、この2つが引っかかって紛らわしい。
検索語を `com.google.android.gms.permission.AD_ID` にする方が正確。
より厳密にしたければこの2つも `tools:node="remove"` で外せるが、今回は触っていない。

### 4-3. `proguard-rules.pro` の2つ目の keep 指定は実際には効いていない

```
-keep class com.deskflowlabs.channeltimelineviewer.ui.**$* { @android.webkit.JavascriptInterface <methods>; }
```

`**$*` は `$` を含むクラス（＝ネストクラス）にしか当たらない。`PlayerBridge` は
トップレベルのクラスなので**この指定には当たらない**（実際 `PlayerBridge$Companion` だけが
名前を保持し、`PlayerBridge` 本体は `ui.m` に改名された）。

ブリッジを守っているのは1つ目の
`-keepclassmembers class * { @android.webkit.JavascriptInterface <methods>; }` の方で、
**こちらが効いているので実害は無い**（`postMessage` は保持されている）。
コメントの「ブリッジのクラス自体も残す」という説明だけが実態と合っていない。

### 4-4. リリース workflow は テスト・lint を回さない

`android-release.yml` は `bundleRelease assembleRelease` だけを実行する。
また `android-build.yml`（PR/push 用）は `assembleDebug` しか作らないので、
**R8 有効のリリース経路は CI でまったく検証されていない**。
今回はそこをローカルで通したので 1.8 については確認済み。

### 4-5. `versionCode=10` は「1回で成功したら」

`github.run_number` は失敗した実行でも消費される。もし run #10 が
（例えば Secret 未設定で）失敗すると、次の実行は #11 になり **versionCode は 11** になる。
Play 的には増えていれば問題ないが、「1.8 (10)」という表記は変わる。

---

## 5. 残っているユーザー操作

1. **`GOOGLE_SERVICES_JSON_B64` の Secret が登録済みか確認する**（最重要）
   未登録だと workflow は「Firebase の設定ファイルを復元」ステップで**わざと失敗**する
   （`android-release.yml:78-82`）。これは「計測が入らないアプリを気づかず出す」のを
   防ぐための意図した設計。
   こちらから確認できなかった理由: `gh` のトークンが失効している
   （`gh auth status` → `The token in default is invalid`）ため Secrets API が 401 になる。
   `gh auth login` で入れ直せば、以降はこちらで確認・登録まで代行できる。
   登録コマンドは `docs/android-firebase-analytics.md` の 3-3 節（中身は画面に出ない）。

2. **Android Release workflow を手で起動する**（CLAUDE.md の方針どおり、押すのは人）
   - `version_name`: **`1.8`**（入力欄の既定値は `1.0` のまま。**入れ忘れると 1.0 で出る**）
   - `upload_to_play`: 内部テストへ上げるなら **オン**（既定はオフ）
   - `release_notes`: 任意
   - 製品版への昇格・審査への送信は、これまでどおり Play Console で人が行う

なお `origin/main` は `6dc1145` で、ローカルと一致している。**push は不要**。

---

## 6. リリース後に Firebase で確認するイベント

**DebugView**（即時・手元の端末）

```
adb shell setprop debug.firebase.analytics.app com.deskflowlabs.channeltimelineviewer
adb shell setprop debug.firebase.analytics.app .none.   # 解除
```

| 見るもの | 期待 |
| --- | --- |
| `screen_view` | 起動直後に `screen_name=channel_input`。画面を移ると `video_list` / `player` / `about` / `pro` に変わる |
| `channel_open` | チャンネルを開くと出る。`source=url`（共有からなら `share`、保存済みからなら `saved`） |
| **引数の中身** | `channel_open` / `video_open` の引数に**チャンネル名・ID・動画タイトルが無い**こと。ここが一番大事 |
| `video_open` | 一覧から開くと `source=list` ＋ `video_count`（本数）。以降は `navigation` / `auto_advance` |
| `video_finish` | 見終わると `result=auto_next` / `repeat_one` / `stopped` |
| `playback_setting` | 再生設定を切り替えると `setting` と `value` |
| `open_in_youtube` | 「YouTubeで開く」で出る |
| オプトアウト | 「ⓘ このアプリについて」→「利用状況の記録を許可する」をオフ → **以降なにも出なくなる**。再起動してもオフのまま。オンに戻すと次の画面移動から `screen_view` が再開（オンに戻した事自体のイベントは意図的に無い） |

**リアルタイム / 通常レポート**（Firebase コンソール → Analytics）

| 見るもの | 期待 |
| --- | --- |
| リアルタイムの利用者数 | 公開後しばらくして 0 でないこと（＝本番の `google-services.json` が入ったビルドが出ている） |
| `first_open` | 自動収集。更新ではなく新規インストールで増える |
| アプリのバージョン | **1.8** が現れること。ここが 1.7 以下のままなら、計測入りビルドが配信されていない |
| `pro_purchase_start` / `pro_purchase_end` | 課金導線が生きているか。`result=purchased` / `pending` |
| `channel_limit_hit` | 無料の1件制限に当たった回数。Pro の必要性を測る指標 |

通常のレポートは反映まで最大24時間かかる。**公開直後は DebugView で見る**こと。
