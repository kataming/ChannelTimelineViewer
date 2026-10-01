// /marketing 以下（CTV Marketing Ops・内部管理画面）は、すべてログインが必要。
// 静的ファイル（app.js など）もここを通るので、ログインしないと中身は一切返さない。
// ⚠️ 通常サイトからリンクしない・サイトマップに載せない・検索させない（noindex）。
import { hasSession, isConfigured, json, loginPage } from '../../marketing-server/auth.js';

const LOGIN_ERRORS = {
  1: 'パスワードが違います',
  2: '失敗が続いたため、しばらく時間をおいてください',
};

export async function onRequest(context) {
  const { request, env } = context;
  const url = new URL(request.url);
  const path = url.pathname;

  if (!isConfigured(env)) return new Response('Not configured', { status: 503 });

  // 相対パス（api/db など）が正しく解決されるよう、末尾の / をそろえる
  if (path === '/marketing') return Response.redirect(`${url.origin}/marketing/`, 301);

  // ログイン・ログアウトの処理そのものは通す
  if (path === '/marketing/api/login' || path === '/marketing/api/logout') return context.next();

  if (!(await hasSession(request, env))) {
    if (path.startsWith('/marketing/api/')) return json({ error: 'ログインが必要です' }, 401);
    return loginPage({ error: LOGIN_ERRORS[url.searchParams.get('e')] ?? '', status: 401 });
  }

  const res = await context.next();
  const out = new Response(res.body, res);
  out.headers.set('Cache-Control', 'no-store');
  out.headers.set('X-Robots-Tag', 'noindex, nofollow');
  out.headers.set('X-Frame-Options', 'DENY');
  out.headers.set('Referrer-Policy', 'no-referrer');
  return out;
}
