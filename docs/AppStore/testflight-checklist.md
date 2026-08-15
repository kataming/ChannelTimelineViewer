# TestFlight 配信前チェックリスト

配信・提出の前に確認する項目です。チェックが付くまで提出しないでください。

## アプリ識別・署名
- [x] `PRODUCT_BUNDLE_IDENTIFIER` を `com.deskflowlabs.channeltimelineviewer` に設定した
- [x] 共有シート拡張の Bundle ID を `com.deskflowlabs.channeltimelineviewer.shareextension` に設定した
- [ ] 拡張用の Bundle ID / プロビジョニングプロファイルを作成した
      （`python scripts/asc_add_extension_signing.py`）
- [ ] `DEVELOPMENT_TEAM` に自分の Team ID を設定した
- [x] App Store Connect に同じ Bundle ID のアプリを作成した
- [ ] 署名（Automatic signing 推奨）でアーカイブできる
- [ ] `MARKETING_VERSION`（表示バージョン）と `CURRENT_PROJECT_VERSION`（ビルド番号）を設定した

## 表示・名称
- [ ] 表示名が `Channel Timeline Viewer`（YouTube/Tube を連想させない）
- [x] **アプリアイコンの実画像を追加した**（`AppIcon.appiconset/AppIcon-1024.png` = 1024×1024 PNG・透過なし・
      `Contents.json` に `"filename"` 設定済み。`scripts/generate_app_icon.py` で生成したオリジナル。
      タイムライン/チェック/進捗バーのモチーフで、YouTube ロゴ・赤い再生ボタン・赤主体の配色を使っていない）
- [ ] スクリーンショットに公式ロゴの不正使用や「公式」と誤認させる表現がない

## プライバシーマニフェスト（必須・追加済み）
- [ ] `Resources/PrivacyInfo.xcprivacy` がビルドに含まれている（トラッキングなし/収集なし/UserDefaults理由CA92.1を申告済み）

## 機能・設定
- [ ] `Resources/Config.plist` に**有効な** `YOUTUBE_API_KEY` を設定した（提出ビルドに含む）
- [ ] `PRIVACY_POLICY_URL` を設定し、アプリ内「ⓘ」画面にリンクが出る
- [ ] アプリ内「ⓘ このアプリについて」に3つの注意事項が表示される
- [ ] チャンネル取得 → 古い順表示 → 再生 → 前後移動 → 視聴済み → お気に入り が一通り動く
- [ ] **共有シートに Channel Timeline Viewer が出る**（YouTube アプリ / Safari）。
      出ない場合は共有先の「その他」からオンにできる
- [ ] 共有したチャンネルURL / 動画URL のどちらからでも動画一覧が開く
      （詳細手順は [`../testflight-checklist.md`](../testflight-checklist.md) の「C-2」）

## ポリシー順守（禁止実装が無いこと）
- [ ] 動画ダウンロードなし
- [ ] スクレイピングなし（公式 API のみ）
- [ ] 独自プレイヤー再生なし（公式 IFrame のみ）
- [ ] 広告回避なし
- [ ] バックグラウンド再生なし（`UIBackgroundModes` 未設定）

## プライバシー（App Store Connect の「Appのプライバシー」）
- [ ] 収集データの申告を行った（本アプリはサーバー送信なし。視聴履歴・お気に入りは端末内 UserDefaults のみ）
- [ ] トラッキングなしを申告（ATT 不使用）
- [ ] プライバシーポリシーURLを登録した

## ビルド/CI
- [ ] GitHub Actions の `iOS Build` が green（コンパイル＋テスト通過）
- [ ] 実機 or シミュレーターで起動確認

## 審査情報
- [ ] `review-notes.md` の内容を App Review メモに記載
- [ ] 連絡先情報を記入
- [ ] （必要なら）レビュー用のサンプルチャンネルURLを記載
