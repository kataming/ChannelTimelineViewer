// Queue Launch Contract V2 で来たときだけ使う、キュー本体の取り寄せ。
//
// V1（#v=1&ids=…）は動画IDを URL に全部並べていた。V2 では URL に載るのは推測できない
// queueId だけで、並び自体は同期サーバーが持つ。**鍵は URL そのもの**という点は V1 と同じで、
// 露出する情報はむしろ少ない。
//
// ここで取るのは「動画IDの並びとキュー名」だけ。タイトルなどは、これまでどおり
// 自サイトの中継（/api/youtube）から引く（同期サーバーに視聴の情報を集めない）。
//
// 通常ページはこのファイルを読み込まない（Watch Queue モードのときだけ）。

import { TrialApiError } from './api.js';

/** 同期サーバー（Chrome 拡張の Watch Queue V2 と同じ場所）。 */
export const SYNC_ORIGIN = 'https://watch-queue-sync.atamitrading.workers.dev';

const TIMEOUT_MS = 10000;

/**
 * 共有リンクのキューを読む（認証なし・読み取りだけ）。
 * @returns {Promise<{queueId:string, name:string, version:number, videoIds:string[]}>}
 * @throws {TrialApiError} network / notFound / disabled / rateLimited / unknown
 */
export async function fetchSharedQueue(queueId) {
  const controller = typeof AbortController === 'function' ? new AbortController() : null;
  const timer = controller ? setTimeout(() => controller.abort(), TIMEOUT_MS) : null;

  let res;
  try {
    res = await fetch(`${SYNC_ORIGIN}/v2/shared/queues/${encodeURIComponent(queueId)}`, {
      headers: { accept: 'application/json' },
      // 同期サーバーに Cookie を送らない・受け取らない。
      credentials: 'omit',
      ...(controller ? { signal: controller.signal } : {}),
    });
  } catch {
    throw new TrialApiError('network');
  } finally {
    if (timer) clearTimeout(timer);
  }

  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }

  if (!res.ok || !data || data.error) {
    if (res.status === 404) throw new TrialApiError('notFound');
    if (res.status === 503) throw new TrialApiError('disabled');
    if (res.status === 429) throw new TrialApiError('rateLimited');
    throw new TrialApiError((data && data.error) || 'unknown');
  }

  const videoIds = Array.isArray(data.videoIds) ? data.videoIds.filter((id) => typeof id === 'string') : [];
  if (!videoIds.length) throw new TrialApiError('notFound');
  return { queueId: String(data.queueId || queueId), name: String(data.name || ''), version: Number(data.version) || 0, videoIds };
}
