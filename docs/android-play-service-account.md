# Play への自動アップロード用サービスアカウントを作る（任意・一度だけ）

GitHub Actions から Google Play へ AAB を直接送るための設定。**必須ではない**。
初回リリースは Play Console へ手でアップロードすれば足りる。2回目以降の手間を減らしたいときに作る。

作ったサービスアカウントは **Play のデベロッパーアカウント単位**なので、
`sunflower-room-partner-kit` など他のアプリでも同じものを使い回せる（アプリごとに権限を付ける）。

---

## 1. Play Console と Google Cloud を紐づける

1. https://play.google.com/console → 左下の **設定** → **API アクセス**
2. 「Google Cloud プロジェクトにリンク」
   - 既存のプロジェクトを使ってもよい（YouTube API キーを作ったプロジェクトとは**別でも同じでも可**）
   - 迷ったら新規作成でよい

## 2. サービスアカウントを作る

1. 同じ「API アクセス」画面の **サービスアカウント** → 「新しいサービスアカウントを作成」
2. 案内に従って Google Cloud Console が開く → **サービスアカウントを作成**
   - 名前: `play-publisher` など分かる名前
   - **ロール（権限）は付けなくてよい**（Play 側で権限を与えるため）
3. 作成したサービスアカウント → **キー** タブ → 「鍵を追加」→ **JSON** → ダウンロード
   - このJSONは**パスワードと同じ扱い**。Git に入れない、チャットに貼らない

## 3. Play Console 側で権限を与える

1. Play Console → **ユーザーとアクセス権**
2. 一覧に先ほどのサービスアカウント（`...@....iam.gserviceaccount.com`）が出てくる → 選択
3. アクセス権を設定
   - 対象: **このアプリ**（`Channel Timeline Viewer`）だけで十分。全アプリに広げてもよい
   - 権限: **リリース** 系にチェック
     - 「製品版リリースの管理」
     - 「テスト版リリースの管理」
     - 「アプリ情報の編集と公開」（掲載情報も自動化したい場合）
4. 招待／保存

> 権限の反映に数分〜数時間かかることがある。直後に失敗したら少し待って再試行する。

## 4. GitHub に登録する

1. https://github.com/kataming/ChannelTimelineViewer/settings/secrets/actions
2. New repository secret
   - 名前: **`GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`**
   - 値: ダウンロードした JSON の**中身をそのまま**貼り付け

## 5. 使う

GitHub → Actions → **Android Release** → Run workflow

| 入力 | 値 |
| --- | --- |
| `version_name` | 例 `1.0.1` |
| `upload_to_play` | **オン** |
| `release_notes` | テスターや利用者に見せる変更点 |

内部テストトラックへ送られる。製品版へ出すときは Play Console でそのリリースを「製品版に昇格」する
（いきなり製品版へ自動投入しない作りにしてある。事故を防ぐため）。

---

## 注意

- **Play の API では「まだ1度もリリースが無いアプリ」への最初のアップロードができない。**
  初回だけは Play Console から手でアップロードする（このアプリは内部テストで実施済み）。
- サービスアカウントのJSONが漏れると、第三者がアプリを更新できてしまう。GitHub Secrets か
  ローカルの資格情報フォルダ（`C:\Users\atami\Desktop\api\` など Git 管理外）にだけ置く。
- 不要になったら Google Cloud 側で鍵を削除すれば失効する。
