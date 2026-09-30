# チャンネル内検索（タイトルの絞り込み）

いま開いている1チャンネルの動画一覧を、**動画タイトル**で絞り込む（2026-09-30 追加・Web体験版 / iOS / Android）。
**CTV のシンプルさを保つ**ための小さな機能で、次は**実装しない**:
説明文・コメント・メモの検索、複数チャンネル横断、AI 検索、候補表示、AND/OR、年代・長さの絞り込み、
検索専用の画面、YouTube の検索 API を使った別検索。

## 検索する範囲

- そのチャンネルについて**取得・保存済みの一覧全体**（`playlistItems.list` でアップロード一覧を全件取得したもの）。
  画面に描画されている分（Web体験版は 50 本ずつ描画）だけではない。
- 一覧の取得は3つとも**最大 5,000 本**（50 本 × 100 ページ）で打ち切る既存の仕様のまま。
  5,000 本を超えるチャンネルでは、取得できていない古い（または新しい順で後ろの）動画は検索にも出ない。
- 検索のために**通信しない**（入力のたびに API を呼ばない）。YouTube API の quota は増えない。

## 一致の規則（3つで同じ）

```
normalize(s) = NFKC(s) を小文字にしたもの
一致        = normalize(タイトル) が normalize(検索語の前後の空白を除いたもの) を含む
検索語が空   = 絞り込まない（全件）
```

- NFKC は各OSの標準機能（Swift `precomposedStringWithCompatibilityMapping` / Kotlin `java.text.Normalizer` /
  JS `String.prototype.normalize`）だけを使う。ライブラリは足さない。
  全角英数（`ＣｈａｔＧＰＴ`）・半角カナ（`ｶﾀｶﾅ`）も同じ文字として当たる。
- 大文字・小文字は区別しない。部分一致。日本語・中国語・韓国語もそのまま部分一致する。
- 実装:
  - iOS: `Models/VideoItem.swift` の `VideoItem.titleMatches(_:)`
  - Android: `model/Models.kt` の `VideoItem.titleMatches(query)`
  - Web体験版: `site/src/trial/model.js` の `titleMatches(title, query)`
- **3つとも同じテスト例**で確かめている（下の表。変えるときは3か所のテストを一緒に直す）:
  - iOS `Tests/ChannelSearchTests.swift` / Android `ChannelSearchTest.kt` / Web `site/scripts/test-trial.mjs`

| タイトル | 検索語 | 結果 |
| --- | --- | --- |
| How to Use ChatGPT for Work | chatgpt | 当たる |
| How to Use ChatGPT for Work | CHATGPT | 当たる |
| How to Use ChatGPT for Work | Use Chat | 当たる |
| ＣｈａｔＧＰＴ入門 | chatgpt | 当たる（全角） |
| 日本語の動画タイトル | 動画 | 当たる |
| ｶﾀｶﾅのタイトル | カタカナ | 当たる（半角カナ） |
| 中文视频标题 | 视频 | 当たる |
| 한국어 동영상 제목 | 동영상 | 当たる |
| How to Use ChatGPT for Work | python | 当たらない |
| （何でも） | 空 / 空白だけ | 当たる（絞り込まない） |

## 画面

- 一覧の画面に**検索のアイコン**を置く。押すと検索欄が出る。使わない人には従来とほぼ同じ見た目。
  - iOS: ナビゲーションバー右上（並び替えメニューの左）。検索欄は一覧の一番上の行
  - Android: 上部バーの右（並び替えの左）。検索中は上部バーのタイトルが検索欄になる（← で閉じる・× で入力を消す・戻る操作でも閉じる）
  - Web体験版: 一覧の上のツールバーの右端。検索欄はツールバーの下
- 入力するとその場で絞り込む（debounce なし）。0 件なら「該当する動画がありません」。
- 検索語を消す・検索を閉じると全件に戻る。
- **並び替え（古い順/新しい順）と視聴フィルターはそのまま効く**（並び替え → 視聴フィルター → タイトル、の順に適用）。
- 件数の表示（「5,000本中 12本を表示」）は絞り込み後の数になる。進捗・「次に見る」はチャンネル全体のまま。
- 再生画面へ行って戻っても検索は残る。**別のチャンネルを開いたら検索は消える**。
- Free / Pro のどちらでも使える（Pro 限定にしない）。Watch Queue モード（Web）では出さない。

## 送らないもの

検索語は**どこにも送らない・保存しない**（Analytics にも出さない。Android の計測イベントも足していない）。
