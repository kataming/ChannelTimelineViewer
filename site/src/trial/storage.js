// 体験版の保存（このブラウザの localStorage だけ）。
//
// サーバーには何も送らない。アカウントも同期も無い。
// プライベートブラウズ等で保存できない環境でも例外で止まらないよう、すべて try/catch で包む。

const NS = 'ctv-web';
const K_CHANNEL = `${NS}:channel:v1`;
const K_PREFS = `${NS}:prefs:v1`;
const kVideos = (channelId) => `${NS}:videos:v1:${channelId}`;
const kState = (channelId) => `${NS}:state:v1:${channelId}`;

/** localStorage が使えるか（プライベートブラウズ・設定で無効なことがある）。 */
export function storageAvailable() {
  try {
    const probe = `${NS}:probe`;
    localStorage.setItem(probe, '1');
    localStorage.removeItem(probe);
    return true;
  } catch {
    return false;
  }
}

function readJSON(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return fallback;
    const value = JSON.parse(raw);
    return value === null || value === undefined ? fallback : value;
  } catch {
    return fallback;
  }
}

function writeJSON(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch {
    // 容量超過・保存不可。画面は動き続けてよい（記録が残らないだけ）。
    return false;
  }
}

function remove(key) {
  try {
    localStorage.removeItem(key);
  } catch {
    /* 消せなくても続行する */
  }
}

// --- 保存中のチャンネル（1件だけ） ---

export function loadChannel() {
  const c = readJSON(K_CHANNEL, null);
  if (!c || typeof c.id !== 'string' || !c.id) return null;
  return c;
}

export function saveChannel(channel) {
  return writeJSON(K_CHANNEL, {
    id: channel.id,
    title: channel.title || '',
    thumb: channel.thumb || null,
    uploads: channel.uploads || null,
    savedAt: Date.now(),
  });
}

export function clearChannel(channelId) {
  remove(K_CHANNEL);
  if (channelId) {
    remove(kVideos(channelId));
    remove(kState(channelId));
  }
}

// --- 動画一覧（保存して2回目以降すぐ出す） ---
//
// 1本 [id, タイトル, 公開日(ms)] の配列で持つ。サムネイルURLは videoId から組み立てられるので保存しない。

export function loadVideos(channelId) {
  const entry = readJSON(kVideos(channelId), null);
  if (!entry || !Array.isArray(entry.i)) return null;
  const videos = [];
  for (const row of entry.i) {
    if (!Array.isArray(row) || typeof row[0] !== 'string') continue;
    videos.push({ id: row[0], title: row[1] || '', published: Number(row[2]) || 0 });
  }
  return { videos, updatedAt: Number(entry.a) || 0, truncated: Boolean(entry.t) };
}

export function saveVideos(channelId, videos, { truncated = false } = {}) {
  return writeJSON(kVideos(channelId), {
    a: Date.now(),
    t: truncated ? 1 : 0,
    i: videos.map((v) => [v.id, v.title, v.published]),
  });
}

// --- 視聴済み・スキップ・メモ・再生位置・表示設定 ---

const EMPTY_STATE = { w: {}, s: {}, m: {}, p: {}, last: null, sort: 'oldest', filter: 'all' };

export function loadState(channelId) {
  const raw = readJSON(kState(channelId), null);
  if (!raw) return { ...EMPTY_STATE, w: {}, s: {}, m: {}, p: {} };
  return {
    w: raw.w && typeof raw.w === 'object' ? raw.w : {},
    s: raw.s && typeof raw.s === 'object' ? raw.s : {},
    m: raw.m && typeof raw.m === 'object' ? raw.m : {},
    p: raw.p && typeof raw.p === 'object' ? raw.p : {},
    last: typeof raw.last === 'string' ? raw.last : null,
    sort: raw.sort === 'newest' ? 'newest' : 'oldest',
    filter: ['all', 'unwatched', 'watched'].includes(raw.filter) ? raw.filter : 'all',
  };
}

export function saveState(channelId, state) {
  return writeJSON(kState(channelId), state);
}

// --- 再生の設定（チャンネルに紐づかない） ---

const DEFAULT_PREFS = {
  // 自動再生は既定オフ。ユーザーが再生画面のトグルで明示的にオンにしたときだけ働く。
  autoplay: false,
  // 続きから再生は既定オン。
  resume: true,
  repeat: 'off',
  unwatchedOnly: false,
};

export function loadPrefs() {
  const raw = readJSON(K_PREFS, null);
  if (!raw) return { ...DEFAULT_PREFS };
  return {
    autoplay: raw.autoplay === true,
    resume: raw.resume !== false,
    repeat: ['off', 'one', 'all'].includes(raw.repeat) ? raw.repeat : 'off',
    unwatchedOnly: raw.unwatchedOnly === true,
  };
}

export function savePrefs(prefs) {
  return writeJSON(K_PREFS, prefs);
}
