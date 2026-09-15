// Watch Queue モードの「考えるところ」。DOM にも通信にも触らない純粋関数だけを置く。
//
// Queue Launch Contract V1（docs/watch-queue-mode.md）:
//   https://channeltimeline.jewelrysunflower.com/watch-queue#v=1&ids=VIDEO_ID1,VIDEO_ID2,...
// キューは URL の # 以降（フラグメント）で受け取る。フラグメントはブラウザがサーバーへ送らない。

import { fmt } from './model.js';

export const QUEUE_CONTRACT_VERSION = '1';
/** 受け付ける動画の最大本数（これを超えた分は無視して、その旨を表示する）。 */
export const QUEUE_MAX_IDS = 500;

const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;

/**
 * location.hash を読み取る。
 * @returns {{ok:true, ids:string[], truncated:boolean} | {ok:false, reason:'missing'|'version'|'empty'}}
 * - v が 1 でなければ受け付けない（将来の版を誤って解釈しない）
 * - 形の正しくない ID と重複は捨て、残りの順番はそのまま守る
 */
export function parseQueueHash(hash) {
  const raw = String(hash || '').replace(/^#/, '');
  if (!raw) return { ok: false, reason: 'missing' };
  const params = new URLSearchParams(raw);
  if (params.get('v') !== QUEUE_CONTRACT_VERSION) return { ok: false, reason: 'version' };

  const ids = [];
  const seen = new Set();
  let truncated = false;
  for (const part of (params.get('ids') || '').split(',')) {
    const id = part.trim();
    if (!VIDEO_ID_RE.test(id) || seen.has(id)) continue;
    if (ids.length === QUEUE_MAX_IDS) {
      truncated = true;
      break;
    }
    seen.add(id);
    ids.push(id);
  }
  if (!ids.length) return { ok: false, reason: 'empty' };
  return { ok: true, ids, truncated };
}

/** from より後ろで、再生できる最初の位置。無ければ -1。 */
export function nextPlayableIndex(length, from, isUnplayable = () => false) {
  for (let i = Math.max(-1, from) + 1; i < length; i += 1) {
    if (!isUnplayable(i)) return i;
  }
  return -1;
}

/** まだ再生し終えていない・再生できる最初の位置（「次に見る」）。無ければ -1。 */
export function upNextIndex(length, isPlayed = () => false, isUnplayable = () => false) {
  for (let i = 0; i < length; i += 1) {
    if (!isPlayed(i) && !isUnplayable(i)) return i;
  }
  return -1;
}

/** 「3 videos」「1 video」「3本」。単数・複数は Intl.PluralRules で選ぶ。 */
export function countText(copy, count, lang) {
  let rule = 'other';
  try {
    rule = new Intl.PluralRules(lang).select(count);
  } catch {
    /* 未知の言語コードでも表示は続ける */
  }
  return fmt(rule === 'one' ? copy.countOne : copy.countOther, count.toLocaleString(lang));
}
