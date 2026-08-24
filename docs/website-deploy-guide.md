# 公式サイトの公開手順（Cloudflare Pages ＋ 独自ドメイン）

公開先: **https://channeltimeline.jewelrysunflower.com**
中身: [`site/`](../site/)（Astro・静的・7言語）。アプリのビルドとは独立している。

Cloudflare の管理画面操作とドメインの DNS 設定は、アカウントにログインした人（＝あなた）しか行えないため、
ここだけは手動になる。**1回設定すれば、以後は `main` に push するだけで自動デプロイされる。**

---

## 1. 事前に確認すること

- `jewelrysunflower.com` が Cloudflare で管理されていること（arrows-lite と同じアカウント／ゾーン）。
  - すでに `arrows.jewelrysunflower.com` を Cloudflare Pages で運用しているので、同じゾーンにサブドメインを足すだけ。
- GitHub リポジトリ `kataming/ChannelTimelineViewer` が Cloudflare から見えること（Public なので問題なし）。

## 2. Cloudflare Pages のプロジェクトを作る

1. Cloudflare ダッシュボード → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**
2. リポジトリ `kataming/ChannelTimelineViewer` を選ぶ
3. ビルド設定を次のとおりにする（**ルートディレクトリの指定を忘れないこと**）

| 項目 | 値 |
| --- | --- |
| Project name | `channel-timeline-viewer`（任意。`*.pages.dev` のサブドメインになる） |
| Production branch | `main` |
| Framework preset | `Astro` |
| Build command | `npm run build` |
| Build output directory | `dist` |
| Root directory (advanced) | `site` |

4. 環境変数（Production・任意）

| 変数 | 値 | 備考 |
| --- | --- | --- |
| `PUBLIC_SITE_URL` | `https://channeltimeline.jewelrysunflower.com` | 既定値と同じなので省略可 |
| `PUBLIC_APP_STORE_URL` | （既定でアプリページを指すので省略可） | 既定: `https://apps.apple.com/jp/app/channel-timeline-viewer/id6792964082` |
| `PUBLIC_PLAY_STORE_URL` | （Google Play 公開後に設定） | 未設定の間は Google Play のバッジが「審査中」表示になる |
| `PUBLIC_SUPPORT_EMAIL` | `support@jewelrysunflower.com` | 既定値と同じなので省略可 |

5. **Save and Deploy** → 数分で `https://<project>.pages.dev` が出来る。ここで表示を確認する。

## 3. 独自ドメインをつなぐ

1. 作成した Pages プロジェクト → **Custom domains** → **Set up a custom domain**
2. `channeltimeline.jewelrysunflower.com` を入力
3. Cloudflare が同じアカウント内のゾーンを見つけて、CNAME レコードを自動で追加する（Proxy はオンのまま）
   - 手動で追加する場合: `channeltimeline` → `CNAME` → `<project>.pages.dev`（Proxied）
4. 証明書が発行されるまで数分待つ。`https://channeltimeline.jewelrysunflower.com/` が開けば完了。

## 4. 公開後にやること

- [ ] `https://channeltimeline.jewelrysunflower.com/` が言語ごとに振り分けられるか（英語ブラウザ→ `/en/`、日本語→ `/ja/`）
- [ ] `/ja/privacy/` `/en/privacy/` などが 200 で開くか
- [ ] `/sitemap.xml` と `/robots.txt` が開くか
- [ ] App Store Connect の各言語に URL を入れる（[`AppStore/metadata/`](AppStore/metadata/) 参照）
  - サポートURL: `https://channeltimeline.jewelrysunflower.com/{lang}/support/`
  - マーケティングURL: `https://channeltimeline.jewelrysunflower.com/{lang}/`
  - プライバシーポリシーURL: `https://channeltimeline.jewelrysunflower.com/{lang}/privacy/`
- [ ] アプリの `Resources/Config.plist` の `PRIVACY_POLICY_URL` を新ドメインに切り替える
      （※ 現在は GitHub Pages を指している。切り替えても旧URLは残すので、公開済みビルドは壊れない）
- [ ] Google Search Console にプロパティ（ドメイン `jewelrysunflower.com` 配下）を追加し、sitemap を送信

## 5. 更新の流れ

1. `site/src/i18n/translations.js` を直す（文言の原本はここだけ）
2. `cd site && npm run build && npm run check` で確認
3. `main` に push → Cloudflare Pages が自動でビルド・公開

GitHub Actions（[`.github/workflows/site-build.yml`](../.github/workflows/site-build.yml)）でも同じビルドと点検を回すので、
壊れた状態で push すれば CI が赤くなる。

## 6. 注意

- `player.html`（再生用の中継ページ）は **GitHub Pages のまま**にしておく。公開済みアプリが参照しているため、
  移設すると古いビルドで再生できなくなる。プライバシーポリシーには両方の記載がある。
- サイトは Cookie もアクセス解析も使っていない。導入する場合はプライバシーポリシー
  （`site/src/i18n/translations.js` の `privacy.sections`「このウェブサイトについて」）も同時に直すこと。
