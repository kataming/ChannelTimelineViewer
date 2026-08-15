# TestFlight 実機確認チェックリスト

> Apple Developer Program 加入後、実機に TestFlight 配信して確認する流れ。
> 画面ごとの詳細な動作確認は [`manual-test-checklist.md`](manual-test-checklist.md) を併用する。
> **署名・Bundle ID・Team ID は加入後に設定**（現状は未設定）。

## A. 配信前（ビルド準備）
- [ ] `project.yml` の `DEVELOPMENT_TEAM` に自分の Team ID（10桁）を設定
- [x] `PRODUCT_BUNDLE_IDENTIFIER` を `com.deskflowlabs.channeltimelineviewer` に設定済み
- [ ] `xcodegen generate` で `.xcodeproj` を再生成
- [x] アプリアイコン 1024px を `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` に配置済み
      （`scripts/generate_app_icon.py` で生成・再生成可能）
- [ ] `Resources/Config.plist` に**本番** `YOUTUBE_API_KEY` と `PRIVACY_POLICY_URL` を設定（Git管理しない）
- [ ] APIキーに本番制限を設定（[`youtube-api-key-production-settings.md`](youtube-api-key-production-settings.md)）
- [ ] `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` を設定
- [ ] GitHub Actions の CI が green（コンパイル＋ユニットテスト）
- [ ] **共有シート（Share Extension）用の署名を用意した**
      （`python scripts/asc_add_extension_signing.py` → `PROVISIONING_PROFILE_EXT_*` を Secrets に登録。
      手順は [`ci-release-guide.md`](ci-release-guide.md) Step 2.5）
- [ ] `iOS Build` のログで「Share Extension is embedded in the app bundle」が成功している
      （`.app/PlugIns/*.appex` とカスタムURLスキーム `channeltimelineviewer` の確認）

## B. App Store Connect / アーカイブ
- [ ] App Store Connect でアプリを作成（Bundle ID 一致）
- [ ] アプリ情報・プライバシーポリシーURL・年齢区分・「Appのプライバシー」を入力
- [ ] Xcode で実機/汎用iOSデバイス向けに **Product → Archive**
- [ ] Organizer → Distribute App → App Store Connect → Upload
- [ ] 処理完了後、TestFlight タブにビルドが表示される

## C. TestFlight 実機確認
- [ ] 自分（内部テスター）に配信し、実機の TestFlight アプリでインストール
- [ ] 起動してクラッシュしない
- [ ] チャンネルURL入力 → 動画一覧（古い順）取得 → 実APIで実データが出る
- [ ] 進捗バー・「次に見る/続きから」・フィルター（未視聴/視聴済み）が動く
- [ ] 公式埋め込みプレイヤーで再生できる・前へ/次へ・視聴済み切替が反映される
- [ ] 途中でやめた動画を開き直すと**続きから再生**される／「最初から」で頭出しできる
- [ ] 再生画面に「自動再生オフ：終了後に停止」トグルが**常時表示**され、**初期状態はオフ**
- [ ] オフのまま再生終了 → 停止して「次の動画を再生」ボタンが出る
- [ ] 自分でオンにすると、終了時に一覧の次の動画へ続けて再生される（実際に見た動画だけ視聴済みになる）
- [ ] 「視聴済みにする」の大きなボタンが再生画面から無くなり、「…」メニューと一覧のスワイプで切り替えられる
- [ ] メモを入力 → 保存され、再表示でも残る
- [ ] 「ⓘ このアプリについて」に注意事項5点とプライバシーポリシーリンクが出る
- [ ] バックグラウンド（ホームに戻る/画面ロック）で音声が止まる（BG再生なし）
- [ ] 実機で1〜2世代前のiOS（17.x）でも起動・主要操作ができる（可能なら）

## C-2. 共有シート（Share Extension）の実機確認 ★今回の追加機能
> 先に **アプリを1回起動しておく**（インストール直後は共有シートに出ないことがある）。

- [ ] **YouTube アプリ**でチャンネルのページを開く → 共有 → 一覧に **Channel Timeline Viewer** が出る
      - 出ない場合: 共有先を右端までスクロール → **「その他」**（または「アクションを編集…」）→
        Channel Timeline Viewer を **オン** にする。並べ替えて上位に固定すると次回から出やすい
- [ ] タップ → Channel Timeline Viewer が起動し、**そのチャンネルの動画一覧（古い順）**が開く
- [ ] **YouTube アプリで動画**を開く → 共有 → Channel Timeline Viewer
      → **その動画を投稿したチャンネル**の一覧が開く（動画URL → channelId 解決）
- [ ] YouTube アプリの共有が「タイトル＋URL」のテキストでも同じように開ける
- [ ] **Safari** で `https://www.youtube.com/@任意のハンドル` を開く → 共有 → 同様に開ける
- [ ] `https://youtu.be/...`（短縮URL）でも開ける
- [ ] 共有したチャンネルが「最近使ったチャンネル」に追加され、進捗管理の対象になる
- [ ] YouTube 以外のページ（例: ニュースサイト）を共有した場合、
      「YouTube の URL が見つかりませんでした」と出て**何も起きない**（誤動作しない）
- [ ] アプリを**起動済みの状態**で共有しても、共有したチャンネルへ切り替わる
- [ ] 従来どおり**URLの手入力**でも取得できる（既存導線が壊れていない）

## D. 規約・ストア表現の最終確認
- [ ] 説明文が「YouTube代替」ではなく「時系列視聴・進捗管理・学習補助」になっている
- [ ] スクショに YouTube ロゴの不正使用・「公式」誤認表現がない
- [ ] 「このアプリは YouTube 公式アプリではありません」等の注意がストア説明とアプリ内に明記
- [ ] [`AppStore/review-notes.md`](AppStore/review-notes.md) の審査メモを App Review Information に記載
- [ ] 最新の [YouTube API サービス利用規約](https://developers.google.com/youtube/terms/api-services-terms-of-service)・
      [ブランドガイドライン](https://developers.google.com/youtube/terms/branding-guidelines) を再確認

## E. 提出
- [ ] スクリーンショット（[`screenshot-copy.md`](screenshot-copy.md) の文言）を用意
- [ ] 審査提出
