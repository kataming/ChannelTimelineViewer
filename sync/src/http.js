// HTTP の共通部品: CORS、JSON 応答、入力の検証、レート制限。
//
// ⚠️ CORS はブラウザ側の仕組みで、リクエスト自体は止められない。
//    だから「書き込みの許可」は必ずサーバー側でも確かめる（isAllowedOrigin + 端末トークン）。

export const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;
export const UUID_RE = /^[0-9a-fA-F-]{8,64}$/;
export const TOKEN_RE = /^[0-9a-f]{32,128}$/;
export const PLATFORMS = new Set(['extension', 'ios', 'android', 'web']);

export function allowedOrigins(env) {
  return String(env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

/** 拡張（chrome-extension://…）と公式サイトのオリジンだけを通す。 */
export function isAllowedOrigin(origin, env) {
  if (!origin) return true; // アプリ（iOS / Android）からの呼び出しには Origin が付かない
  return allowedOrigins(env).includes(origin);
}

export function corsHeaders(origin, env) {
  const headers = {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    vary: 'Origin',
  };
  if (origin && isAllowedOrigin(origin, env)) {
    headers['access-control-allow-origin'] = origin;
    headers['access-control-allow-headers'] = 'authorization, content-type';
    headers['access-control-allow-methods'] = 'GET, POST, PUT, DELETE, OPTIONS';
    headers['access-control-max-age'] = '600';
  }
  return headers;
}

export function json(body, { status = 200, origin = '', env = {} } = {}) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(origin, env) });
}

export function fail(code, { status = 400, origin = '', env = {} } = {}) {
  return json({ error: code }, { status, origin, env });
}

/** 想定外のキーが混ざった JSON は受け付けない。 */
export function hasOnlyKeys(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  return Object.keys(value).every((key) => keys.includes(key));
}

export function isVideoId(value) {
  return typeof value === 'string' && VIDEO_ID_RE.test(value);
}

export function isId(value) {
  return typeof value === 'string' && UUID_RE.test(value);
}

export function isToken(value) {
  return typeof value === 'string' && TOKEN_RE.test(value);
}

export function text(value, max) {
  if (typeof value !== 'string') return '';
  return value.replace(/\s+/g, ' ').trim().slice(0, max);
}

/** 端末トークン（生成した形＝16進のみ）を読む。 */
export function bearerToken(request) {
  const header = request.headers.get('authorization') || '';
  const match = /^Bearer\s+([0-9a-f]{32,128})$/i.exec(header.trim());
  return match ? match[1].toLowerCase() : null;
}

/** 管理トークン用。運用者が決めた任意の文字列なので、形は限定しない。 */
export function rawBearer(request) {
  const header = request.headers.get('authorization') || '';
  const match = /^Bearer\s+(\S{8,256})$/.exec(header.trim());
  return match ? match[1] : null;
}

/** D1 の1テーブルで足りる素朴なレート制限（1分窓）。 */
export async function rateLimit(env, bucket, limit) {
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - (now % 60);
  const row = await env.DB.prepare('SELECT window_start, count FROM rate_limits WHERE bucket = ?')
    .bind(bucket)
    .first();
  if (!row || row.window_start !== windowStart) {
    await env.DB.prepare(
      'INSERT INTO rate_limits (bucket, window_start, count) VALUES (?, ?, 1) ' +
        'ON CONFLICT(bucket) DO UPDATE SET window_start = excluded.window_start, count = 1',
    )
      .bind(bucket, windowStart)
      .run();
    return true;
  }
  if (row.count >= limit) return false;
  await env.DB.prepare('UPDATE rate_limits SET count = count + 1 WHERE bucket = ?').bind(bucket).run();
  return true;
}

export function clientKey(request) {
  return request.headers.get('cf-connecting-ip') || 'unknown';
}
