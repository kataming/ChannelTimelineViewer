# App Store 公開準備メモ

現状は **シミュレーター/CIビルド専用（署名なし）**。Apple Developer Program 加入後に、ここに整理した箇所を
差し替えるだけで提出準備に移行できる。**署名設定はまだ入れていない。**

（説明文・審査メモ・プライバシーポリシー雛形など詳細は [`AppStore/`](AppStore/) にもあり。本ファイルは「加入後にどこを変えるか」の地図。）

---

## 1. 現在のアプリ名・Bundle ID・表示名（確認）

| 項目 | 現在の値 | 定義場所 |
|---|---|---|
| プロジェクト/ターゲット/モジュール/スキーム名 | `ChannelTimelineViewer` | `project.yml` の `name:` / `targets:` |
| **表示名（ホーム画面・App Store）** | `Channel Timeline Viewer` | `project.yml` → `INFOPLIST_KEY_CFBundleDisplayName` |
| 製品名（.app名） | `ChannelTimelineViewer` | ターゲット名と同一（PRODUCT_NAME未指定＝ターゲット名） |
| **Bundle ID** | `com.deskflowlabs.channeltimelineviewer`（App Store Connect 登録済み） | `project.yml` → `PRODUCT_BUNDLE_IDENTIFIER` |
| Team ID | （未設定・空） | `project.yml` → `DEVELOPMENT_TEAM` |
| バージョン | `1.0`（build `1`） | `project.yml` → `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` |
| デプロイ先 | iOS 17.0 / iPhone のみ | `project.yml` |

> 旧コード名 `OldTube...` は廃止済み（リポジトリ名も `ChannelTimelineViewer`）。YouTube/Tube を連想させる名称は表示・Bundle ID から排除済み。

## 2. Apple Developer Program 加入後に設定する場所

加入（年額 約$99）後、**`project.yml` の2か所だけ**を変更して `xcodegen generate` し直す：

```yaml
# project.yml
settings:
  base:
    DEVELOPMENT_TEAM: "ABCDE12345"        # ← 自分の Team ID(10桁)。developer.apple.com → Membership で確認
targets:
  ChannelTimelineViewer:
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.deskflowlabs.channeltimelineviewer  # ← 設定済み
```

- Team ID の確認場所：https://developer.apple.com/account → 「Membership details」→ Team ID（10桁）
- Bundle ID は App Store Connect でアプリ登録時のものと一致させる
- 変更後：`xcodegen generate` → Xcode で「Signing & Capabilities」が Automatic signing で通ることを確認
- **それまでは署名なし**：CI は `CODE_SIGNING_ALLOWED=NO`、ローカルはシミュレーター実行（署名不要）

## 3. 本番用 Config.plist の設定方法

`Config.plist` は **`.gitignore` 済みでコミットされない**（実キーを含むため）。各環境で手動作成する。

```bash
# 雛形をコピー
cp Resources/Config.example.plist Resources/Config.plist
```

`Resources/Config.plist` の中身（`PlistBuddy` でも、Xcode/エディタ直接でも可）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>YOUTUBE_API_KEY</key>
    <string>（本番の YouTube Data API v3 キー）</string>
    <key>PRIVACY_POLICY_URL</key>
    <string>https://kataming.github.io/ChannelTimelineViewer/privacy/</string>
</dict>
</plist>
```

- APIキーは **iOSアプリのバンドルに含まれる**ため、Google Cloud Console で **API制限（YouTube Data API v3のみ）**＋
  可能なら **iOSアプリ制限（Bundle ID）** をかけること。
- 提出ビルドには有効なキーを含める（無いと一覧取得ができずレビューで機能確認不可）。
- CI では Secret `YOUTUBE_API_KEY` があればそれを、無ければダミーキーを使う（`ios-build.yml`）。

## 4. APIキーを GitHub に誤って push しない設定（再確認済み）

`.gitignore` に以下を登録済み。`git check-ignore` で実際に無視されることを確認済み。

```
Config.plist
Resources/Config.plist
youtubeapikey.txt
*apikey*.txt
*api_key*.txt
*.secret
```

運用ルール：
- **`git add -A` / `git add .` を使わない**（対象ファイルを明示指定する）。過去に `youtubeapikey.txt` を
  誤って public へ push した事故あり。明示指定で再発防止。
- 実キーは `Config.plist`（gitignore済み）か、CIは GitHub Secrets に置く。リポジトリやチャットに貼らない。
- 万一 push してしまったら：リモートから除去（force-push）＋**該当キーを必ず無効化・再生成**
  （履歴切り離しだけでは SHA 経由で残存しうるため）。

## 5. 提出前に必要な項目（チェック）

詳細チェックは [`AppStore/testflight-checklist.md`](AppStore/testflight-checklist.md)。要点：

- [ ] Apple Developer Program 加入
- [ ] `DEVELOPMENT_TEAM` / `PRODUCT_BUNDLE_IDENTIFIER` を本番値に差し替え（上記2）
- [ ] **アプリアイコン 1024px** を `Resources/Assets.xcassets/AppIcon.appiconset/` に配置（YouTubeロゴ等は使わない）
- [ ] `Resources/Config.plist` に本番 APIキー＋プライバシーポリシーURL（上記3）
- [ ] プライバシーポリシーを公開し、App Store Connect とアプリ内（`PRIVACY_POLICY_URL`）にURL設定
- [ ] プライバシーマニフェスト `Resources/PrivacyInfo.xcprivacy` を同梱（追加済み）
- [ ] App Store Connect でアプリ作成・説明文（[`AppStore/app-description.md`](AppStore/app-description.md)）・審査メモ（[`AppStore/review-notes.md`](AppStore/review-notes.md)）
- [ ] スクリーンショット（公式ロゴの不正使用や「公式」誤認表現を避ける）
