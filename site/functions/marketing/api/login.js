// ログイン。失敗が続いたら、その接続元からはしばらく受け付けない（総当たり対策）。
import { issueCookie, isConfigured, sameSecret } from '../../../marketing-server/auth.js';

const MAX_FAILS = 10;
const WINDOW_SECONDS = 15 * 60;

function back(url, error) {
  return new Response(null, { status: 303, headers: { Location: `${url.origin}/marketing/${error ? `?e=${error}` : ''}` } });
}

export async function onRequestPost({ request, env }) {
  if (!isConfigured(env)) return new Response('Not configured', { status: 503 });
  const url = new URL(request.url);
  const ip = request.headers.get('CF-Connecting-IP') || 'unknown';
  const failKey = `login-fail:${ip}`;
  const fails = Number(await env.MARKETING_KV.get(failKey)) || 0;
  if (fails >= MAX_FAILS) return back(url, 2);

  const form = await request.formData().catch(() => null);
  const password = form?.get('password') ?? '';
  if (!(await sameSecret(password, env.MARKETING_PASSWORD))) {
    await env.MARKETING_KV.put(failKey, String(fails + 1), { expirationTtl: WINDOW_SECONDS });
    return back(url, 1);
  }
  if (fails) await env.MARKETING_KV.delete(failKey);
  const res = back(url, 0);
  res.headers.append('Set-Cookie', await issueCookie(env));
  return res;
}

export function onRequestGet({ request }) {
  return back(new URL(request.url), 0);
}
