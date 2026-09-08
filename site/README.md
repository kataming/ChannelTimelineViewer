# Channel Timeline Viewer — 公式サイト（Astro / 7言語）

`https://channeltimeline.jewelrysunflower.com` で公開する静的サイト。iOS アプリ本体とは独立していて、
このフォルダだけで完結する（アプリのビルドには影響しない）。

## 構成

```
site/
  astro.config.mjs        公開URL（PUBLIC_SITE_URL で差し替え可）
  src/config.js           App Store / Google Play URL・問い合わせ先などの外部値
  src/i18n/translations.js 文言の原本（7言語・唯一のソース）
  src/i18n/index.js       言語ヘルパ（パス・辞書・フォールバック）
  src/layouts/Base.astro  <head>（canonical / hreflang / OGP）とスタイル
  src/components/         Header / Footer / LangSelect（言語メニュー） / StoreBadges（ストアのバッジ）
                          ScreenGallery（実機スクリーンショットの横並び）
  src/i18n/screens.js     どの言語のスクリーンショットが揃っているか（自動生成・手で書かない）
  src/i18n/manual/        操作マニュアルの文言（言語ごとに1ファイル）。構造は index.js のコメント参照
  src/i18n/manual/images.js  章ごとの画面写真の一覧（自動生成・手で書かない）
  public/manual/<機種>/<言語>/  マニュアルの画面写真（幅400px・WebP）
  public/screens/<言語>/  スクリーンショット（幅440px・WebP）
  src/pages/
    index.astro           / → ブラウザの言語で振り分け（JS 無しなら英語へ）
    [lang]/index.astro    トップ（機能・使い方・FAQ）
    [lang]/try.astro      Web体験版（1チャンネル無料）※下記
    [lang]/manual.astro   操作マニュアル（iPhone / Android の違いは項目の印で示す）
    [lang]/support.astro  サポート
    [lang]/privacy.astro  プライバシーポリシー
    sitemap.xml.js        言語 × ページの全URL
    robots.txt.js
  src/components/TrialApp.astro  Web体験版の中身（トップのヒーローと /try/ で共用）
  src/i18n/trial.js       Web体験版の文言（7言語）。アプリの訳を流用している
  src/trial/              Web体験版のブラウザ側コード（下記）
  functions/api/youtube.js  Cloudflare Pages Functions（APIキーを隠すための中継）
  scripts/check-build.mjs dist/ の点検（言語・hreflang・翻訳漏れ）
  scripts/test-trial.mjs  Web体験版の点検（URL解析・計算・画面と処理の対応・7言語）
```

言語は `en / ja / zh / es / de / fr / ko` の7つ。URL は `/{lang}/...`、`zh` の hreflang は `zh-Hans`。

## 開発

```
cd site
npm install
npm run dev      # http://localhost:4321
npm run build    # dist/ に出力
npm run check    # dist/ を点検（build のあとに実行する）
npm test         # Web体験版の点検（ビルド不要）
```

Web体験版の中継（`/api/youtube`）は Astro の dev サーバーでは動かない。動かして試すときは
Cloudflare Pages と同じ環境を使う:

```
cd site
echo YOUTUBE_API_KEY=<キー> > .dev.vars   # ← .gitignore 済み。絶対にコミットしない
npm run build
npx wrangler pages dev dist --port 8788        # = npm run dev:api（wrangler が入っていれば）
```

## 環境変数（任意）

| 変数 | 用途 | 既定 |
| --- | --- | --- |
| `PUBLIC_SITE_URL` | canonical / hreflang / sitemap の絶対URL | `https://channeltimeline.jewelrysunflower.com` |
| `PUBLIC_APP_STORE_URL` | App Store バッジの遷移先 | `https://apps.apple.com/jp/app/channel-timeline-viewer/id6792964082` |
| `PUBLIC_PLAY_STORE_URL` | Google Play バッジの遷移先。空のあいだは「審査中」のバッジになる。**入れるとマニュアル1章の Android の項目も「Google Play から入れる」へ自動で変わる** | 空（審査中） |
| `PUBLIC_SUPPORT_EMAIL` | サポート／プライバシーの連絡先 | `support@jewelrysunflower.com` |
| `YOUTUBE_API_KEY` | **Web体験版が使う YouTube Data API v3 のキー（サーバー側・秘密）**。未設定でもサイトは壊れず、体験版だけが「ただいまご利用いただけません」になる | なし |

⚠️ `YOUTUBE_API_KEY` は **iOS / Android アプリが使っているキーとは別のキー**にする。
Web の利用でアプリ側の日次 quota（10,000 units/日）を使い切ってしまわないようにするため。
これだけは `PUBLIC_` を付けない（付けるとブラウザ側に埋め込まれてしまう）。

## スクリーンショットを差し替えるとき

トップの「使用イメージ」に出している画像は、App Store 提出用に撮ったものと同じ。

1. GitHub Actions の **iOS Screenshots** を実行する（言語を選べる）。artifact
   `app-store-screenshots-<言語>` を `build/screenshots-site/<言語>/` に展開する。
2. `python scripts/prepare_site_screenshots.py --src build/screenshots-site`
   （幅440pxのWebPに変換して `site/public/screens/` に置き、`src/i18n/screens.js` を作り直す）
3. 変換前に**必ず目で確認する**。CI のシミュレーターは YouTube 側に
   「Sign in to confirm you're not a bot」を出されることがあり、その画像は載せられない。
   再生画面（4枚目）は `docs/AppStore/screenshots/<言語>/04-player-device.png` を自動で優先する。
4. 撮れなかったカットはその言語だけ非表示になる。枚数が足りない言語は英語版の画像を出す。

キャプションは `src/i18n/translations.js` の `shots`（App Store のキャプションと同じ文言）。

## マニュアルの画面写真を作り直すとき

章ごとに1枚、実機・シミュレーターで撮った本物の画面を載せている（イラストは使わない）。

```
python scripts/prepare_manual_images.py
```

- iPhone は `build/screenshots-site/<言語>/` と `build/shots-dl/<言語>/`、
  再生画面は `docs/AppStore/screenshots/<言語>/04-player-device.png` を使う。
- Android は `docs/PlayStore/screenshots/<Playのロケール>/` を使う（リポジトリに入っている）。
- 幅400pxのWebPにして `site/public/manual/` に置き、`src/i18n/manual/images.js` を作り直す。
- **その言語の写真が無い章は、画像なしで出る**（別言語の画面は出さない。説明と食い違うため）。

## Pro の価格を出し直すとき

料金セクションの Pro カードには、**その言語の国の現在価格**を出している。
数字は手で書かず、ストアから取り直す:

```
cd ..
set PLAY_SERVICE_ACCOUNT_FILE=<play-service-account.json のパス>   # PowerShell は $env:...
python scripts/fetch_store_prices.py
```

- `site/src/i18n/prices.js` を作り直す（**自動生成なので手で編集しない**）
- Google Play は API から、App Store は API（`ASC_KEY_ID` 等がある場合）か、
  無ければ**商品ページに実際に表示されている金額**から取る
- 表示は `src/components/ProPrice.astro`。金額の書式は `Intl.NumberFormat` で言語ごとに作る

**両ストアの金額が違うときは、ストア名を添えて両方出す**（片方だけだと誤りになるため）。
2026-09-08 に Google Play をユーロ圏 €5.99・韓国 ₩7,700 へ上げて App Store と揃えたので、
いまは中国本土をのぞいて1つだけ表示される。

| | App Store | Google Play |
| --- | --- | --- |
| en（米国） | $4.99 | $4.99 |
| ja（日本） | ¥800 | ¥800 |
| zh（中国本土） | ¥38.00 | （Google Play 未提供） |
| es / de / fr（ユーロ圏） | 5,99 € | 5,99 € |
| ko（韓国） | ₩7,700 | ₩7,700 |

なぜ揃える必要があったか: Apple の価格表は**税込みで組まれていて** $4.99 相当が €5.99、
Google Play は $4.99 を**自動換算**して €4.99 だった。税を抜くと Android だけ手取りが約2割低く、
サイトに両方並べると理由の分からない差に見えるため、Play 側を上げて合わせた
（買い切りなので既存の購入者に影響はない）。ユーロ表記でも VAT の無いアフリカ諸国（€4.27）と
サンマリノ・バチカン（€4.29）は、Apple が USD で売っていて比べる相手がいないので変えていない。

**ストアで価格を変えたら、このスクリプトを流し直して push する**（サイトだけ古い金額のまま
残らないように）。`npm run check` は7言語すべてに価格が出ているかを見るので、
取得に失敗したまま公開することはない。

## 文言を直すとき

`src/i18n/translations.js` だけを直す（ページ側に文言を書かない）。7言語すべてに同じキーがあること。
英語のキーが他言語ページに漏れていれば `npm run check` が失敗する。

## 公開

Cloudflare Pages に接続する手順は [`../docs/website-deploy-guide.md`](../docs/website-deploy-guide.md) を参照。

## Web体験版（`/{lang}/try/`）

公式サイト上で **1チャンネルだけ**を実際に使える無料体験版。位置づけは
「PCで価値を試す入口 → App Store / Google Play への導線」で、スマホアプリの代わりではない。

**同じものを2か所に置いている**（中身も保存先も同じなので、ヒーローで試した続きを `/try/` で見られる）:

| 置き場所 | variant | 見た目 |
| --- | --- | --- |
| トップページのヒーロー右側 | `phone` | スマホの枠の中。**静止画ではなく実際に動く**。一覧画面と再生画面を行き来する |
| `/{lang}/try/` | `full` | 横に広く、一覧とプレイヤーを左右に並べる |

### 見た目は「アプリの画面」に合わせる（2026-09-08）

最初は Web らしい見た目（ピル型のボタンが折り返す・チェックボックス・全部が縦一列）で作ったが、
**「ぜんぜんスマホと違う。これなら静止画のほうがまし」**という指摘を受けて作り直した。
次はアプリの画面に合わせてあるので、変えるときは実機のアプリと見比べること:

- **上部バー**（戻る `‹` / チャンネル名 / `⋯` メニュー）。チャンネルの操作（新着を確認・
  再読み込み・別のチャンネル・削除）は `⋯` の中に入れて、ボタンを並べない
- **一覧画面と再生画面を分ける**（`phone` のみ。`#ctv[data-screen]` で切り替え）。
  行を押すと再生画面へ、`‹` で一覧へ戻る
- **iOS 風のスイッチ**（`.ctv-switch`）。チェックボックスは使わない
- **丸い移動ボタンを横一列**（最初へ / 前へ / ⋯ / 次へ / 最後へ）。
  視聴済み・スキップ・最初から再生は真ん中の `⋯` の中
- **全幅の「YouTubeで開く」**、アイコン付きの**メモ**見出し
- 一覧の行は「サムネイル・タイトル・日付・緑のチェック・`›`」

#### 文字の大きさ（2026-09-08 追記）

Web の既定サイズのままだと、枠に対して文字が大きすぎて「サイトをスマホ型に押し込んだもの」に見える。
参考にした実機スクリーンショット（幅270px）から、**内容の幅に対する比率**を測って合わせてある:

| | アプリ（270px幅） | 枠（内容幅 約228px） |
| --- | --- | --- |
| 動画タイトル | 約3.5% | 11.5px |
| 本文（設定の見出し等） | 約3.2% | 10px |
| 説明・日付 | 約2.4% | 8.5px |
| 移動ボタンの文字 | 約2.4% | 8px |

`[data-variant='phone']` の中で個別に `font-size` を指定している。`full`（/try/）は
読みやすさ優先で通常サイズのままなので、**片方だけ変えると崩れる**。

#### 「YouTubeで開く」まで1画面に収める

アプリの再生画面は、動画からメモの手前までが**スクロールなしで1画面に入る**。体験版もそれに合わせてある:

- 動画タイトルは1行で切る（アプリも1行）
- 繰り返しは上部バーのバッジ（アプリの「ALL」と同じ位置）にして、設定カードから出した
- 「続きから再生する」の説明文は枠の中では出さない
- 枠の高さは `clamp(420px, calc(100svh - 118px), 680px)`。
  `118px` は「ヘッダー60 + ヒーローの上余白16 + 下のリンク約26 + 余裕」。
  **ヒーローの余白を増やすとスマホの下が切れる**ので、増やすならこの数字も直すこと。

収まっているかは実際に測って確かめられる（窓の高さ 665 / 800 / 945 で確認済み）。
崩したときは「YouTubeで開く」が下にはみ出すので、そこを見れば分かる。

⚠️ `Base.astro` の共通スタイルに `details { border-bottom; padding: 14px 0 }`（FAQ用）があり、
メニューの `<details>` に効いてしまう。`trial.css` の先頭で打ち消しているので消さないこと。

ヒーローのスマホは高さを `clamp(420px, calc(100svh - 150px), 660px)` にしてあり、
ページの一番上で**スマホ全体が画面に収まる**（切れない）ようにしている。
幅は高さから決める（≒9:19.5）ので、中身の量で幅が変わらない。
画面幅 900px 以下ではヒーローの体験版は畳み、`/try/` へ誘導する。

- 制限するのは**保存できるチャンネル数（1件）だけ**。その1件の中では何も削らない
  （古い順/新しい順・視聴済み・スキップ・進捗・メモ・続きから再生・自動再生・繰り返し）
- 2チャンネル目を保存しようとすると **アプリ版Proの案内**を出す
  （「Proの内容を見る」を「入れ替える」より上に置き、消えることは赤字・太字で警告する）
- **Web課金・アカウント・同期・複数チャンネル保存は実装しない**（アプリ版Proの価値を壊さないため）
- 記録は**そのブラウザの localStorage だけ**。サーバーには何も送らない
- 再生は **YouTube 公式の埋め込みプレイヤー**。ダウンロード・広告回避・
  バックグラウンド再生・スクレイピングはしない

### 構成

```
src/components/TrialApp.astro  画面の中身（静的HTML・7言語）。CSS と起動もここが持つ
                               ので、使う側は <TrialApp code variant /> を置くだけでよい
src/pages/[lang]/try.astro  体験版のページ（variant="full"）
src/pages/[lang]/index.astro トップ。ヒーローに variant="phone" を置いている
src/i18n/trial.js           文言（7言語）。アプリの Localization/strings.json の訳を流用
src/trial/resolve.js        入力URLの解析（アプリの ChannelResolver と同じ規則）
src/trial/model.js          並べ替え・絞り込み・進捗・自動再生の行き先・再生位置の規則
src/trial/storage.js        localStorage（チャンネル1件 / 一覧 / 視聴状態 / 再生設定）
src/trial/api.js            /api/youtube を呼ぶところ
src/trial/player.js         公式 IFrame Player のラッパー（nearEnd の先回りを含む）
src/trial/app.js            画面との配線
functions/api/youtube.js    中継（APIキーはここだけが持つ・エッジにキャッシュ）
```

見た目の切り替えは `#ctv[data-variant]` だけで行い、HTML と id は2か所で完全に同じにしてある。
そのため `app.js` は分岐を持たない（唯一の例外は「続きを描く」判定の基準で、
`phone` のときだけスクロールするのが枠の中になるため `.ctv-scroll` を見る）。

`app.js` が触る id が `TrialApp.astro` に無い、使っている文言キーが7言語のどれかに無い、
といった食い違いは `npm test` が落ちて教えてくれる。

### quota について

中継が通すのは `channels.list` / `playlistItems.list` / `videos.list`（各 1 unit）だけ。
古いカスタムURL（`youtube.com/SomeName`）でハンドルとして引けなかったときだけ
`search.list`（100 unit）を1回使う。同じ問い合わせが Google まで届かないよう、
成功した応答はエッジ（Cache API）に置いてから返す（チャンネル12時間・一覧6時間）。

1チャンネルの初回読み込みは「50件で1 unit」なので、1000本のチャンネルで 20 units。
上限は 100ページ（5000本）で、それを超えるチャンネルは先頭までを表示して案内を出す。

### 再生について

アプリ（iOS / Android）は `docs/player.html` という中継ページ越しに公式プレイヤーを出しているが、
**Web体験版は自分のオリジンから直接 IFrame Player API を読み込む**（Referer の問題が起きないため）。
`docs/player.html` は公開済みアプリ専用なので、体験版のために変更しないこと。

#### プレイヤーの大きさ（2026-09-08 追記・2つのつまずき）

1. **`<iframe>` の既定の高さ 150px**
   IFrame API は iframe に `height="100%"` を付けるが、入れ物（`#ctv-player-mount`）に
   高さが無いと `100%` が解決できず、既定の 150px のままになる。
   枠（16:9）よりはみ出したぶんが切り取られて、**映像がずれて拡大されたように見えた**。
   `#ctv-player-mount { width: 100%; height: 100% }` で入れ物に高さを持たせて解決。
   `npm test` では拾えないので、変えたら実際に測ること（枠と iframe の寸法が一致していればよい）。

2. **公式プレイヤーは狭いほど操作ボタンを大きく描く**
   スマホ枠の中は約213pxで、そのまま描かせると実機（約390px）より操作ボタンが
   ずっと大きくなり、これも「拡大されている」ように見えた。
   そこで **390px 幅で描かせて CSS で縮小**している:
   `#ctv-player-mount` を 390×219.375px に固定し、`transform: scale(var(--ctv-player-scale))`。
   縮小率（枠の幅 ÷ 390）は `app.js` の `updatePlayerScale()` が入れる
   （画面切り替え・動画切り替え・窓のリサイズ・全画面の切り替えで再計算）。
   全画面のあいだは `[data-fullscreen='true']` で等倍に戻す。
   `full`（/try/）は十分な幅があるので縮小しない。
