// CTV Marketing Ops のデータ（JSON 1 つ）を KV（MARKETING_KV）に保存する。
// ローカル版（ctv-marketing-ops の server/）と同じ API: GET で全体、PUT で全体を置き換え。
// ログインの確認は _middleware.js で済んでいる。
import { emptyDocument, normalize } from '../../../public/marketing/domain/schema.js';
import { json } from '../../../marketing-server/auth.js';

const KEY = 'db';
const MAX_BYTES = 5 * 1024 * 1024;
const BACKUP_TTL = 60 * 86400;

export async function onRequestGet({ env }) {
  const stored = await env.MARKETING_KV.get(KEY);
  return json(stored ? normalize(JSON.parse(stored)) : emptyDocument());
}

export async function onRequestPut({ request, env }) {
  const text = await request.text();
  if (text.length > MAX_BYTES) return json({ error: 'データが大きすぎます' }, 413);
  let doc;
  try {
    doc = normalize(JSON.parse(text));
  } catch (e) {
    return json({ error: e.message }, 400);
  }

  const previous = await env.MARKETING_KV.get(KEY);
  // 別の画面で先に保存されていたら上書きしない（If-Match は読み込んだときの updatedAt）
  const baseVersion = request.headers.get('If-Match');
  if (baseVersion && previous && JSON.parse(previous).updatedAt !== baseVersion) {
    return json({ error: '別の画面で先に保存されています。再読み込みしてからやり直してください' }, 409);
  }

  // 直前の版を 10 分単位で 1 つ残す（60 日で自動的に消える）。書き込み回数を増やしすぎないため
  if (previous) {
    const bucket = `backup:${new Date().toISOString().slice(0, 15)}`;
    if (!(await env.MARKETING_KV.get(bucket))) {
      await env.MARKETING_KV.put(bucket, previous, { expirationTtl: BACKUP_TTL });
    }
  }
  await env.MARKETING_KV.put(KEY, JSON.stringify(doc));
  return json(doc);
}
