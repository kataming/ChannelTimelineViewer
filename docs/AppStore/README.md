# App Store 提出準備 — 索引

このフォルダは **Channel Timeline Viewer** を App Store に提出するための資料です。
（プロジェクト名・ターゲット/モジュール名・表示名・Bundle ID をすべて `Channel Timeline Viewer` 系に統一済み。）

## ファイル

| ファイル | 内容 |
|---|---|
| [`app-description.md`](app-description.md) | App Store 説明文の下書き（日本語・英語） |
| [`review-notes.md`](review-notes.md) | App 審査向けメモ（公式プレイヤー使用・禁止実装なしの説明、テスト手順） |
| [`testflight-checklist.md`](testflight-checklist.md) | TestFlight 配信前のチェックリスト |
| [`privacy-policy-template.md`](privacy-policy-template.md) | プライバシーポリシーの雛形 |

## プライバシーポリシーURLの設定場所

このアプリはプライバシーポリシーURLを **2か所**で扱います。

1. **アプリ内表示**: `Resources/Config.plist` の `PRIVACY_POLICY_URL` キー。
   設定するとアプリ内「ⓘ このアプリについて」画面にリンクが表示されます（未設定なら非表示）。
   - 例:
     ```xml
     <key>PRIVACY_POLICY_URL</key>
     <string>https://example.com/channel-timeline-viewer/privacy</string>
     ```
2. **App Store Connect**: アプリ情報 → 「プライバシーポリシーURL」に同じURLを登録（提出に必須）。

ポリシー本文は [`privacy-policy-template.md`](privacy-policy-template.md) を編集し、GitHub Pages・Notion 公開ページ・
自社サイト等でホストして、その公開URLを上記2か所に設定してください。

## 提出前に変更が必要な設定（`project.yml`）

- ~~`PRODUCT_BUNDLE_IDENTIFIER`~~: `com.deskflowlabs.channeltimelineviewer` に設定済み
- `DEVELOPMENT_TEAM`: 自分の Apple Developer Team ID を設定
- `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`: リリースに合わせて更新
- 変更後 `xcodegen generate` で `.xcodeproj` を再生成
