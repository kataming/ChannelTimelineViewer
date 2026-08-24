// サイト全体で使う外部値。公開前に決まらないものは環境変数で差し替えられるようにしている。
export const SITE_URL = (import.meta.env.PUBLIC_SITE_URL || 'https://channeltimeline.jewelrysunflower.com')
  .replace(/\/$/, '');

// App Store のアプリページ（2026-08-24 公開済み）。環境変数があればそちらを優先する。
export const APP_STORE_URL =
  import.meta.env.PUBLIC_APP_STORE_URL || 'https://apps.apple.com/jp/app/channel-timeline-viewer/id6792964082';

// Google Play のアプリページ。審査通過まで空のままにしておくと「審査中」表示になる。
export const PLAY_STORE_URL = import.meta.env.PUBLIC_PLAY_STORE_URL || '';

// 問い合わせ先（サポートページに掲載）。
export const SUPPORT_EMAIL = import.meta.env.PUBLIC_SUPPORT_EMAIL || 'support@jewelrysunflower.com';

// GitHub リポジトリ（公開）。
export const REPOSITORY_URL = 'https://github.com/kataming/ChannelTimelineViewer';

// アプリの表示名（翻訳しない製品名）。
export const APP_NAME = 'Channel Timeline Viewer';
