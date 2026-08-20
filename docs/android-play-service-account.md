# Play への自動アップロード用サービスアカウントを作る（任意・一度だけ）

GitHub Actions から Google Play へ AAB を直接送るための設定。**必須ではない**。
初回リリースは Play Console へ手でアップロードすれば足りる。2回目以降の手間を減らしたいときに作る。

作ったサービスアカウントは **Play のデベロッパーアカウント単位**なので、
`sunflower-room-partner-kit` など他のアプリでも同じものを使い回せる（アプリごとに権限を付ける）。

---

## 1. Google Play Android Developer API を有効にする

> 以前の Play Console にあった「設定 → API アクセス」の画面は**現在のUIでは廃止**されている。
> Google Cloud 側でサービスアカウントを作り、Play Console の「ユーザーと権限」で招待する形になる。

1. https://console.cloud.google.com/ → プロジェクトを選ぶ（YouTube API キーと同じプロジェクトでよい）
2. 「APIとサービス」→「ライブラリ」→ **`Google Play Android Developer API`** を検索 → **有効にする**

## 2. サービスアカウントを作る

1. 「APIとサービス」→「認証情報」→「認証情報を作成」→ **サービス アカウント**
   （有効にした API の詳細画面にある「認証情報を作成」からでも同じ）
2. 名前: `play-publisher` など
3. **ロール（プロジェクトへの権限）は付けずに完了**（権限は Play 側で与える）
4. 作成したサービスアカウント → **「キー」タブ** → 「鍵を追加」→ **JSON** → ダウンロード
   - このJSONは**パスワードと同じ扱い**。Git に入れない、チャットに貼らない
5. サービスアカウントの**メールアドレス**（`...@<プロジェクトID>.iam.gserviceaccount.com`）をコピー
   - 見つからないときは https://console.cloud.google.com/iam-admin/serviceaccounts

## 3. Play Console で招待する

1. Play Console → 左メニュー **「ユーザーと権限」** → **「新しいユーザーを招待」**
2. メールアドレス: 2でコピーしたサービスアカウントのアドレス
3. アプリを選択: **Channel Timeline Viewer**
4. 権限（この5つ）
   - 未公開のアプリの編集、削除
   - 製品版としてのリリース、デバイスの除外、Play App Signing の使用
   - テスト版トラックとしてのアプリのリリース
   - テスト版トラックの管理、テスターリストの編集
   - ストアでの表示の管理
   - ※「管理者（すべての権限）」は付けない（権限が広すぎる）
5. 招待（反映に数分かかることがある）

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
