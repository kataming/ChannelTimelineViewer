# Channel Timeline Viewer — Android 版

iOS 版と同じ考え方の Android アプリ（Kotlin / Jetpack Compose）。
**翻訳・再生の中継ページ・規約順守の方針は iOS 版と共通**で、コードだけを各プラットフォーム向けに書いている。

## 作りの対応表

| 役割 | iOS（Swift） | Android（Kotlin） |
| --- | --- | --- |
| URL 解析 | `Services/ChannelResolver.swift` | `network/ChannelResolver.kt` |
| 共有テキストの解析 | `Services/SharedLinkParser.swift` | `network/SharedLinkParser.kt` |
| API クライアント | `Services/YouTubeAPIClient.swift` | `network/YouTubeApiClient.kt` |
| 端末内保存 | `Services/*Store.swift`（UserDefaults） | `data/Stores.kt`（SharedPreferences） |
| 再生ロジック | `ViewModels/PlayerViewModel.swift` | `viewmodel/PlayerViewModel.kt` |
| 一覧ロジック | `ViewModels/VideoListViewModel.swift` | `viewmodel/VideoListViewModel.kt` |
| 画面 | `Views/*.swift`（SwiftUI） | `ui/*.kt`（Compose） |
| プレイヤー | `Views/YouTubePlayerWebView.swift`（WKWebView） | `ui/YouTubePlayerWebView.kt`（WebView） |

再生はどちらも **GitHub Pages の中継ページ**（`docs/player.html`）を読み込み、その中に公式 IFrame Player を埋め込む。
中継ページは iOS（`window.webkit.messageHandlers`）と Android（`window.ytAndroid`）の両方へ通知を送る。

## 守っている制約（iOS 版と同じ）

- ダウンロード・オフライン保存をしない
- 独自プレイヤーで再生しない（公式の埋め込みプレイヤーのみ）
- 広告回避・再生制限の回避をしない
- スクレイピングをしない（一覧は YouTube Data API v3）
- バックグラウンド再生をしない（再生中だけ画面を消さない設定にしている）
- 自動再生は**既定オフ**で、ユーザーがトグルをオンにしたときだけ、開いている一覧の次の動画へ進む

## ビルド

```
cd android
./gradlew testDebugUnitTest    # ユニットテスト
./gradlew assembleDebug        # デバッグ APK
./gradlew lintDebug            # lint
```

APIキーは**リポジトリに入れない**。次のどちらかで渡す（未設定でもビルドは通り、アプリが警告を出す）。

- `android/local.properties` に `YOUTUBE_API_KEY=...`（各自の端末用。gitignore 済み）
- 環境変数 `YOUTUBE_API_KEY`（CI 用。GitHub Secrets から渡している）

`local.properties` には Android SDK の場所も書く（Android Studio が自動で作る）。

```
sdk.dir=C:/Users/<ユーザー名>/AppData/Local/Android/Sdk
```

## 文言（7言語）

原本は iOS と共通の [`../Localization/strings.json`](../Localization/strings.json)。
生成はリポジトリのルートから:

```
python scripts/build_android_strings.py
```

`res/values/`（英語＝既定）と `values-ja` `values-zh-rCN` `values-es` `values-de` `values-fr` `values-ko` を書き出す。
CI は「strings.json から生成したものと一致するか」を検査するので、**手で strings.xml を編集しない**こと。

## CI

[`.github/workflows/android-build.yml`](../.github/workflows/android-build.yml)。
macOS ランナーが要らないので Linux で速く回る。テスト・APK ビルド・lint と、翻訳の整合性を確認する。

## まだやっていないこと

- Google Play への公開（アカウント登録・ストア掲載情報・署名鍵）
- リリースビルドの署名設定（現在は debug のみ）
- 画面の作り込み（iOS 版のスワイプ操作は、Android では行の長押し＝スキップ切り替えにしている）
