// Watch Queue モードの「考えるところ」。DOM にも通信にも触らない純粋関数だけを置く。
//
// Queue Launch Contract V1（docs/watch-queue-mode.md）:
//   https://channeltimeline.jewelrysunflower.com/watch-queue#v=1&ids=VIDEO_ID1,VIDEO_ID2,...
// キューは URL の # 以降（フラグメント）で受け取る。フラグメントはブラウザがサーバーへ送らない。

import { fmt } from './model.js';

export const QUEUE_CONTRACT_VERSION = '1';
/** 受け付ける版。V2 ではキュー本体は同期サーバーにあり、URL には鍵になる queueId だけが載る。 */
export const QUEUE_CONTRACT_VERSIONS = ['1', '2'];
/** 受け付ける動画の最大本数（これを超えた分は無視して、その旨を表示する）。 */
export const QUEUE_MAX_IDS = 500;

const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;
const QUEUE_ID_RE = /^[A-Za-z0-9_-]{4,64}$/;

/**
 * location.hash を読み取る。
 * @returns {{ok:true, version:1, ids:string[], truncated:boolean}
 *         | {ok:true, version:2, queueId:string}
 *         | {ok:false, reason:'missing'|'version'|'empty'}}
 * - 知らない版は受け付けない（将来の版を誤って解釈しない）
 * - V1: 形の正しくない ID と重複は捨て、残りの順番はそのまま守る
 * - V2: queueId の形だけを確かめる（中身の取得は通信する側の仕事）
 */
export function parseQueueHash(hash) {
  const raw = String(hash || '').replace(/^#/, '');
  if (!raw) return { ok: false, reason: 'missing' };
  const params = new URLSearchParams(raw);
  const version = params.get('v');
  if (!QUEUE_CONTRACT_VERSIONS.includes(version)) return { ok: false, reason: 'version' };

  if (version === '2') {
    const queueId = (params.get('q') || '').trim();
    if (!QUEUE_ID_RE.test(queueId)) return { ok: false, reason: 'empty' };
    return { ok: true, version: 2, queueId };
  }

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
  return { ok: true, version: 1, ids, truncated };
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
