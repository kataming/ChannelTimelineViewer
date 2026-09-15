# Watch Queue モード（外部流入専用の第2再生モード）

- 決定日: 2026-09-16（ユーザーの確定仕様）
- 送り手: Chrome 拡張 **YouTube Watch Queue**（別プロジェクト `youtube-watch-queue`）
- 受け手: 公式サイトの Web版スマホVIEWER（`site/src/components/TrialApp.astro` の `variant="phone"`）

## 位置づけ（守ること）

Channel Timeline Viewer のメイン用途は **「YouTubeチャンネルを順番に見る」** のまま変えない。
Watch Queue モードは、**正しい Queue Launch Payload を持ったリンクで来たときだけ**起動する第2の再生モード。

通常サイトには **何も足さない**:

- YouTube Watch Queue・Watch Queue 機能・Chrome 拡張の紹介／説明／リンク
- トップページの CTA、通常ナビゲーションの項目、通常スマホVIEWERの Watch Queue ボタン
- sitemap・検索への掲載（Watch Queue のページは `noindex`、`src/i18n/pages.js` の `PAGES` に入れない）

`npm run check` が、通常ページ（sitemap の全ページ・ルート・404）に Watch Queue の痕跡が無いことを点検する。
`npm test` が、通常ページのソースから Watch Queue を参照していないことを点検する。

## Queue Launch Contract V1

```
https://channeltimeline.jewelrysunflower.com/watch-queue#v=1&ids=VIDEO_ID1,VIDEO_ID2,...
```

| 項目 | 規則 |
|---|---|
| 置き場所 | URL のフラグメント（`#` 以降）。ブラウザはフラグメントをサーバーへ送らない |
| `v` | `1` 固定。それ以外（無し・`2` など）は **無効なキュー**として扱う（将来の版を誤解釈しない） |
| `ids` | YouTube の動画ID（`/^[A-Za-z0-9_-]{11}$/`）をカンマ区切り。**並び順＝再生順** |
| 不正なID・重複 | 捨てる。残りの順番はそのまま守る |
| 上限 | 500 本。超えた分は無視し「最初の500本だけを表示しています」と出す |
| 有効なIDが0本 | 「キューが空か、リンクが正しくありません」 |
| 保存 | しない（キューはURLにだけある）。体験版の保存（チャンネル・視聴記録・メモ）にも触らない |

送り手（拡張）は同じ規則で URL を作る（`youtube-watch-queue/src/shared/queueLaunch.ts`）。
解析は `site/src/trial/queue-model.js` の `parseQueueHash()`（`npm test` で点検）。

## 入口と言語

1. `/watch-queue`（Cloudflare Pages が `/watch-queue/` に揃える。フラグメントはブラウザが保つ）
2. `/watch-queue/` … **ルート（`/`）と同じ言語の振り分け**（`src/components/LangRedirect.astro` を共用）で
   `/{lang}/watch-queue/#…` へ。順番は「言語切替で保存した言語（`ctv-lang`）→ ブラウザの言語 → 英語」。
   `keepHash` で `#` 以降を引き継ぐ（meta refresh は付けない＝付けるとキューが消える）
3. `/{lang}/watch-queue/` … 7言語（`en / ja / zh / es / de / fr / ko`）の静的ページ。
   言語切替リンク（ヘッダー・フッター）には、ページ側の処理で今の `#` を付けてあるので、切り替えてもキューを持ったまま移る。
   Watch Queue 独自の言語判定は作っていない

## 画面（既存スマホVIEWERの再利用）

`/{lang}/watch-queue/` は `TrialApp variant="phone" mode="queue"` を置くだけ。新しいプレイヤー画面は作っていない。

| 使うもの（体験版と共通） | Watch Queue モードでの使い方 |
|---|---|
| 上部バー・戻る | タイトルは「Watch Queue」 |
| 一覧・「次に見る」カード・件数 | キューの順番のまま。件数は「3本」「3 videos」 |
| 公式プレイヤー（`player.js`）・終わりぎわの先回り | そのまま |
| 最初へ／前へ／次へ／最後へ | そのまま（キューの中を移動） |
| 現在位置 | 体験版の `ui.positionFormat`（「第2本目 / 全8本」「#2 of 8」） |
| 自動再生スイッチ | **そのまま（既定オフ・体験版と設定を共有）**。オンのときだけ終了後に次へ進む |
| 再生終了の案内「次の動画を再生」 | 自動再生オフのとき |
| 「最初から再生」 | キューを先頭からもう一度 |

キューでは使わないもの（CSS/JS で隠す）: 進捗バー、並び替え、絞り込み、⋯メニュー（新着確認・チャンネル操作）、
視聴済み・スキップの操作、メモ、繰り返し、未視聴のみ、続きから再生。

### 再生の流れ

```
Queue 1本目 → 終了 → Queue 2本目 → 終了 → … → 最後の動画 → 「キューの再生が完了しました」
```

- 自動再生オン: 終了（の0.5秒前の先回り）で次の動画へ。
- 自動再生オフ: 終了したら「再生が終了しました。次の動画: ○○ ［次の動画を再生］」で止まる。
  ⚠️ **連続再生は「ユーザーが明示的にオンにしたときだけ」**（CLAUDE.md の連続再生の方針）を Watch Queue でも守る。
- 再生できない動画（Data API が返さない＝非公開・削除済み／埋め込み不可／プレイヤーのエラー）:
  「この動画は再生できません」を出す。自動再生オンなら2.5秒後に次へ、オフなら［次の動画を再生］で進む。
- 最後の動画が終わると「キューの再生が完了しました」［最初から再生］。

## 文言（7言語）

- 新しい文言は `site/src/i18n/watchQueue.js`（Watch Queue のページだけが読み込む）。
- 同じ意味の文言が体験版にあるものは**新しく作らず** `trial.js` の `ui.*` を使う:
  前へ `ui.prev`／次へ `ui.next`／最初へ・最後へ／最初から再生 `ui.restart`／現在位置 `ui.positionFormat`／
  視聴済み `ui.watched`／次に見る `ui.upNextFormat`／再生終了 `ui.endedTitle`・`ui.endedPlayNext`／
  自動再生 `ui.autoplay*`／読み込み中 `ui.loading`／通信・上限エラー `ui.errNetwork`・`ui.errQuota`／タイトルなし `ui.untitled`。
- 「Watch Queue」は機能名として訳さない（Pro と同じ扱い）。
- `npm test` が7言語のキー・空欄・差し込み数を、`npm run check` が各言語ページに正しい訳が渡っていることを点検する。

## 動画情報の取得（中継）

タイトル・チャンネル名・公開日・埋め込み可否は、体験版と同じ中継 `functions/api/youtube.js` の
`op=videoInfo&ids=…`（`videos.list`・50件ずつ・1 unit・エッジで6時間キャッシュ）で取る。
中継に渡すのは動画IDだけ。中継が使えないとき（キー未設定など）はタイトルが出ないだけで、再生はそのまま続けられる。
プライバシーポリシー（`translations.js` の `privacy` 10章）の中継の説明は、特定の機能名を出さずに
「表示するチャンネル・プレイリスト・動画の識別子だけを渡す」と書いてある。

## 点検・確認

- `cd site && npm test && npm run build && npm run check`
- 本番の通し確認（拡張 Popup → 本番VIEWER → キュー順再生・7言語・言語切替・通常ページに痕跡なし）は
  `youtube-watch-queue/scripts/e2e_watch_queue.mjs --base https://channeltimeline.jewelrysunflower.com --extension`
