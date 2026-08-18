# 提出状況（App Store Connect）

最終確認日: 2026-08-18 / アプリ ID `6792964082` / Bundle ID `com.deskflowlabs.channeltimelineviewer`

App Store Connect の状態は API で確認できます（画面にログインしなくても分かる）。

```
GitHub → Actions → App Store Metadata → Run workflow → mode: status
```

## 済んでいること

| 項目 | 状態 | 方法 |
| --- | --- | --- |
| Apple Developer Program | **加入済み**（Team ID 893UUWYHB8） | — |
| アプリ登録 | 済み（バージョン 1.0 / PREPARE_FOR_SUBMISSION） | — |
| 説明・キーワード・プロモーション文 | **7言語すべて反映済み** | `mode: push` |
| App 名・サブタイトル・プライバシーポリシーURL | **7言語すべて反映済み**（URLは言語別ページ） | `mode: push` |
| サポート/マーケティングURL | 7言語（`/{lang}/support/`・`/{lang}/`） | `mode: push` |
| カテゴリ | 主要 = 教育（EDUCATION） | `mode: category` |
| 年齢制限 | 4+ | ASC 側で設定済み |
| ビルド | **build 25 を 1.0 に紐づけ済み** | `mode: attach-build` |
| スクリーンショット（日本語・6.9インチ） | 5枚登録済み（ホーム/一覧/フィルター/進捗/このアプリについて） | App Store Screenshots ワークフロー |

## 残っていること

| 項目 | 誰が | 内容 |
| --- | --- | --- |
| 審査連絡先 | ユーザー → Claude | 電話番号を Secret `ASC_REVIEW_PHONE` に登録すれば、`mode: review` で連絡先と英語の審査メモを自動投入できる |
| 再生画面のスクショ | ユーザー | CI だと YouTube の bot 確認画面が写るため、実機（TestFlight）で1枚撮る → 追加登録 |
| 価格 | ユーザー | 無料（¥0）を App Store Connect の「価格および配信状況」で設定（API では扱いにくいため画面で） |
| App のプライバシー | ユーザー | 「データを収集していません」を選択（本アプリは端末内保存のみ・解析なし・IDFA 不使用） |
| 提出 | ユーザー | 上記がそろったら「審査へ提出」 |

### App のプライバシーで選ぶ内容（事実ベース）

- **データを収集していません（Data Not Collected）**
  - 端末内にのみ保存: 視聴済み/スキップの videoId・進捗・お気に入りチャンネル・メモ・再生位置・一覧キャッシュ
  - 解析 SDK・広告 SDK・IDFA いずれも不使用。サーバーへの送信なし
  - YouTube Data API / 公式埋め込みプレイヤーの利用は Google 側のポリシーに従う（プライバシーポリシーに記載済み）

## 使えるワークフロー

| ワークフロー | mode / 入力 | 何をするか |
| --- | --- | --- |
| App Store Metadata | `status` | 現状を読むだけ（変更しない） |
| App Store Metadata | `push` | `docs/AppStore/metadata.json` の7言語を反映（`dry_run` で確認可） |
| App Store Metadata | `attach-build` | TestFlight のビルドを提出バージョンに紐づける |
| App Store Metadata | `category` | 主要カテゴリを設定 |
| App Store Metadata | `review` | 審査連絡先＋英語の審査メモ（`review-notes-en.md`）を投入 |
| App Store Screenshots | `screenshots_run_id` | iOS Screenshots の artifact を取り出して登録（`replace` で入れ替え） |
| iOS Screenshots | `languages` | 言語ごとにスクショを撮影 |

> 補足: 初回バージョンでは「このバージョンの新機能（What's New）」を Apple 側が受け付けません。
> スクリプトは初回を判定して自動的に送らないようにしています（更新版では送ります）。
