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
  public/screens/<言語>/  スクリーンショット（幅440px・WebP）
  src/pages/
    index.astro           / → ブラウザの言語で振り分け（JS 無しなら英語へ）
    [lang]/index.astro    トップ（機能・使い方・FAQ）
    [lang]/support.astro  サポート
    [lang]/privacy.astro  プライバシーポリシー
    sitemap.xml.js        言語 × ページの全URL
    robots.txt.js
  scripts/check-build.mjs dist/ の点検（言語・hreflang・翻訳漏れ）
```

言語は `en / ja / zh / es / de / fr / ko` の7つ。URL は `/{lang}/...`、`zh` の hreflang は `zh-Hans`。

## 開発

```
cd site
npm install
npm run dev      # http://localhost:4321
npm run build    # dist/ に出力
npm run check    # dist/ を点検（build のあとに実行する）
```

## 環境変数（任意）

| 変数 | 用途 | 既定 |
| --- | --- | --- |
| `PUBLIC_SITE_URL` | canonical / hreflang / sitemap の絶対URL | `https://channeltimeline.jewelrysunflower.com` |
| `PUBLIC_APP_STORE_URL` | App Store バッジの遷移先 | `https://apps.apple.com/jp/app/channel-timeline-viewer/id6792964082` |
| `PUBLIC_PLAY_STORE_URL` | Google Play バッジの遷移先。空のあいだは「審査中」のバッジになる | 空（審査中） |
| `PUBLIC_SUPPORT_EMAIL` | サポート／プライバシーの連絡先 | `support@jewelrysunflower.com` |

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

## 文言を直すとき

`src/i18n/translations.js` だけを直す（ページ側に文言を書かない）。7言語すべてに同じキーがあること。
英語のキーが他言語ページに漏れていれば `npm run check` が失敗する。

## 公開

Cloudflare Pages に接続する手順は [`../docs/website-deploy-guide.md`](../docs/website-deploy-guide.md) を参照。
