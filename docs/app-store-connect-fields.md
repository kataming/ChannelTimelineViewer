# App Store Connect 入力項目 下書き

> App Store Connect に入力する各項目の下書き。位置づけは **「時系列視聴・進捗管理・学習補助アプリ」**。
> 「公式」「YouTube公式」と誤認させない／ロゴを使わない。実際の API キーは記載しない。
> 説明文の本文は [`app-store-description.md`](app-store-description.md) を参照（ここでは入力欄ごとに整理）。

## App 情報（App Information）
- **App名（Name）**: Channel Timeline Viewer
- **サブタイトル（Subtitle, 30字）**: チャンネル動画を古い順で学習・整理
- **プライマリ言語**: 日本語
- **カテゴリ（Primary）**: 教育（Education）※または ユーティリティ（Utilities）
- **カテゴリ（Secondary）**: なし（任意）
- **コンテンツ著作権（Content Rights）**: サードパーティのコンテンツ（YouTube動画）を含む旨は、公式埋め込み
  プレイヤーで表示するのみ。権利は各動画の権利者に帰属。
- **年齢制限（Age Rating）**: アンケートに回答。本アプリ自体は不適切表現なし。ただし YouTube の動画は
  ユーザー入力チャンネルに依存するため、「Webコンテンツ/制限のないWebアクセス」相当に該当しうる
  → 質問に正直に回答（17+ になる可能性あり。要確認）。

## 価格（Pricing）
- **価格**: 無料（Free）※初回公開時
- **アプリ内課金**: なし（Product ID を作らない）
- **サブスクリプション**: なし
- 収益化は**本体価格の変更のみ**で行う（無料 → $4.99 → $9.99）。
  値上げの目安と手順は [`monetization-plan.md`](monetization-plan.md) を参照。
  値上げ後も、無料期間中に入手したユーザーの機能は制限しない。

## バージョン情報（Version Information / ローカリゼーション）
- **プロモーションテキスト（170字）**: [`app-store-description.md`](app-store-description.md) のプロモーション文
- **説明（Description）**: 同上の日本語説明文（英語ローカライズは英語説明文）
- **キーワード（100字）**: `チャンネル,動画,時系列,古い順,公開日,進捗,学習,シリーズ,未視聴,タイムライン`
- **サポートURL**: https://kataming.github.io/ChannelTimelineViewer/support/
- **マーケティングURL（任意）**: https://kataming.github.io/ChannelTimelineViewer/
- **プライバシーポリシーURL**: https://kataming.github.io/ChannelTimelineViewer/privacy/

## App プライバシー（App Privacy）
> Apple の「データ収集」アンケート。**運営者（開発者）のサーバーへは一切送信・収集しない**前提で回答。

- **データ収集（Data Collection）**: 開発者は利用者データを収集しない（視聴履歴・お気に入り・進捗・メモは
  端末内 UserDefaults のみ／外部送信なし）→ 「**Data Not Collected**」を基本とする。
- **トラッキング**: なし（IDFA不使用、ATT不要）
- ⚠️ 注意：本アプリは YouTube の**公式埋め込みプレイヤー/Data API**（Google）を利用する。Google/YouTube 側の
  データ取り扱いは各社ポリシーに従う。**第三者（YouTube埋め込み）に関する申告要否は提出前に Apple の最新ガイドと
  YouTube のデータ取り扱いを確認**すること（不明なら保守的に申告）。

## ビルド / 審査情報（App Review Information）
- **ビルド**: GitHub Actions or Xcode でアーカイブしたビルドを選択
- **連絡先（Contact）**: 片見俊春 / atamitrading@wind.ocn.ne.jp
- **デモアカウント**: 不要（ログイン無し）。ただし**動画取得に有効なAPIキーを含むビルド**が必要
- **メモ（Notes）**: [`AppStore/review-notes.md`](AppStore/review-notes.md) の内容を貼る
  （公式プレイヤー使用・DL/スクレイピング/広告回避/BG再生なし・テスト手順・APIキー同梱の旨）

## 輸出コンプライアンス（Export Compliance）
- 通信は HTTPS（標準的な暗号化）のみ。独自暗号は無し → 「標準的な暗号化を使用（適用除外に該当）」を選択する想定
  （提出時の質問に従って回答）。

## 著作権（Copyright）
- 例: `2026 片見俊春`

## 商標表記（説明文末尾など）
- 「YouTube は Google LLC の商標です。本アプリは公式アプリではありません。」

---

## 提出前 最終チェック
- [ ] 名称・説明・キーワードに「公式」誤認や YouTube ロゴ使用がない
- [ ] プライバシー/サポート/マーケティングURL が公開＆到達可能
- [ ] App プライバシーの申告（第三者の扱い含む）を確認
- [ ] スクショ（[`screenshot-production-guide.md`](screenshot-production-guide.md)）・アイコン（[`app-icon-requirements.md`](app-icon-requirements.md)）準備済み
- [ ] 審査メモに公式プレイヤー使用・禁止実装なしを明記
