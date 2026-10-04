/**
 * アプリ（Android / iOS）の最初の案内「人気動画から選ぶ」に並べる、国ごとの人気動画。
 * GET /api/popular?region=JP
 *
 * 【なぜサーバーで持つか】（2026-10-05・ユーザー判断）
 * アプリから直接 YouTube Data API を呼ぶと、開くたび・入れ直すたびに quota を 1 使う
 * （2,000 人が 5 回入れ直すだけで 1 日 10,000 の上限に届く）。ここで国ごとに 1 時間だけ
 * エッジに置いておけば、Google への問い合わせは「国の数 × 1 時間に 1 回」程度で頭打ちになる。
 *
 * 【やっていないこと】
 * - アプリから受け取るのは国コード（2 文字）だけ。端末やユーザーを識別する情報は受け取らない・記録しない。
 * - 汎用の中継ではない。chart=mostPopular の videos.list しか呼ばない。
 * - スクレイピングはしない。公式の Data API v3 だけを使う。返すのは一覧に出す公開情報だけ。
 *
 * 【quota】videos.list（chart=mostPopular）は 1 回 1 unit。
 * キーは Web 体験版と同じ `YOUTUBE_API_KEY`（アプリが一覧の取得に使うキーとは別）。
 */

const API = 'https://www.googleapis.com/youtube/v3/videos';
const TTL = 60 * 60; // 1時間
const MAX_RESULTS = 50;
const REGION_RE = /^[A-Z]{2}$/;

const json = (body, status = 200, ttl = 0) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': ttl ? `public, max-age=${ttl}` : 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });

function bestThumb(thumbnails) {
  if (!thumbnails) return null;
  const t = thumbnails.medium || thumbnails.high || thumbnails.default;
  return t && t.url ? t.url : null;
}

/** videos.list の答えを、アプリが使う形にする（同じチャンネルは最初の1本だけ）。 */
export function toItems(data) {
  const seen = new Set();
  const items = [];
  for (const v of (data && data.items) || []) {
    const s = v.snippet || {};
    if (!v.id || !s.channelId || seen.has(s.channelId)) continue;
    seen.add(s.channelId);
    items.push({
      videoId: v.id,
      title: s.title || '',
      channelId: s.channelId,
      channelTitle: s.channelTitle || '',
      thumbnailUrl: bestThumb(s.thumbnails),
    });
  }
  return items;
}

async function fetchPopular(region, key) {
  const url = new URL(API);
  url.searchParams.set('part', 'snippet');
  url.searchParams.set('chart', 'mostPopular');
  url.searchParams.set('maxResults', String(MAX_RESULTS));
  if (region) url.searchParams.set('regionCode', region);
  url.searchParams.set('key', key);
  const res = await fetch(url.toString(), { headers: { accept: 'application/json' } });
  if (!res.ok) return null;
  return res.json();
}

export async function onRequestGet({ request, env, waitUntil }) {
  const key = env.YOUTUBE_API_KEY;
  if (!key) return json({ error: 'not_configured' }, 503);

  const raw = (new URL(request.url).searchParams.get('region') || '').toUpperCase();
  const region = REGION_RE.test(raw) ? raw : 'US';

  // キャッシュのキーは国だけで決める（APIキーや、その他の問い合わせ内容は含めない）。
  const cacheKey = new Request(`https://cache.internal/popular/${region}`, { method: 'GET' });
  const cache = caches.default;
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  let data = null;
  try {
    data = await fetchPopular(region, key);
    // その国の一覧が無い（YouTube が対応していない国など）ときは、国を指定せずに取り直す。
    if (!data || !(data.items || []).length) data = await fetchPopular(null, key);
  } catch {
    data = null;
  }
  if (!data) return json({ error: 'upstream' }, 502);

  const response = json({ region, items: toItems(data) }, 200, TTL);
  waitUntil(cache.put(cacheKey, response.clone()));
  return response;
}
