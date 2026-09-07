// 体験版から中継（/api/youtube）を呼ぶところ。
// APIキーはサーバー側（Cloudflare Pages Functions）にあり、ブラウザには渡らない。

const ENDPOINT = '/api/youtube';

/** 中継が返したエラーコードをそのまま持つ例外。 */
export class TrialApiError extends Error {
  constructor(code) {
    super(code);
    this.name = 'TrialApiError';
    this.code = code;
  }
}

async function call(params) {
  const url = new URL(ENDPOINT, location.origin);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, String(v));
  }

  let res;
  try {
    res = await fetch(url.toString(), { headers: { accept: 'application/json' } });
  } catch {
    throw new TrialApiError('network');
  }

  let data = null;
  try {
    data = await res.json();
  } catch {
    throw new TrialApiError(res.ok ? 'unknown' : 'network');
  }

  if (!res.ok || (data && data.error)) {
    throw new TrialApiError((data && data.error) || 'unknown');
  }
  return data;
}

/** 動画IDから、その動画を投稿したチャンネルIDを引く。 */
export async function channelIdForVideo(videoId) {
  const data = await call({ op: 'videoChannel', v: videoId });
  return data.channelId;
}

/**
 * 解析済みの識別子（resolve.js の parseInput の結果）からチャンネルを解決する。
 * @returns {{id:string,title:string,thumb:string|null,uploads:string|null}}
 */
export async function resolveChannel(identifier) {
  if (!identifier) throw new TrialApiError('invalid');

  const params = { op: 'channel' };
  switch (identifier.kind) {
    case 'channelId':
      params.id = identifier.value;
      break;
    case 'handle':
      params.handle = identifier.value;
      break;
    case 'username':
      params.user = identifier.value;
      break;
    case 'name':
      params.name = identifier.value;
      break;
    case 'video': {
      params.id = await channelIdForVideo(identifier.value);
      break;
    }
    default:
      throw new TrialApiError('invalid');
  }

  const data = await call(params);
  if (!data.channel || !data.channel.id) throw new TrialApiError('notFound');
  return data.channel;
}

/**
 * uploads プレイリストの1ページ（最大50件）。
 * @returns {{items:Array<{id:string,title:string,published:number}>, next:string|null}}
 */
export async function fetchVideosPage(playlistId, pageToken) {
  const data = await call({ op: 'videos', playlist: playlistId, page: pageToken || '' });
  const items = [];
  for (const raw of data.items || []) {
    const published = Date.parse(raw.published);
    if (!raw.id || Number.isNaN(published)) continue;
    items.push({ id: raw.id, title: raw.title || '', published });
  }
  return { items, next: data.next || null };
}
