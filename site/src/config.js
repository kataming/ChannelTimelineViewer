// サイト全体で使う外部値。公開前に決まらないものは環境変数で差し替えられるようにしている。
export const SITE_URL = (import.meta.env.PUBLIC_SITE_URL || 'https://channeltimeline.jewelrysunflower.com')
  .replace(/\/$/, '');

// App Store のアプリページ。審査通過まで確定しないので、未設定のうちは「準備中」表示にする。
export const APP_STORE_URL = import.meta.env.PUBLIC_APP_STORE_URL || '';

// 問い合わせ先（サポートページに掲載）。
export const SUPPORT_EMAIL = import.meta.env.PUBLIC_SUPPORT_EMAIL || 'support@jewelrysunflower.com';

// GitHub リポジトリ（公開）。
export const REPOSITORY_URL = 'https://github.com/kataming/ChannelTimelineViewer';

// アプリの表示名（翻訳しない製品名）。
export const APP_NAME = 'Channel Timeline Viewer';
