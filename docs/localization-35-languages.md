# アプリ画面の 35 言語化（2026-10-01）

## 決めたこと（ユーザー判断）

| 対象 | 言語数 |
| --- | --- |
| アプリ本体の画面（iOS / Android） | 35 |
| ストアのタイトル・短い説明・詳しい説明・新機能 | App Store 33 / Google Play 35 |
| スクリーンショット・チュートリアル画像 | 7（ほかの言語には英語の画像を出す） |
| ヘルプ・規約・プライバシーポリシー・公式サイト | 7 |

- ポルトガル語はブラジル（pt-BR）のみ
- App Store に言語が無いフィリピン語（fil）とズールー語（zu）は、App Store には載せない（アプリ画面と Google Play は対応）
- 翻訳は Claude。新しく足した 28 言語は**ネイティブの確認をまだ受けていない**

## 出したもの

- iOS 1.3.0（build 39）… 2026-10-01 に審査へ提出（WAITING_FOR_REVIEW）
- Android 1.15（versionCode 19）… 2026-10-01 に審査へ送信
- どちらも「チャンネル内検索」と「35 言語」を含む

## 仕組み

- 原本は `Localization/strings.json`（1 キーに 35 言語）。`build_localizations.py` / `build_android_strings.py` で生成
- **1 言語でも訳が欠けると生成が失敗する**（以前は日本語で埋めていた。35 言語では別言語の端末に日本語が出るので止めた）
- ストアの原本は `docs/AppStore/metadata.json`（33 言語）と `docs/PlayStore/metadata.json`（35 言語）
- スクショは 7 言語ぶんだけ作る。ほかの言語には英語の画像を入れる
  - App Store: `asc_appstore_metadata.py --mode push` の最後に `fill_screenshots` が自動で入れる
    （主要言語が日本語なので、入れないと日本語の画面が見える）
  - Google Play: `play_publish.py` の `image_sets` が en-US の画像を使う

## まだ済んでいないこと（人の確認が要る）

新しい 28 言語は機械検査（変数・改行・固有名詞・文字数）だけ通してある。意味と自然さは未確認。

| 優先 | 言語 | 見てほしいところ |
| --- | --- | --- |
| 高 | ズールー語（zu） | アプリ向けの定まった言い回しが少ない。字幕・共有シート・クリップボードなどの語を選んで訳した |
| 高 | アラビア語（ar）・ウルドゥー語（ur） | 右から左の表示。画面が左右反転したときに文言（「右上の…」など）と食い違わないか、実機で見る |
| 中 | 全言語 | 共有シートのメニュー名（「その他」「編集」「お気に入り」）は推測。各言語の iOS / Android の実際の表記と合うか |
| 中 | カンナダ語（kn） | 「元に戻す」（player.nav.undo）と「キャンセル」（common.cancel）が同じ語 |
| 低 | タイ語（th） | ストア説明の日付例が仏暦（2569）。アプリの表示と揃っているか |

直すときは `Localization/strings.json`（画面）と `docs/AppStore/metadata.json` / `docs/PlayStore/metadata.json`（ストア）を直し、
生成スクリプトを流してからコミットする。
