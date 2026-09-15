# チャンネルの追加方法の案内（初回チュートリアル）

2026-09-16 追加。iOS / Android 両方。

## 1. 背景

チャンネルを追加する道筋が **「YouTube で共有 → このアプリを選ぶ」** で、
アプリの中を探しても見つからない。入れた直後の人が何もできずに終わる可能性が高かった。

入力欄に URL を貼る道もあるが、これも「YouTube からURLをコピーしてくる」と知っていないと使えない。
つまり**どちらの道も、外のアプリでの操作を知っている前提**になっていた。

## 2. UX の目的

「入れた直後の人が、1本目のチャンネルを登録できる」ところまで運ぶ。それだけ。

やらないこと:

- 起動直後に強制で出す（機能紹介の押し売りにしない）
- 何度も出す（分かっている人には邪魔でしかない）
- アプリの外の操作を自動化する（YouTube の画面を乗っ取るようなことはしない）

## 3. 表示条件

**初めてチャンネルを追加しようとしたとき**だけ自動で出す。判定は次の2つが**両方**成り立つとき:

1. まだ案内を見終わっていない（`channelTutorialCompleted` が false）
2. 保存チャンネルが**1件も無い**（＝まだ1つも追加できていない人）

チャンネル入力画面を開いた時点で判定する。この画面は「チャンネルを追加するための画面」なので、
ここに来た＝追加しようとしている、とみなしている。

2件目以降を追加しようとする人には出ない（条件2で外れる）。

## 4. 完了条件・スキップ

| 操作 | 完了フラグ | 次回の自動表示 |
| --- | --- | --- |
| 最後まで見て「YouTubeを開いて試す」 | **立てる** | 出ない |
| 途中で「スキップ」 | **立てる** | 出ない |
| シートを下にはらって閉じる | **立てる**（iOS は `onSkip` 経由） | 出ない |
| 「このアプリについて」から開き直した | **変えない** | 条件が残っていれば出る |

**スキップも「見た」扱いにしている。** 断った人に同じものを出し続けないため。
見直したい人には第5節の入口がある。

アプリを更新しても再表示しない（フラグは端末に残る）。
アプリを入れ直すと新しい利用者として扱われ、また出る。

## 5. 再表示のしかた

**「ⓘ このアプリについて」→「チャンネルの追加方法を見る」**（`tutorial.open.a11y`）。

ここから開いた場合は**完了フラグを変えない**。手で見直しただけで状態が変わると、
「説明が要る人かどうか」の区別がつかなくなるため。

## 6. iOS と Android の違い

| | iOS | Android |
| --- | --- | --- |
| 画面 | `Views/ChannelTutorialView.swift`（`.sheet`） | `ui/ChannelTutorialSheet.kt`（`ModalBottomSheet`） |
| 保存 | `Services/ChannelTutorialStore.swift`（`UserDefaults`） | `data/ChannelTutorialStore.kt`（`SharedPreferences`） |
| キー | `channelTutorialCompleted` | `channel_tutorial_completed_v1` |
| STEP3 の文言 | `tutorial.step3.body.ios` | `tutorial.step3.body` |
| STEP3 の画像 | **無し**（第7節） | `tutorial_android_share_sheet` |
| 計測 | **無し**（iOS に解析SDKを入れない方針） | あり（第9節） |

STEP3 の文章が別なのは、**受け取り方がそもそも違う**ため:

- **Android**: 共有先にアプリが出る → 選ぶと直接一覧が開く
- **iOS**: 共有シートで選ぶとリンクがクリップボード経由で渡り、
  アプリに戻って「共有されたURLを開く」を押す（iOS の制約。`SharedLinkRouter` 参照）

## 7. 使用画像

| ファイル名（両OS共通） | 中身 | 出どころ |
| --- | --- | --- |
| `tutorial_youtube_channel` | YouTube で @nasa のチャンネルページを開いた画面 | Android エミュレータの実画面 |
| `tutorial_youtube_share` | メニューの中の「Share」を枠で囲んだもの | 同上 |
| `tutorial_android_share_sheet` | Android の共有シートで本アプリを枠で囲んだもの | 同上 |

置き場所:

- Android … `android/app/src/main/res/drawable-nodpi/`
- iOS … `Resources/Assets.xcassets/<名前>.imageset/`
- 素材（加工前）… `docs/tutorial/raw/`

合計 **約162KB**（3枚・幅720px・PNG 256色）。ビルドサイズへの影響は無視できる大きさ。

### ⚠️ iOS の共有シート画像が無い

**未取得。** 開発機が Windows で、iOS シミュレータも実機も無く、**本物を撮れなかった**。

作り物の共有シートを描くことはしていない（Apple の UI を偽装することになり、
「架空UI化は禁止」という方針にも反するため）。代わりに iOS の STEP3 は、
**自前のUIで「共有 → このアプリを選ぶ」だけを示す**図と、文章で説明している。

本物を入れるときは第11節の手順で差し替える。

## 8. @nasa を例に使った理由と、提携でないことの明示

- 公的機関の**公開チャンネル**で、誰でも同じ画面を再現できる
- 本数が多く「古い順に見る」という本アプリの用途に合う
- NASA の映像は基本的にパブリックドメインで、画面写真として扱いやすい

**画像はUIの説明に必要な最小限**（チャンネルページの上部・メニュー・共有シート）に留め、
動画そのものを見せる作りにはしていない。

案内の最後に、全言語で次を表示している（`tutorial.example.note`）:

> 画面は例として NASA の公開チャンネルを使っています。本アプリは YouTube および NASA とは
> 関係がなく、提携・公認を受けたものではありません。

**やっていないこと**: YouTube/NASA のロゴを本アプリの宣伝に使う、公認・提携をうたう、
画面の文字やロゴを描き替える。

## 9. Analytics イベント（Android のみ）

iOS には解析SDKを入れていないので、iOS 側の計測は**無い**
（[`../android-firebase-analytics.md`](../android-firebase-analytics.md) の方針）。

| イベント | いつ | 引数 |
| --- | --- | --- |
| `channel_tutorial_view` | 案内を開いた | `source` = `first_time`（自動）/ `manual`（About から） |
| `channel_tutorial_complete` | 最後まで見て CTA を押した | なし |
| `channel_tutorial_skip` | 途中でやめた | `value` = やめた時点の手順番号（1〜3） |

既存イベントと重複するものは新設していない。**「チュートリアル後に実際に追加へ進んだか」は
既存の `channel_open`（`source=share` / `url`）で分かる**ので、`channel_add_start` は作っていない。

効果の見方: `channel_tutorial_view` のユーザー数に対して、その後 `channel_open` が出た人の割合。

**送らないもの**: URL・チャンネル名（NASA を含む）・動画タイトル・個人情報。
`ChannelTutorialTest` が機械的に検査している。

計測は fail-open。記録に失敗しても案内と完了状態は動く（先に状態を確定させ、記録はそのあと）。

## 10. テスト結果

`ChannelTutorialTest`（Android・10件）で次を確認:

| # | 見たこと | 結果 |
| --- | --- | --- |
| 1 | 初回は出る | ✅ |
| 2 | 見終わったら出ない | ✅ |
| 2' | すでに保存済みの人には出ない | ✅ |
| 3 | スキップも「見た」扱い | ✅ |
| 5 | 手で開き直しても完了状態が壊れない | ✅ |
| 5' | 未完了の人が手で開いても自動表示の権利は残る | ✅ |
| — | 再起動しても覚えている | ✅ |
| 9 | 記録が失敗しても完了状態は保存される | ✅ |
| — | 記録にURL・チャンネル名が混ざらない | ✅ |

Android ユニットテスト全体: **114件 / 失敗0**。

画像が読めない場合（#8）は、両OSとも**説明文だけで成立する**作りにしてある
（iOS は `UIImage(named:)` が nil なら代替の図、Android は文章が先に出る）。

## 11. 画像を差し替えるとき

素材を `docs/tutorial/raw/` に置き直して、次を実行する:

```
python scripts/build_tutorial_images.py
```

クロップ位置と枠の座標は `scripts/build_tutorial_images.py` の `main()` に
**元画像のピクセル座標**で書いてある。撮り直したらそこだけ直す。

### Android の素材を撮り直す

```
emulator -avd <AVD名> &
adb install -r android/app/build/outputs/apk/release/app-release.apk
adb shell am start -a android.intent.action.VIEW -d "https://www.youtube.com/@nasa" -p com.google.android.youtube
adb exec-out screencap -p > docs/tutorial/raw/android-channel.png
```

メニュー（右上の ⋮）→ Share → More と進んで、同じ手順で撮る。
**自アプリを入れておく**こと（共有シートに出ないと STEP3 の意味が無い）。

### iOS の共有シートを撮る（未実施）

実機の iPhone で:

1. YouTube アプリで `@nasa` を開く → 共有 → 共有シートを出す
2. **Channel Timeline Viewer が見えている状態**でスクリーンショット
3. `docs/tutorial/raw/ios-share-sheet.png` として置く
4. `scripts/build_tutorial_images.py` に STEP3(iOS) の書き出しを足す
   （`tutorial_ios_share_sheet` を iOS の imageset へ）
5. `Views/ChannelTutorialView.swift` の STEP3 の `image` を
   `nil` から `"tutorial_ios_share_sheet"` に変える

⚠️ 自分の名前・アイコン・通知など、個人のものが写り込んでいないか確認してから入れること。

## 12. 次回リリース時の確認事項

- **バージョンは上げていない**（この変更だけで提出しない前提のため）。
  Android の最新 versionCode は **11**、iOS は `MARKETING_VERSION 1.1.1` / `CURRENT_PROJECT_VERSION 30`。
  次のリリース時に、そのときの最新値を見て決める
- iOS の共有シート画像を入れたか（第11節）
- 実機で、文字を最大まで大きくしても崩れないか
- ダークモードで画像の白背景が浮きすぎないか
- 新規インストールで**実際に案内が出るか**（フラグは端末に残るので、
  確認するときはアプリを消して入れ直す）
