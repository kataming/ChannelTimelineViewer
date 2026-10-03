# 無料版の広告（Google AdMob）— 2026-10-03 導入

ユーザー判断（2026-10-03・確定）:

1. **アンカー型アダプティブバナー**を基本の広告にする
2. **MREC（300×250）**を追加する
3. リリース後に実際の eCPM・広告 ARPU・継続率を測る
4. **Pro は完全に広告なし**
5. インタースティシャル（全面広告）・動画広告は**今回入れない**

入れていないもの: Interstitial / Rewarded / Rewarded Interstitial / App Open / Native / Collapsible Banner。
足すときは本書と `AdVisibilityPolicy` を通すこと（画面に直接書かない）。

---

## 1. 置き場所（iOS / Android 共通）

| 画面 | 広告 | 理由 |
| --- | --- | --- |
| 動画一覧 | **アンカー型アダプティブバナー**（画面下に固定） | 一覧をスクロールして選ぶ画面で、下端は操作が無い。一覧の最後の行も広告の上までスクロールできる |
| 最初の画面（入力・保存チャンネル） | **MREC**（保存チャンネルの一覧の後ろに1つ） | 入力欄・取得ボタン・Pro の案内より下。**保存チャンネルが0件（初回）の人には出さない・読み込みもしない** |
| 再生画面 | **なし** | YouTube のプレイヤー・移動ボタン・自動再生の切り替えに重ねない（III.G.1.c・誤タップ防止） |
| Pro の購入画面 | なし | 購入の操作の邪魔をしない |
| このアプリについて | なし | 規約・プライバシーの説明画面 |

- 1つの画面に広告は1つだけ（バナーと MREC を同じ画面に出さない）
- MREC には「広告（ads.label）」の表示と枠線を付ける。動画やチャンネルの行（サムネイル付き）と同じ見た目にしない
- バナーは区切り線の下に置き、ナビゲーションバー／ホームインジケーターに重ねない（Android は `navigationBarsPadding`、iOS は `safeAreaInset`）
- どちらも**読み込めてから場所を取る**。読み込み中・失敗・オフライン・Pro のときは空白を残さない
- 大きさは Google が現在推奨している「大きいアンカー型」
  （Android `AdSize.getLargeAnchoredAdaptiveBannerAdSize` / iOS `largeAnchoredAdaptiveBanner(width:)`）。
  高さは 50〜150dp・画面の20%以内。従来の `getCurrentOrientationAnchoredAdaptiveBannerAdSize` は SDK 25 で非推奨

### ⚠️ YouTube API の規約（III.G.1.d）との関係 — 判断が必要

YouTube API Services Developer Policies **III.G.1.d** は、「YouTube API のデータを表示している画面で広告を販売してはならない。
ただし、YouTube から得たものではないデータ・内容が同じ画面にあり、YouTube API Data を取り除いても
広告販売を正当化できるだけの独立した価値がある場合を除く」としている。

- 動画一覧・最初の画面はどちらも YouTube API Data（動画タイトル・サムネイル・チャンネル名）を表示している
- 本アプリ独自の価値（公開日順の整理・視聴済み・進捗・続きから・メモ）が同じ画面にあるので
  「独立した価値」を主張できる余地はあるが、**判定は YouTube 側**（API の監査・クォータ申請で見られうる）
- YouTube API Data を一切表示しない画面は「このアプリについて」だけ

置き場所は `MainActivity.kt`（Android）と `VideoListView.swift` / `ChannelInputView.swift`（iOS）の
それぞれ1行で決めているので、方針が変わったら移すのは簡単。**本番 ID を入れる前に判断すること。**

---

## 2. Free / Pro の制御

正は既存の Pro 判定（Android `ProEntitlementStore.isPro` / iOS `ProEntitlementStore.isPro`）。
**課金側のコードは変えていない**。広告側がそれを読むだけ。

| 状態 | 同意フォーム（UMP） | SDK の初期化 | 広告リクエスト | 表示 |
| --- | --- | --- | --- | --- |
| Pro | しない | しない | しない | なし |
| 無料・同意が要らない地域 | 確認だけ（フォームは出ない） | する | する | あり |
| 無料・EEA/英国/スイス（同意済み or 不同意） | フォーム → 結果を保存 | `canRequestAds` なら | `canRequestAds` なら | 不同意でも「限定広告」が出る |
| 無料・本番 ID 未設定のリリース | しない | しない | しない | なし |

- 判定は `AdVisibilityPolicy`（Android `ads/AdVisibilityPolicy.kt` / iOS `Services/AdsConfig.swift`）の1か所
- **購入直後・復元直後**: `isPro` が true になった瞬間に `canShowAds` が false になり、画面は広告を外して破棄する
  （以後リクエストしない）。起動時に Pro なら最初から何もしない
- **返金などで無料に戻ったとき**: そのとき初めて同意の確認と SDK の初期化をする
- 広告の失敗（初期化・同意・読み込み）はすべて握りつぶす。起動・再生・購入を待たせない（fail-open）

---

## 3. テスト広告と本番 ID

| ビルド | アプリ ID | 広告ユニット |
| --- | --- | --- |
| デバッグ | Google 公式のテスト用 | **常に Google 公式のテスト用**（本番 ID があっても使わない） |
| リリース・本番 ID なし（いま） | テスト用（SDK が起動時に落ちないための置き場所） | 空 → **広告を一切出さない**（初期化もしない） |
| リリース・本番 ID あり | 本番 | 本番 |

テスト用 ID（Google 公式）:
- Android: アプリ `ca-app-pub-3940256099942544~3347511713` / アダプティブバナー `…/9214589741` / バナー（MREC にも使用）`…/6300978111`
- iOS: アプリ `ca-app-pub-3940256099942544~1458002511` / アダプティブバナー `…/2435281174` / バナー（MREC）`…/2934735716`

**AdMob の ID は秘密情報ではない**（アプリに入って誰でも読める）。本番 ID の入れ方:

- Android: `ADMOB_APP_ID` / `ADMOB_BANNER_UNIT_ID` / `ADMOB_MREC_UNIT_ID` を
  環境変数・`android/local.properties`・`android/gradle.properties` のどれかに書く
  （CI で使うなら `android/gradle.properties` に書いてコミットするのがいちばん手間が少ない）
- iOS: `project.yml` のアプリ本体ターゲットの `ADMOB_APP_ID` / `ADMOB_BANNER_UNIT_ID` / `ADMOB_MREC_UNIT_ID`
  （`App/Info.plist` に入る）

### デバッグ用の起動オプション

| 目的 | Android（`am start` の追加引数） | iOS（起動引数） |
| --- | --- | --- |
| EEA の同意フォームを試す | `--ez adsEea true` | `-AdsEEA YES` |
| 同意をやり直す | `--ez adsResetConsent true` | `-AdsResetConsent YES` |
| 広告を出さない（ストア用スクショ） | `--ez noAds true` | `-NoAds YES` |

**実機で確かめるとき（Android）**: 端末に Play 版が入っていても、`./gradlew :app:installDebug -PadsPreview=true` で
**別アプリ「CTV 広告確認」（`….adstest`）**として並べて入れられる（Play 版と保存データには触れない）。
テスト広告・同意フォームは確かめられるが、Pro の購入は引き継がれない。確認が済んだら
`adb uninstall com.deskflowlabs.channeltimelineviewer.adstest` で消す。

ストア用スクリーンショットの撮影（`scripts/capture_play_screenshots.py`・`scripts/capture_android_tutorial.py`・
`UITests/*ScreenshotUITests.swift`）は `noAds` を付けてある。**テスト広告をストアの画像に写さないこと。**

---

## 4. 同意（UMP）と ATT

- **UMP（Google User Messaging Platform）を入れた。** 広告リクエストより前に
  `requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired` を行い、`canRequestAds` が true になってから
  SDK を初期化する。前回の同意が残っていれば、今回の確認を待たずに進める（Google 推奨の形）
- 同意が要る地域の人には「ⓘ このアプリについて」に **「広告のプライバシー設定」**（`about.ads.privacyOptions`）を出し、
  いつでも見直せるようにした（`privacyOptionsRequirementStatus == REQUIRED` のときだけ）
- **同意フォームの文面と対象地域は AdMob の管理画面（プライバシーとメッセージ）で作る。**
  作るまでは本番で同意フォームが出ない（＝ EEA 等では広告を出せない可能性がある）
- **ATT（App Tracking Transparency）は入れていない。** `NSUserTrackingUsageDescription` も無い。
  IDFA を使わないので、iOS の広告はすべて「トラッキングなし」で配信される
- **Android の広告ID（`AD_ID` 権限）は外したまま。** Google Mobile Ads が足してくる分も
  manifest の `tools:node="remove"` で外れる。広告は広告IDなしで配信される（単価は下がりうる）

---

## 5. 計測（eCPM・広告 ARPU・継続率）

**アプリ側で広告の数字を二重に数えない。**

| 指標 | どこで見る | アプリ側の追加 |
| --- | --- | --- |
| 表示回数・収益・eCPM・表示率 | **AdMob の管理画面**（アプリ別・広告ユニット別・国別） | なし |
| 広告 ARPU（1人あたり広告収益） | AdMob の収益 ÷ Firebase の利用者数。AdMob と Firebase を**連携**すると、Firebase に `ad_impression`（収益つき）が自動で入り、利用者単位で見られる | なし（連携は管理画面の作業） |
| 無料／Pro の人数・比較 | Firebase の**ユーザー属性 `pro_status`**（`free` / `pro`）で分ける | **追加した**（Android のみ） |
| 導入前後の比較（DAU/MAU・セッション・継続率・Pro 購入率） | Firebase の「アプリのバージョン」で導入前の版と後の版を比べる。購入率は既存の `pro_purchase_success` | なし |

- `pro_status` は区分（`free` / `pro`）だけで、個人を特定する情報は含まない
- iOS 版には利用状況の記録（Firebase）が無いので、iOS は **AdMob の管理画面の数字だけ**で見る
  （iOS に計測を足すのは別の判断）
- Paid Event（表示ごとの収益コールバック）は**使っていない**。AdMob × Firebase 連携の `ad_impression` で足りるため

---

## 6. 依存の追加と、それに伴う変更

| | 追加したもの |
| --- | --- |
| Android | `com.google.android.gms:play-services-ads:25.5.0`、`com.google.android.ump:user-messaging-platform:4.0.0` |
| iOS | SPM `GoogleMobileAds`（13.x）、`GoogleUserMessagingPlatform`（3.x） |

- **Android の Kotlin を 2.0.21 → 2.2.21 に上げた。** Google Mobile Ads 24.x 以降が新しい Kotlin のメタデータで
  作られており、2.0.21 ではコンパイルできなかった（23.x は Google の方針で既に非推奨のため採らなかった）。
  上げたあと、単体テスト 182 件・リリース（R8）ビルド・エミュレーターでの再生を確認した。
  R8 後も `PlayerBridge.postMessage` と `model.**` の serializer が残っていることを mapping で確認した
- **マージで増える Android の権限**（いずれも利用者への許可ダイアログは出ない）:
  `ACCESS_ADSERVICES_TOPICS`・`RECEIVE_BOOT_COMPLETED`（Google Mobile Ads）、
  `FOREGROUND_SERVICE`（Google Mobile Ads が連れてくる WorkManager）。
  `ACCESS_ADSERVICES_AD_ID` / `ACCESS_ADSERVICES_ATTRIBUTION` は以前から Firebase 由来で入っていた。
  外すかどうかは**ユーザー判断**（外すと Privacy Sandbox 経由の広告が減る）
- iOS の `Resources/PrivacyInfo.xcprivacy`（アプリ自身の申告）は変えていない。
  Google Mobile Ads は自分のプライバシーマニフェストを同梱しており、App Store はそれを合算する

---

## 7. 外向きの記載で、広告を出す前に必ず直すもの

本番 ID を入れたリリースを出す**前に**、次を全部そろえて直すこと（いまは本番 ID が無いので広告は出ず、
記載と実物は食い違っていない）。

| 場所 | いまの記載 | 必要な変更 |
| --- | --- | --- |
| App Store 説明文（`docs/AppStore/metadata.json` の `description`・33言語） | 「アプリ内に広告はありません。サブスクリプションもありません」 | 広告ありに直す（Pro は広告なし、と書くかは判断） |
| Google Play 詳しい説明（`docs/PlayStore/metadata.json` の `fullDescription`・35言語） | 同上「No ads.」 | 同上 |
| 審査メモ（`docs/AppStore/review-notes.md` / `review-notes-en.md`） | 「広告は表示しません。広告 SDK も含んでいません」「NO PURCHASES, NO ADS」 | 広告あり（AdMob・UMP・ATT 不使用・Pro は広告なし・置き場所）に直す |
| 公式サイト（`site/src/i18n/translations.js`・7言語） | `ctaNote`「広告なし・サブスクなし」、FAQ「広告やサブスクはありますか？」、料金欄 `note`「広告もありません」 | 広告ありに直す |
| プライバシーポリシー（`docs/privacy-policy.md`・`translations.js` の `privacy`・7言語） | 「サーバーに送信・収集しません」「トラッキングを行いません」「Android のみ Firebase」 | **Google AdMob・UMP による広告配信と、Google に渡る情報（IP アドレス・端末情報・広告の操作など）・同意の見直し方法**を追記。広告ID・IDFA は使わない記載はそのまま正しい |
| App Store の App のプライバシー（栄養ラベル） | データ収集なし | Google Mobile Ads が集めるもの（Google の案内に従う：おおよそ「位置情報（おおよそ・IP 由来）」「ID（デバイス ID）」「使用状況（製品の操作・広告データ）」「診断」を**第三者広告**目的で）。トラッキング「なし」 |
| Google Play データセーフティ | 「広告SDKなし・広告ID収集なし」 | Google Mobile Ads の申告（Google の案内に従う）。広告IDは**収集しない**のまま（権限を外してあるため） |
| Play Console「広告を含む」 | いいえ | **はい** |
| `docs/android-play-release-guide.md` | 「広告 SDK は不使用」「アプリ内購入・サブスク・広告なし」 | 広告ありに直す |
| アプリ内「ⓘ このアプリについて」 | 広告の説明なし（`about.analytics.body` の「広告用の識別子も使いません」は引き続き正しい） | 「無料版には広告が出る・Pro は広告なし」の一文を足すかは判断 |
| Pro の訴求（`pro.*`・ストア・サイト） | Pro の価値は「複数チャンネル保存」だけ | 「広告なし」を Pro の価値として書くかは**判断**（CLAUDE.md の収益化方針の更新が要る） |
| app-ads.txt | なし | AdMob の案内に従い、ストアに登録した開発者サイト（`channeltimeline.jewelrysunflower.com`）の直下に置く |

「子ども・保護者を利用対象として訴求する表現の削除」（2026-10-03）は維持している。ストアの文言を直すときも戻さないこと。

---

## 8. 人の作業（AdMob 管理画面など・Claude は行っていない）

1. AdMob にアプリを2つ登録（iOS / Android）→ **本番のアプリ ID**
2. 広告ユニットを作る（各OS）: **アンカー型アダプティブバナー**1つ・**MREC 用のバナー**1つ → 本番の広告ユニット ID
3. 「プライバシーとメッセージ」で **GDPR（EEA・英国・スイス）の同意メッセージ**を作って公開（必要なら米国州法のメッセージも）
4. AdMob と Firebase（Android）を**連携**（広告 ARPU を Firebase で見るため）
5. `app-ads.txt` を開発者サイトに置く
6. ストア側: App のプライバシー、データセーフティ、「広告を含む」、説明文（上の表）
7. 本番 ID をこのリポジトリに入れる（3章）→ リリース

---

## 9. 確認したこと（2026-10-03）

Android（エミュレーター API 36・デバッグ＝テスト広告）:
- 無料: 動画一覧の下にアンカー型バナー、最初の画面の保存チャンネルの下に MREC（「広告」表示つき）が出た
- 保存チャンネル0件の最初の画面には MREC が出ない
- Pro（端末内の Pro フラグを立てて起動）: どちらも出ない。**アプリのプロセスに UMP・Ads のログが1行も出ない**
  （＝同意の確認・初期化・リクエストを行っていない）
- 機内モード: 広告の場所は空かず、一覧は保存済みのものから開け、落ちない
- EEA（`adsEea`）: 起動時に同意フォームが出る → 「同意しない」でも限定広告が出る →
  「このアプリについて」に「広告のプライバシー設定」が出て、押すとフォームが開く
- 再生画面に広告は出ない。プレイヤーの再生・自動再生の切り替え・移動ボタンは従来どおり
- リリース（R8・本番 ID なし）: 広告は出ず、UMP・Ads のログも0。動画の再生も動く

iOS:
- GitHub Actions の iOS Build（`feature/admob-ads`）でビルド成功・テスト 206 件成功（広告の判定テストを含む）
- 実機確認用に **TestFlight 1.3.90（build 40）** を上げた。ブランチ `testflight/admob-testads` で、
  リリース設定でも Google の**テスト用**広告ユニットが入っている。
  ⚠️ **審査に出さない・main に入れない。** `docs/AppStore/do-not-submit-builds.txt` に登録済みで、
  `attach-build` はこのビルドを選ばず（表示バージョンも別）、`submit` も拒否する。確認が終わったら期限切れにする

未確認:
- 実際の購入・復元での切り替わり（エミュレーターに Play の購入環境が無い）。
  判定は単体テストと「Pro フラグを立てた起動」で確認した
