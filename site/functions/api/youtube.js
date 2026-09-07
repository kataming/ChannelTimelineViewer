/**
 * Web体験版（/[lang]/try/）が使う YouTube Data API v3 の中継。
 *
 * 【なぜ中継するか】
 * サイトは静的（Astro SSG）なので、ブラウザから直接 Data API を叩くには
 * APIキーを JavaScript に埋め込むしかない。それを避けるため、Cloudflare Pages Functions
 * （＝この関数）でキーをサーバー側に置き、必要な呼び出しだけを通す。
 *
 * 【やっていないこと】
 * - 汎用プロキシではない。`op` で決まった3種類の呼び出ししか通さない（任意のURLは転送しない）。
 * - スクレイピングはしない。公式の Data API v3 だけを使う。
 * - 動画そのものの取得・保存はしない。返すのは一覧に出すための公開情報だけ。
 *
 * 【quota について】
 * channels.list / playlistItems.list / videos.list はいずれも 1 unit。
 * search.list だけ 100 unit なので、ハンドルで引けなかったときの最後の手段にしている。
 * 同じ問い合わせが Google まで届かないよう、エッジ（Cache API）に置いてから返す。
 *
 * 【設定】
 * Cloudflare Pages のプロジェクト設定 → 環境変数に `YOUTUBE_API_KEY` を入れる。
 * ⚠️ iOS / Android アプリが使っているキーとは**別のキー**にすること。
 *    Web の利用でアプリ側の日次 quota を使い切ってしまわないようにするため。
 */

const API = 'https://www.googleapis.com/youtube/v3';

// エッジに置いておく時間（秒）。
const TTL = {
  channel: 60 * 60 * 12, // 12時間
  videos: 60 * 60 * 6, // 6時間（新着は「新着を確認」で取り直せる）
  video: 60 * 60 * 24 * 7, // 7日（動画→投稿チャンネルの対応は変わらない）
  search: 60 * 60 * 24, // 24時間（100 unit なので長めに持つ）
};

const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const TOKEN_RE = /^[A-Za-z0-9_\-=.]{1,256}$/;

const json = (body, status = 200, ttl = 0) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': ttl ? `public, max-age=${ttl}` : 'no-store',
      'x-content-type-options': 'nosniff',
    },
  });

const fail = (code, status = 400) => json({ error: code }, status);

function bestThumb(thumbnails) {
  if (!thumbnails) return null;
  const t = thumbnails.medium || thumbnails.high || thumbnails.default;
  return t && t.url ? t.url : null;
}

/**
 * Google への1回のGET。エッジに同じ答えがあればそれを使う。
 * 返り値は { ok, data } または { ok:false, error, status }。
 */
async function callAPI(path, params, key, ttl, ctx) {
  const url = new URL(`${API}/${path}`);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
  }

  // キャッシュのキーにAPIキーは含めない（キーを差し替えても同じ答えを使えるように）。
  const cacheKey = new Request(url.toString(), { method: 'GET' });
  const cache = caches.default;

  const hit = await cache.match(cacheKey);
  if (hit) return { ok: true, data: await hit.json() };

  url.searchParams.set('key', key);
  let res;
  try {
    res = await fetch(url.toString(), { headers: { accept: 'application/json' } });
  } catch {
    return { ok: false, error: 'network', status: 502 };
  }

  const text = await res.text();
  if (!res.ok) {
    if (res.status === 403 && /quotaExceeded|dailyLimitExceeded|rateLimitExceeded/.test(text)) {
      return { ok: false, error: 'quota', status: 429 };
    }
    if (res.status === 404 || res.status === 400) return { ok: false, error: 'notFound', status: 404 };
    return { ok: false, error: 'upstream', status: 502 };
  }

  let data;
  try {
    data = JSON.parse(text);
  } catch {
    return { ok: false, error: 'upstream', status: 502 };
  }

  // 成功したときだけエッジに置く（put の完了は待たない）。
  const store = new Response(JSON.stringify(data), {
    headers: { 'content-type': 'application/json', 'cache-control': `public, max-age=${ttl}` },
  });
  if (ctx && typeof ctx.waitUntil === 'function') ctx.waitUntil(cache.put(cacheKey, store));
  else await cache.put(cacheKey, store);

  return { ok: true, data };
}

/** channels.list の結果を、体験版が使う形に整える。 */
function shapeChannel(data) {
  const item = data && data.items && data.items[0];
  if (!item) return null;
  const snippet = item.snippet || {};
  const related = item.contentDetails && item.contentDetails.relatedPlaylists;
  return {
    id: item.id,
    title: snippet.title || '',
    thumb: bestThumb(snippet.thumbnails),
    uploads: (related && related.uploads) || null,
  };
}

const CHANNEL_PART = 'snippet,contentDetails';

async function channelBy(params, key, ctx) {
  const r = await callAPI('channels', { part: CHANNEL_PART, ...params }, key, TTL.channel, ctx);
  if (!r.ok) return { error: r.error, status: r.status };
  const channel = shapeChannel(r.data);
  return channel ? { channel } : { error: 'notFound', status: 404 };
}

async function handleChannel(searchParams, key, ctx) {
  const id = searchParams.get('id');
  const handle = searchParams.get('handle');
  const user = searchParams.get('user');
  const name = searchParams.get('name');

  if (id) {
    if (!ID_RE.test(id)) return fail('invalid');
    const r = await channelBy({ id }, key, ctx);
    return r.channel ? json(r, 200, TTL.channel) : fail(r.error, r.status);
  }

  if (handle) {
    const clean = handle.replace(/^@/, '');
    if (!ID_RE.test(clean)) return fail('invalid');
    const r = await channelBy({ forHandle: `@${clean}` }, key, ctx);
    return r.channel ? json(r, 200, TTL.channel) : fail(r.error, r.status);
  }

  if (user) {
    if (!ID_RE.test(user)) return fail('invalid');
    const r = await channelBy({ forUsername: user }, key, ctx);
    return r.channel ? json(r, 200, TTL.channel) : fail(r.error, r.status);
  }

  if (name) {
    // youtube.com/SomeName のような古いカスタムURL。
    // いまはハンドルと同じであることが多いので、まず 1 unit の forHandle で試す。
    if (!ID_RE.test(name)) return fail('invalid');
    const byHandle = await channelBy({ forHandle: `@${name}` }, key, ctx);
    if (byHandle.channel) return json(byHandle, 200, TTL.channel);

    // 見つからないときだけ search.list（100 unit）を1回使う。
    const found = await callAPI(
      'search',
      { part: 'snippet', type: 'channel', q: name, maxResults: 1 },
      key,
      TTL.search,
      ctx
    );
    if (!found.ok) return fail(found.error, found.status);
    const hit = found.data.items && found.data.items[0];
    const channelId = hit && hit.id ? hit.id.channelId : null;
    if (!channelId) return fail('notFound', 404);
    const r = await channelBy({ id: channelId }, key, ctx);
    return r.channel ? json(r, 200, TTL.channel) : fail(r.error, r.status);
  }

  return fail('invalid');
}

async function handleVideos(searchParams, key, ctx) {
  const playlist = searchParams.get('playlist');
  const page = searchParams.get('page') || '';
  if (!playlist || !ID_RE.test(playlist)) return fail('invalid');
  if (page && !TOKEN_RE.test(page)) return fail('invalid');

  const r = await callAPI(
    'playlistItems',
    {
      part: 'snippet,contentDetails',
      playlistId: playlist,
      maxResults: 50,
      pageToken: page || undefined,
    },
    key,
    TTL.videos,
    ctx
  );
  if (!r.ok) return fail(r.error, r.status);

  const items = [];
  for (const raw of r.data.items || []) {
    const snippet = raw.snippet || {};
    const details = raw.contentDetails || {};
    const videoId = details.videoId || (snippet.resourceId && snippet.resourceId.videoId);
    if (!videoId) continue;
    // 非公開・削除された動画は公開日が落ちる。並べられないので一覧に出さない。
    const published = details.videoPublishedAt || snippet.publishedAt;
    if (!published) continue;
    items.push({ id: videoId, title: snippet.title || '', published });
  }

  return json({ items, next: r.data.nextPageToken || null }, 200, TTL.videos);
}

async function handleVideoChannel(searchParams, key, ctx) {
  const v = searchParams.get('v');
  if (!v || !ID_RE.test(v)) return fail('invalid');
  const r = await callAPI('videos', { part: 'snippet', id: v }, key, TTL.video, ctx);
  if (!r.ok) return fail(r.error, r.status);
  const item = r.data.items && r.data.items[0];
  const channelId = item && item.snippet ? item.snippet.channelId : null;
  if (!channelId) return fail('notFound', 404);
  return json({ channelId }, 200, TTL.video);
}

export async function onRequestGet(context) {
  const { request, env } = context;
  const key = env && env.YOUTUBE_API_KEY;
  if (!key) {
    // キー未設定でも「サイトが壊れている」ようには見せない。
    // 体験版の画面が「いまは使えない」と案内し、ストアへの導線だけ残す。
    return fail('notConfigured', 503);
  }

  const { searchParams } = new URL(request.url);
  switch (searchParams.get('op')) {
    case 'channel':
      return handleChannel(searchParams, key, context);
    case 'videos':
      return handleVideos(searchParams, key, context);
    case 'videoChannel':
      return handleVideoChannel(searchParams, key, context);
    default:
      return fail('invalid');
  }
}

/** GET 以外は受け付けない。 */
export async function onRequest(context) {
  if (context.request.method !== 'GET') {
    return new Response('Method Not Allowed', { status: 405, headers: { allow: 'GET' } });
  }
  return onRequestGet(context);
}
