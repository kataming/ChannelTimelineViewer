import { defineConfig } from 'astro/config';

// 公開ドメインは環境変数で差し替えられるようにしておく（Cloudflare Pages のプレビュー環境など）。
const SITE_URL = (process.env.PUBLIC_SITE_URL || 'https://channeltimeline.jewelrysunflower.com')
  .replace(/\/$/, '');

export default defineConfig({
  site: SITE_URL,
  // /en/ → /en/index.html。言語ごとに固有のURLを持たせる（hreflang / SEO のため）。
  build: { format: 'directory' },
  trailingSlash: 'always',
});
