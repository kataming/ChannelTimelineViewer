// キューの「考えるところ」。D1 にも HTTP にも触らない純粋関数だけを置く（テストしやすくするため）。

import { isVideoId, text } from './http.js';

export const MAX_NAME_LENGTH = 60;
export const MAX_TITLE_LENGTH = 300;

/**
 * クライアントから届いた items を、保存できる形に整える。
 * - videoId の形が正しいものだけ
 * - 同じ videoId は最初の1つだけ
 * - **順番は届いた配列のまま**（added_at では並べ替えない）。position は 0 始まりで振り直す
 */
export function normalizeItems(items, maxItems) {
  if (!Array.isArray(items)) return { ok: false, reason: 'items' };
  if (items.length > maxItems) return { ok: false, reason: 'tooManyItems' };
  const seen = new Set();
  const normalized = [];
  for (const raw of items) {
    if (!raw || typeof raw !== 'object') return { ok: false, reason: 'item' };
    if (!isVideoId(raw.videoId)) return { ok: false, reason: 'videoId' };
    if (seen.has(raw.videoId)) continue;
    seen.add(raw.videoId);
    normalized.push({
      videoId: raw.videoId,
      position: normalized.length,
      title: text(raw.title, MAX_TITLE_LENGTH),
      channelName: text(raw.channelName, MAX_NAME_LENGTH),
      durationText: text(raw.durationText, 32),
      addedAt: text(raw.addedAt, 40),
    });
  }
  return { ok: true, items: normalized };
}

export function normalizeQueueName(name) {
  return text(name, MAX_NAME_LENGTH);
}

/**
 * 課金の判定。Collection = 保存チャンネル数 + キュー数。
 * 無料は 1 つまで、Pro は複数。キュー内の本数は数に影響しない。
 */
export function collectionLimitState({ isPro, channelCount, queueCount }) {
  const total = Math.max(0, channelCount | 0) + Math.max(0, queueCount | 0);
  return {
    total,
    isPro: Boolean(isPro),
    canCreateAnother: Boolean(isPro) || total < 1,
  };
}

/**
 * 競合の扱い（CRDT は使わない）。
 * クライアントは自分が知っている version を baseVersion として送る。
 * サーバーの version と食い違っていたら拒否し、クライアントに取り直させる。
 */
export function checkVersion(currentVersion, baseVersion) {
  if (baseVersion === null || baseVersion === undefined) return { ok: true, next: currentVersion + 1 };
  if (typeof baseVersion !== 'number' || !Number.isInteger(baseVersion) || baseVersion < 0) {
    return { ok: false, reason: 'baseVersion' };
  }
  if (baseVersion !== currentVersion) return { ok: false, reason: 'conflict' };
  return { ok: true, next: currentVersion + 1 };
}

/** クライアントが V2 を理解できるか（古いモバイルを壊れた画面へ誘導しないため）。 */
export function hasWatchQueueV2Capability(capabilities) {
  return String(capabilities || '')
    .split(',')
    .map((value) => value.trim())
    .includes('watch_queue_v2');
}
