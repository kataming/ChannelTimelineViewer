// 管理画面の「今すぐ取得」。Google 広告の取り込み Worker（ctv-marketing-ads-sync）をサービスバインディングで呼ぶ。
// ログインの確認は _middleware.js で済んでいる。Worker 本体は CTV の公開リポジトリには無い（ctv-marketing-ops/worker）。
import { json } from '../../../marketing-server/auth.js';

export async function onRequestPost({ env }) {
  if (!env.ADS_SYNC) return json({ status: 'error', message: '取り込み用の Worker がつながっていません' }, 503);
  const res = await env.ADS_SYNC.fetch('https://ads-sync/run', { method: 'POST' });
  const body = await res.json().catch(() => ({ status: 'error', message: `HTTP ${res.status}` }));
  // 失敗でも 200（成否は body.status）。5xx を返すと Cloudflare がエラーページに差し替えてしまう
  return json(body);
}
