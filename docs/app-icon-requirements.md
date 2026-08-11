# App Store アイコン要件

> 提出にはアプリアイコンが必須。**YouTube のロゴ・赤い再生ボタン・「Tube」等のブランド要素は使わない**
> （商標・誤認の回避）。オリジナルのアイコンを用意する。

## 必須スペック（App Store / iOS）
- サイズ: **1024 × 1024 px**（App Store マーケティング用。アプリ本体の各サイズは Xcode が自動生成）
- 形式: **PNG**（JPEG可だが PNG 推奨）
- カラースペース: sRGB または Display P3、**フラット（レイヤー統合済み）**
- **アルファ（透過）なし**：背景は不透明にする（透過があると審査で弾かれる）
- **角丸を自分で付けない**：四角のまま作る（iOS が自動でマスク・角丸を適用）
- 余白・セーフエリア：要素を端ギリギリにしない（角丸でケラレる）

## デザイン指針（規約・誤認回避）
- ❌ 使わない：YouTube ロゴ、赤い丸/角丸の再生ボタン、YouTube の赤色を主体にした配色、「Tube」「YouTube」の文字
- ✅ 推奨モチーフ：**時系列・順番・チェックリスト・進捗**を想起させるもの
  - 例：左から右へ並ぶ動画フレーム＋時計/タイムライン、番号付きリスト、チェック＋プログレスバー
- 配色は YouTube を連想させない（赤一色を避け、青・緑・モノトーン等）
- 「公式」「Official」と誤認させる意匠にしない

## アプリへの組み込み手順
1. 1024px の PNG を用意（例 `AppIcon-1024.png`）
2. `Resources/Assets.xcassets/AppIcon.appiconset/` に画像を置く
3. 同フォルダの `Contents.json` の該当スロットに `"filename": "AppIcon-1024.png"` を設定
   - 現状は単一サイズ（iOS 17 形式）の空スロットを用意済み。filename を入れるだけ
4. `xcodegen generate` → Xcode でアイコンが反映されることを確認
5. ビルド時の「missing app icon」警告が消えることを確認

## 作成ツール（例）
- Sketch / Figma / Affinity Designer / Canva 等で 1024×1024・透過なしで書き出し
- アイコン各サイズ生成が必要な場合も、iOS は 1024 単一指定で自動対応（追加サイズ不要）

## 現在のアイコン（作成済み）

`scripts/generate_app_icon.py`（Pillow）で生成し、`Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`
に配置済み。デザインを変えたい場合は同スクリプトの座標・配色を編集して `python scripts/generate_app_icon.py` を再実行する。

- モチーフ：タイムライン上に並ぶ3枚の動画フレーム（視聴済み＝ティール／現在地＝白／未視聴＝くすんだ青）＋
  チェック付きノード＋下部の進捗バー＝「公開日順に並べて進捗を管理する」というアプリの中身をそのまま表現
- 配色：ネイビー〜ティールのグラデーション（**赤は不使用**）

## チェック
- [x] 1024×1024・PNG・透過なし（RGB モードで保存）・角丸なし
- [x] YouTube ロゴ/赤再生ボタン/「Tube」文字を使っていない
- [x] `AppIcon.appiconset/Contents.json` に filename 設定済み
- [ ] Xcode でアイコン表示・警告なし（Mac/CI でのビルド時に確認）
