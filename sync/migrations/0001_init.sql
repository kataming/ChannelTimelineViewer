-- Watch Queue V2 sync — initial schema
--
-- 保存するのは最小限だけ: キューの中身（videoId と順番と画面に出す文字）、ペアリングの識別子、
-- 端末の能力。Google アカウント情報・Cookie・閲覧履歴・検索履歴は保存しない。
-- トークンとペアリングコードは平文で持たず、SHA-256 のハッシュだけを保存する。

CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL,
  -- 課金の正本は Channel Timeline Viewer（App Store / Google Play の購入）。
  -- アプリが同期のたびに現在の状態を報告し、ここには判定用の写しだけを置く。
  is_pro INTEGER NOT NULL DEFAULT 0,
  channel_count INTEGER NOT NULL DEFAULT 0,
  entitlement_updated_at INTEGER
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  platform TEXT NOT NULL,              -- extension | ios | android | web
  capabilities TEXT NOT NULL DEFAULT '',
  client_version TEXT,
  token_hash TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER,
  revoked_at INTEGER,
  FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE INDEX IF NOT EXISTS idx_devices_group ON devices(group_id);

CREATE TABLE IF NOT EXISTS pairings (
  id TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  poll_token_hash TEXT NOT NULL,
  group_id TEXT,
  platform TEXT,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  claimed_at INTEGER,
  completed_at INTEGER,
  attempts INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_pairings_expires ON pairings(expires_at);

CREATE TABLE IF NOT EXISTS queues (
  id TEXT PRIMARY KEY,
  group_id TEXT NOT NULL,
  name TEXT NOT NULL DEFAULT '',
  version INTEGER NOT NULL DEFAULT 1,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  deleted_at INTEGER,
  FOREIGN KEY (group_id) REFERENCES groups(id)
);

CREATE INDEX IF NOT EXISTS idx_queues_group ON queues(group_id, updated_at);

CREATE TABLE IF NOT EXISTS queue_items (
  queue_id TEXT NOT NULL,
  video_id TEXT NOT NULL,
  -- 再生順は position で明示保存する（added_at から推測しない）。
  position INTEGER NOT NULL,
  title TEXT NOT NULL DEFAULT '',
  channel_name TEXT NOT NULL DEFAULT '',
  duration_text TEXT NOT NULL DEFAULT '',
  added_at TEXT NOT NULL DEFAULT '',
  PRIMARY KEY (queue_id, video_id),
  FOREIGN KEY (queue_id) REFERENCES queues(id)
);

CREATE INDEX IF NOT EXISTS idx_queue_items_order ON queue_items(queue_id, position);

-- Feature Flag などの実行時設定（再デプロイせずに切り替えるための上書き）。
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 簡易レート制限（1分あたりの呼び出し回数）。
CREATE TABLE IF NOT EXISTS rate_limits (
  bucket TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);
