// /marketing（CTV Marketing Ops・内部管理画面）のログイン。
// パスワードは Cloudflare Pages の秘密値 MARKETING_PASSWORD、セッションの署名鍵は MARKETING_SESSION_SECRET。
// どちらもリポジトリには書かない（npx wrangler pages secret put で登録）。
// パスワードか署名鍵を変えると、発行済みのセッションはすべて無効になる。

export const COOKIE = 'ctv_ops_session';
const SESSION_DAYS = 30;
const enc = new TextEncoder();

function b64url(bytes) {
  let s = '';
  for (const b of new Uint8Array(bytes)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function hmacKey(env) {
  return crypto.subtle.importKey(
    'raw', enc.encode(`${env.MARKETING_SESSION_SECRET}:${env.MARKETING_PASSWORD}`),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'],
  );
}

async function sign(env, payload) {
  return b64url(await crypto.subtle.sign('HMAC', await hmacKey(env), enc.encode(`ctv-ops:${payload}`)));
}

/** 長さに関係なく一定時間で比べる（パスワードの推測に時間差を使わせない）。 */
export async function sameSecret(a, b) {
  const [x, y] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(String(a))),
    crypto.subtle.digest('SHA-256', enc.encode(String(b))),
  ]);
  return crypto.subtle.timingSafeEqual(x, y);
}

export function isConfigured(env) {
  return Boolean(env.MARKETING_PASSWORD && env.MARKETING_SESSION_SECRET && env.MARKETING_KV);
}

export async function issueCookie(env) {
  const exp = Date.now() + SESSION_DAYS * 86400 * 1000;
  const token = `${exp}.${await sign(env, exp)}`;
  return `${COOKIE}=${token}; Path=/marketing; Max-Age=${SESSION_DAYS * 86400}; HttpOnly; Secure; SameSite=Strict`;
}

export function clearCookie() {
  return `${COOKIE}=; Path=/marketing; Max-Age=0; HttpOnly; Secure; SameSite=Strict`;
}

export async function hasSession(request, env) {
  const cookie = request.headers.get('Cookie') || '';
  const match = cookie.match(new RegExp(`(?:^|;\\s*)${COOKIE}=([^;]+)`));
  if (!match) return false;
  const [exp, sig] = match[1].split('.');
  if (!exp || !sig || !/^\d+$/.test(exp) || Number(exp) < Date.now()) return false;
  return sameSecret(sig, await sign(env, exp));
}

export function loginPage({ error = '', status = 200 } = {}) {
  const html = `<!doctype html><html lang="ja"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><meta name="robots" content="noindex, nofollow">
<title>CTV Marketing Ops</title>
<style>
:root{color-scheme:light dark;font-family:system-ui,-apple-system,"Segoe UI","Hiragino Sans","Yu Gothic UI",sans-serif}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:Canvas;color:CanvasText}
form{width:min(320px,calc(100vw - 32px));display:grid;gap:10px}
h1{font-size:16px;margin:0 0 4px}
input,button{font:inherit;padding:8px 10px;border-radius:4px;border:1px solid #9aa3b2}
button{background:#2f6fde;border-color:#2f6fde;color:#fff;cursor:pointer}
.e{color:#b42318;font-size:13px}
</style></head><body>
<form method="post" action="/marketing/api/login">
<h1>CTV Marketing Ops</h1>
<input type="password" name="password" autocomplete="current-password" placeholder="パスワード" required autofocus>
<button>ログイン</button>
${error ? `<div class="e">${error}</div>` : ''}
</form></body></html>`;
  return new Response(html, {
    status,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Robots-Tag': 'noindex, nofollow',
      'X-Frame-Options': 'DENY',
    },
  });
}

export function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Robots-Tag': 'noindex' },
  });
}
