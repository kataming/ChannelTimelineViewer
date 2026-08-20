# Google Play の内部テストで配る（iOS の TestFlight 相当）

テスターは **Play ストアからインストール**でき、更新も自動で届く。審査もほぼ即時。
すでに Play Console のアカウントは持っている前提（`sunflower-room-partner-kit` で公開実績あり）なので、
**追加費用はかからない**。

---

## こちらで済ませてあること

| 項目 | 状態 |
| --- | --- |
| アップロード鍵（`upload.jks`）の作成 | 済み。**この鍵は無くすと同じアプリを更新できなくなる**ので後述のバックアップを必ず |
| 鍵と合言葉を GitHub Secrets に登録 | 済み（`ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS`） |
| 署名付き AAB / APK のビルド設定 | 済み（`android/app/build.gradle.kts`） |
| 内部テストへ自動アップロードするワークフロー | 済み（[`android-release.yml`](../.github/workflows/android-release.yml)） |
| ローカルでの署名ビルド確認 | 済み（AAB 11MB / APK 12MB を生成） |

### 🔑 アップロード鍵のバックアップ（重要）

鍵の実体は**リポジトリに入っていない**（`android/keystore/` は Git 管理外）。次の2つを、この PC 以外の安全な場所
（パスワードマネージャ・暗号化した外部ドライブなど）に控えておくこと。

```
android/keystore/upload.jks        アップロード鍵そのもの
android/keystore/password.txt      その合言葉（別名は upload）
```

紛失しても Play のサポートに依頼すれば鍵の入れ替えはできるが、手間と待ち時間がかかる。

---

## Play Console でやること（ユーザー）

### 1. アプリを登録する

1. https://play.google.com/console → 「アプリを作成」
2. 入力内容

   | 項目 | 値 |
   | --- | --- |
   | アプリ名 | Channel Timeline Viewer |
   | 既定の言語 | 日本語（あとで多言語を追加できる） |
   | アプリ / ゲーム | アプリ |
   | 無料 / 有料 | 無料（あとから有料に変更できる。※逆＝有料→無料は不可） |

3. 作成後、**パッケージ名が `com.deskflowlabs.channeltimelineviewer` になる**ように最初のリリースをアップロードする
   （パッケージ名は最初のアップロードで確定する）

### 2. 最初の AAB を手でアップロードする

Play の API は「まだ1度もリリースが無いアプリ」への最初のアップロードを受け付けない。**初回だけ手作業**が要る。

1. GitHub → Actions → **Android Release** → Run workflow
   - `version_name`: `1.0`
   - `upload_to_play`: **オフのまま**
2. 完了したら artifact **`android-release`** をダウンロード → `app-release.aab`
3. Play Console → 対象アプリ → テスト → **内部テスト** → 「新しいリリースを作成」
4. `app-release.aab` をアップロード → 保存 → 「リリースのレビュー」→ 公開

> 「Play アプリ署名」を有効にするか聞かれたら**有効にする**（推奨）。アップロード鍵とは別に Play が配布用の鍵で署名する。

### 3. テスターを登録する

1. 内部テスト → 「テスター」タブ → メーリングリストを作成（自分の Google アカウントを入れる）
2. 「リンクをコピー」で招待リンクが出る → その端末のブラウザで開いて参加 → Play ストアからインストール

### 4. API キーの制限に署名を追加する（**これを忘れると動画一覧が取れない**）

配り方によってアプリの署名が変わる。**署名ごとに SHA-1 を登録**しておかないと、
API キーの Android アプリ制限で弾かれ、アプリには「不明なエラーが発生しました」と出る。

| 配り方 | 署名 | SHA-1 |
| --- | --- | --- |
| CI のデバッグ APK（`android-debug-apk`） | リポジトリのデバッグ鍵 | `93:1F:B3:FE:72:80:3D:8C:A1:73:4E:7E:C1:B1:7D:EB:AA:77:2D:36` |
| CI のリリース APK（`android-release` の .apk） | アップロード鍵 | `26:C1:A2:42:CF:51:A3:06:DD:1B:DD:33:CD:28:1C:68:9C:75:26:BF` |
| **Play 内部テスト／本番** | **Play アプリ署名鍵** | Play Console に表示される値（下記） |

Play 経由で配ると署名が Play の鍵に変わるため、デバッグ鍵の SHA-1 だけでは弾かれる。

1. Play Console → 対象アプリ → 左メニュー **「アプリの完全性」** → 上部タブ **「アプリの署名」**
   （以前のUIでは「設定 → アプリの署名」。同じページに「アップロード鍵の証明書」も出る）
2. 「**アプリ署名鍵の証明書**」の **SHA-1 証明書のフィンガープリント**をコピー
3. Google Cloud Console → 認証情報 → `channel-timeline-viewer-android` のキー → Android アプリの制限に
   **パッケージ名 `com.deskflowlabs.channeltimelineviewer` ＋ その SHA-1** を追加（既存のデバッグ用はそのまま残す）
4. 保存してから**数分待つ**（制限の変更は即時に反映されないことがある）。
   端末側はアプリを一度終了（強制停止）してから開き直す。

### 5. サービスアカウントの JSON をこのリポジトリにも登録する（自動化用）

`sunflower-room-partner-kit` で使っている Play のサービスアカウントは、**同じ Play アカウント内なら使い回せる**。

1. その JSON の中身をコピー
2. https://github.com/kataming/ChannelTimelineViewer/settings/secrets/actions
   → New repository secret → 名前 **`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`** → 貼り付け
3. Play Console → ユーザーと権限 → そのサービスアカウントに **このアプリへの権限**（リリース管理）を付与

---

## 2回目以降（自動）

GitHub → Actions → **Android Release** → Run workflow

| 入力 | 意味 |
| --- | --- |
| `version_name` | 表示バージョン（例 1.0.1） |
| `upload_to_play` | **オン**にすると内部テストへ自動アップロード |
| `release_notes` | テスターに見せる変更点（任意） |

`versionCode` は実行番号を自動で使うので、重複で弾かれることはない。

---

## 補足

- 内部テストの審査は通常ほぼ即時（数分〜）。本番公開の審査とは別物。
- 内部テストは最大100人。国・地域の制限は受けない。
- 本番公開に進むときは、ストア掲載情報（説明文・スクリーンショット・プライバシーポリシー）が別途必要。
  iOS 用に7言語で用意した [`AppStore/metadata.json`](AppStore/metadata.json) の文章がそのまま下敷きに使える。
