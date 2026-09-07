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
| `YOUTUBE_API_KEY` | （YouTube Data API v3 のキー） | **Web体験版（`/{lang}/try/`）に必要**。未設定でも他のページは通常どおり動き、体験版だけが「ただいまご利用いただけません」になる |

**いま使っているキー（2026-09-07 作成）**

| 項目 | 値 |
| --- | --- |
| Google Cloud プロジェクト | `channel-timeline-web`（Channel Timeline Viewer Web） |
| キーの表示名 | Channel Timeline Viewer Web trial |
| キーの UID | `1f7109da-feec-4fb0-857f-19c42a3af15c` |
| 制限 | YouTube Data API v3 のみ（リファラー制限なし＝サーバー側から呼ぶため） |
| 手元の控え | `C:\Users\atami\Desktop\api\channel-timeline-web-youtube-key.txt` |

アプリ（iOS / Android）のキーは別プロジェクト `channel-timeline` にある
（`channel-timeline-viewer-android` と `API キー 1`）。**quota はプロジェクト単位なので、
Web が混んでもアプリ側の一覧取得は止まらない。**

値をもう一度取り出したいとき:

```
gcloud services api-keys get-key-string 1f7109da-feec-4fb0-857f-19c42a3af15c ^
  --project=channel-timeline-web --format="value(keyString)"
```

⚠️ `YOUTUBE_API_KEY` について（重要）

- **iOS / Android アプリが使っているキーとは別のキーを作る**。同じキーを使うと、Web の利用で
  アプリ側の日次 quota（10,000 units/日）を使い切ってしまい、アプリで一覧が取れなくなる。
- Google Cloud のプロジェクトごと分けるのがいちばん安全（quota はプロジェクト単位）。
- キーの制限は「APIの制限 → YouTube Data API v3 のみ」にする。
  HTTPリファラー制限は**不要**（ブラウザではなく Cloudflare のサーバー側から呼ぶため）。
- `PUBLIC_` を付けないこと。付けるとブラウザ側のJSに埋め込まれてしまう。
- 変数の種類は **Secret（暗号化）** にしておく。
- ローカルで試すときは `site/.dev.vars`（`.gitignore` 済み）に同じ行を書いて
  `npx wrangler pages dev dist` を使う。

**管理画面を開かずに登録する方法**（一度 `npx wrangler login` しておけば以後ずっと使える）:

```
cd site
npx wrangler pages secret put YOUTUBE_API_KEY --project-name channel-timeline-viewer
```

値の入力を求められるので貼り付ける（画面には出ない）。`--project-name` は
`channeltimeline.jewelrysunflower.com` の CNAME 先（`channel-timeline-viewer.pages.dev`）と同じ名前。
登録済みの名前は `npx wrangler pages secret list --project-name channel-timeline-viewer` で確認できる。
**Secret は次のデプロイから反映される**ので、登録後に push（または再デプロイ）すること。

5. **Save and Deploy** → 数分で `https://<project>.pages.dev` が出来る。ここで表示を確認する。

> **Pages Functions について**
> Web体験版が使う中継は `site/functions/api/youtube.js` に置いてある。
> Cloudflare Pages は **Root directory（＝`site`）の直下の `functions/`** を自動で拾って
> `/api/youtube` として動かす。設定項目は無く、置いてあるだけで有効になる。
> 動いているかは `https://<project>.pages.dev/api/youtube?op=channel&handle=@GoogleDevelopers`
> を開けば分かる（キー未設定なら `{"error":"notConfigured"}` が返る）。

## 3. 独自ドメインをつなぐ

1. 作成した Pages プロジェクト → **Custom domains** → **Set up a custom domain**
2. `channeltimeline.jewelrysunflower.com` を入力
3. Cloudflare が同じアカウント内のゾーンを見つけて、CNAME レコードを自動で追加する（Proxy はオンのまま）
   - 手動で追加する場合: `channeltimeline` → `CNAME` → `<project>.pages.dev`（Proxied）
4. 証明書が発行されるまで数分待つ。`https://channeltimeline.jewelrysunflower.com/` が開けば完了。

## 4. 公開後にやること

- [ ] `https://channeltimeline.jewelrysunflower.com/` が言語ごとに振り分けられるか（英語ブラウザ→ `/en/`、日本語→ `/ja/`）
- [ ] `/ja/privacy/` `/en/privacy/` などが 200 で開くか
- [ ] `/ja/try/`（Web体験版）でチャンネルURLを入れて一覧が出るか。
      出ない場合は `/api/youtube?op=channel&handle=@GoogleDevelopers` の応答を見る
      （`notConfigured` = 環境変数の未設定、`quota` = 日次上限）
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
  Web体験版が何を保存し・何を呼ぶかは、すでに同じ節に7言語で書いてある。
- Web体験版は**1チャンネルまで**。複数チャンネル保存・Web課金・アカウント同期は入れない
  （アプリ版Proの価値を壊さないため）。詳しくは [`../site/README.md`](../site/README.md)。
