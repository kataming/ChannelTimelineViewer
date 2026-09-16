/**
 * Watch Queue V2 — sync API（Cloudflare Worker + D1）
 *
 * 役割:
 *   - 端末のペアリング（短いコード方式。QR もカメラ権限も要らない）
 *   - キューの同期（編集の正本は Chrome 拡張。アプリ側は再生・選択・削除）
 *   - 課金判定の写しの受け渡し（正本は App Store / Google Play の購入。ここでは判定に使うだけ）
 *   - Feature Flag（OFF ならすべての V2 機能を止める＝kill switch）
 *
 * 保存しないもの: Google アカウント情報・Cookie・閲覧履歴・検索履歴・トークンの平文。
 *
 * エンドポイント:
 *   GET    /v2/config
 *   POST   /v2/pairing/start        拡張が呼ぶ  → コードを表示
 *   POST   /v2/pairing/claim        アプリが呼ぶ → コードを入力して承認
 *   POST   /v2/pairing/complete     拡張が呼ぶ  → 承認されたら端末トークンを受け取る
 *   GET    /v2/shared/queues/:queueId  共有リンクからの読み取り（認証なし・動画IDの並びだけ）
 *   GET    /v2/queues               同期（pull）
 *   PUT    /v2/queues/:queueId      同期（push・全置き換え）
 *   DELETE /v2/queues/:queueId      キュー削除
 *   GET    /v2/entitlement          いま何 Collection 使えるか
 *   POST   /v2/entitlement          アプリが購入状態を報告する
 *   GET    /v2/devices              つながっている端末
 *   POST   /v2/devices/revoke       端末の接続解除
 *   POST   /v2/admin/flag           Feature Flag の切り替え（ADMIN_TOKEN があるときだけ）
 */

import { generatePairingCode, generateId, generateToken, hash, normalizeCode, safeEqual } from './crypto.js';
import {
  bearerToken,
  clientKey,
  corsHeaders,
  fail,
  hasOnlyKeys,
  isAllowedOrigin,
  isId,
  isToken,
  json,
  rateLimit,
  rawBearer,
  text,
} from './http.js';
import {
  bumpPairingAttempts,
  countQueues,
  createDevice,
  createGroup,
  createPairing,
  deleteExpiredPairings,
  deviceByTokenHash,
  getGroup,
  getQueue,
  getSetting,
  listDevices,
  listQueuesWithItems,
  markPairingClaimed,
  markPairingCompleted,
  pairingByCodeHash,
  pairingById,
  replaceQueue,
  revokeDevice,
  setSetting,
  sharedQueueWithItems,
  softDeleteQueue,
  touchDevice,
  updateEntitlement,
} from './db.js';
import { checkVersion, collectionLimitState, normalizeItems, normalizeQueueName } from './queueModel.js';

const PAIRING_TTL_SECONDS = 600; // 10分
const PAIRING_MAX_ATTEMPTS = 5;
const CONTRACT_VERSION = 2;
const FLAG_KEY = 'watch_queue_v2_enabled';

async function featureEnabled(env) {
  const override = await getSetting(env, FLAG_KEY);
  if (override === 'true') return true;
  if (override === 'false') return false;
  return String(env.WATCH_QUEUE_V2_ENABLED || 'false') === 'true';
}

function limits(env) {
  return {
    maxQueues: Number(env.MAX_QUEUES_PER_GROUP || 20),
    maxItems: Number(env.MAX_ITEMS_PER_QUEUE || 500),
  };
}

async function readJson(request) {
  if (Number(request.headers.get('content-length') || 0) > 512 * 1024) return null;
  try {
    return await request.json();
  } catch {
    return null;
  }
}

/** 端末トークンで認証する。失効した端末は通さない。 */
async function authenticate(request, env) {
  const token = bearerToken(request);
  if (!token) return null;
  const device = await deviceByTokenHash(env, await hash(token, env.TOKEN_PEPPER || ''));
  if (!device || device.revoked_at) return null;
  return device;
}

async function handleConfig(env, origin) {
  const { maxQueues, maxItems } = limits(env);
  return json(
    {
      watchQueueV2Enabled: await featureEnabled(env),
      contractVersion: CONTRACT_VERSION,
      maxQueues,
      maxItems,
      pairingTtlSeconds: PAIRING_TTL_SECONDS,
    },
    { origin, env },
  );
}

async function handlePairingStart(request, env, origin) {
  if (!isAllowedOrigin(origin, env)) return fail('forbidden', { status: 403, origin, env });
  if (!(await rateLimit(env, `pair-start:${clientKey(request)}`, 10))) {
    return fail('rateLimited', { status: 429, origin, env });
  }
  await deleteExpiredPairings(env);

  const code = generatePairingCode();
  const pollToken = generateToken();
  const pairing = await createPairing(env, {
    codeHash: await hash(code, env.TOKEN_PEPPER || ''),
    pollTokenHash: await hash(pollToken, env.TOKEN_PEPPER || ''),
    ttlSeconds: PAIRING_TTL_SECONDS,
  });
  // コードは1回だけここで返す。サーバーにはハッシュしか残らない。
  return json({ pairingId: pairing.id, code, pollToken, expiresAt: pairing.expiresAt }, { origin, env });
}

async function handlePairingClaim(request, env, origin) {
  if (!(await rateLimit(env, `pair-claim:${clientKey(request)}`, 20))) {
    return fail('rateLimited', { status: 429, origin, env });
  }
  const body = await readJson(request);
  if (!hasOnlyKeys(body, ['code', 'platform', 'capabilities', 'clientVersion', 'deviceToken'])) {
    return fail('invalid', { origin, env });
  }
  const code = normalizeCode(body.code);
  if (!code) return fail('invalid', { origin, env });
  const platform = ['ios', 'android', 'web'].includes(body.platform) ? body.platform : null;
  if (!platform) return fail('invalid', { origin, env });

  const pairing = await pairingByCodeHash(env, await hash(code, env.TOKEN_PEPPER || ''));
  if (!pairing) return fail('notFound', { status: 404, origin, env });
  if (pairing.attempts >= PAIRING_MAX_ATTEMPTS) return fail('tooManyAttempts', { status: 429, origin, env });
  await bumpPairingAttempts(env, pairing.id);
  if (pairing.expires_at < Math.floor(Date.now() / 1000)) return fail('expired', { status: 410, origin, env });
  if (pairing.claimed_at) return fail('alreadyUsed', { status: 409, origin, env });

  // すでにペアリング済みの端末なら、そのグループへ拡張を迎え入れる（グループを増やさない）。
  let groupId = null;
  if (body.deviceToken && isToken(body.deviceToken)) {
    const existing = await deviceByTokenHash(env, await hash(body.deviceToken, env.TOKEN_PEPPER || ''));
    if (existing && !existing.revoked_at) groupId = existing.group_id;
  }
  let deviceToken = null;
  if (!groupId) {
    groupId = await createGroup(env);
    deviceToken = generateToken();
    await createDevice(env, {
      groupId,
      platform,
      capabilities: text(body.capabilities, 200),
      clientVersion: text(body.clientVersion, 40),
      tokenHash: await hash(deviceToken, env.TOKEN_PEPPER || ''),
    });
  }
  await markPairingClaimed(env, pairing.id, groupId, platform);
  return json({ groupId, deviceToken }, { origin, env });
}

async function handlePairingComplete(request, env, origin) {
  if (!isAllowedOrigin(origin, env)) return fail('forbidden', { status: 403, origin, env });
  if (!(await rateLimit(env, `pair-complete:${clientKey(request)}`, 60))) {
    return fail('rateLimited', { status: 429, origin, env });
  }
  const body = await readJson(request);
  if (!hasOnlyKeys(body, ['pairingId', 'pollToken', 'capabilities', 'clientVersion'])) {
    return fail('invalid', { origin, env });
  }
  if (!isId(body.pairingId) || !isToken(body.pollToken)) return fail('invalid', { origin, env });

  const pairing = await pairingById(env, body.pairingId);
  if (!pairing) return fail('notFound', { status: 404, origin, env });
  if (!safeEqual(pairing.poll_token_hash, await hash(body.pollToken, env.TOKEN_PEPPER || ''))) {
    return fail('forbidden', { status: 403, origin, env });
  }
  if (pairing.expires_at < Math.floor(Date.now() / 1000) && !pairing.claimed_at) {
    return fail('expired', { status: 410, origin, env });
  }
  if (!pairing.claimed_at) return json({ status: 'pending' }, { origin, env });
  if (pairing.completed_at) return fail('alreadyUsed', { status: 409, origin, env });

  const deviceToken = generateToken();
  await createDevice(env, {
    groupId: pairing.group_id,
    platform: 'extension',
    capabilities: text(body.capabilities, 200),
    clientVersion: text(body.clientVersion, 40),
    tokenHash: await hash(deviceToken, env.TOKEN_PEPPER || ''),
  });
  await markPairingCompleted(env, pairing.id);
  return json({ status: 'paired', groupId: pairing.group_id, deviceToken }, { origin, env });
}

async function entitlementFor(env, groupId) {
  const [group, queueCount] = await Promise.all([getGroup(env, groupId), countQueues(env, groupId)]);
  return {
    ...collectionLimitState({
      isPro: Boolean(group && group.is_pro),
      channelCount: group ? group.channel_count : 0,
      queueCount,
    }),
    channelCount: group ? group.channel_count : 0,
    queueCount,
    reportedAt: group ? group.entitlement_updated_at : null,
  };
}

/**
 * 共有リンク（/watch-queue#v=2&q=…）で開いたウェブVIEWER向けの読み取り。
 *
 * ウェブVIEWERはペアリングしていないので、**推測不能な queueId を鍵として扱う**。
 * V1 で動画IDを URL に全部並べていたのと同じ考え方で、URL の露出はむしろ減る。
 * 返すのは動画IDの並びとキュー名だけ。書き込みはできない。
 */
async function handleSharedQueue(request, env, queueId, origin) {
  if (!isId(queueId)) return fail('invalid', { origin, env });
  if (!(await rateLimit(env, `shared:${clientKey(request)}`, 60))) {
    return fail('rateLimited', { status: 429, origin, env });
  }
  const queue = await sharedQueueWithItems(env, queueId);
  if (!queue || queue.videoIds.length === 0) return fail('notFound', { status: 404, origin, env });
  return json(queue, { origin, env });
}

async function handleGetQueues(env, device, origin) {
  const queues = await listQueuesWithItems(env, device.group_id);
  return json({ queues, entitlement: await entitlementFor(env, device.group_id) }, { origin, env });
}

async function handlePutQueue(request, env, device, queueId, origin) {
  const { maxQueues, maxItems } = limits(env);
  const body = await readJson(request);
  if (!hasOnlyKeys(body, ['name', 'items', 'baseVersion'])) return fail('invalid', { origin, env });
  if (!isId(queueId)) return fail('invalid', { origin, env });

  const normalized = normalizeItems(body.items, maxItems);
  if (!normalized.ok) return fail(normalized.reason, { origin, env });

  const existing = await getQueue(env, device.group_id, queueId);
  const isNew = !existing || existing.deleted_at;
  if (isNew) {
    const [queueCount, entitlement] = await Promise.all([
      countQueues(env, device.group_id),
      entitlementFor(env, device.group_id),
    ]);
    if (queueCount >= maxQueues) return fail('tooManyQueues', { status: 409, origin, env });
    // 2つ目以降の Collection は Pro が要る（判定の正本はアプリが報告した購入状態）。
    if (!entitlement.canCreateAnother) return fail('proRequired', { status: 402, origin, env });
  }

  const version = checkVersion(existing && !existing.deleted_at ? existing.version : 0, body.baseVersion ?? null);
  if (!version.ok) {
    return version.reason === 'conflict'
      ? json({ error: 'conflict', version: existing ? existing.version : 0 }, { status: 409, origin, env })
      : fail(version.reason, { origin, env });
  }

  const saved = await replaceQueue(env, {
    groupId: device.group_id,
    queueId,
    name: normalizeQueueName(body.name),
    items: normalized.items,
    version: version.next,
    isNew,
  });
  return json(saved, { origin, env });
}

async function handleDeleteQueue(env, device, queueId, origin) {
  const existing = await getQueue(env, device.group_id, queueId);
  if (!existing || existing.deleted_at) return fail('notFound', { status: 404, origin, env });
  await softDeleteQueue(env, device.group_id, queueId, existing.version + 1);
  return json({ deleted: true, version: existing.version + 1 }, { origin, env });
}

async function handlePostEntitlement(request, env, device, origin) {
  // 購入状態を報告できるのはアプリ側（拡張は自己申告しない）。
  if (device.platform === 'extension') return fail('forbidden', { status: 403, origin, env });
  const body = await readJson(request);
  if (!hasOnlyKeys(body, ['isPro', 'channelCount'])) return fail('invalid', { origin, env });
  if (typeof body.isPro !== 'boolean' || typeof body.channelCount !== 'number') {
    return fail('invalid', { origin, env });
  }
  await updateEntitlement(env, device.group_id, { isPro: body.isPro, channelCount: body.channelCount });
  return json(await entitlementFor(env, device.group_id), { origin, env });
}

async function handleRevoke(request, env, device, origin) {
  const body = (await readJson(request)) ?? {};
  if (!hasOnlyKeys(body, ['deviceId'])) return fail('invalid', { origin, env });
  const target = body.deviceId && isId(body.deviceId) ? body.deviceId : device.id;
  const revoked = await revokeDevice(env, device.group_id, target);
  return json({ revoked }, { origin, env });
}

async function handleAdminFlag(request, env, origin) {
  // ADMIN_TOKEN が設定されていないときは、その存在自体を隠す（404）。
  if (!env.ADMIN_TOKEN) return fail('notFound', { status: 404, origin, env });
  const token = rawBearer(request);
  if (!token || !safeEqual(token, env.ADMIN_TOKEN)) return fail('notFound', { status: 404, origin, env });
  const body = await readJson(request);
  if (!hasOnlyKeys(body, ['enabled']) || typeof body.enabled !== 'boolean') return fail('invalid', { origin, env });
  await setSetting(env, FLAG_KEY, body.enabled ? 'true' : 'false');
  return json({ watchQueueV2Enabled: body.enabled }, { origin, env });
}

export default {
  async fetch(request, env) {
    const origin = request.headers.get('origin') || '';
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(origin, env) });
    }
    if (path === '/' || path === '/health') {
      return json({ ok: true, service: 'watch-queue-sync' }, { origin, env });
    }
    if (path === '/v2/config' && request.method === 'GET') {
      return handleConfig(env, origin);
    }
    if (path === '/v2/admin/flag' && request.method === 'POST') {
      return handleAdminFlag(request, env, origin);
    }

    // Kill switch: config 以外はすべて止まる。クライアントは pre-V2 の挙動に戻る。
    if (!(await featureEnabled(env))) {
      return fail('disabled', { status: 503, origin, env });
    }

    // 共有リンクからの読み取りは認証しない（鍵は queueId そのもの）。書き込み系より前に置く。
    const sharedMatch = /^\/v2\/shared\/queues\/([^/]+)$/.exec(path);
    if (sharedMatch && request.method === 'GET') return handleSharedQueue(request, env, sharedMatch[1], origin);

    if (path === '/v2/pairing/start' && request.method === 'POST') return handlePairingStart(request, env, origin);
    if (path === '/v2/pairing/claim' && request.method === 'POST') return handlePairingClaim(request, env, origin);
    if (path === '/v2/pairing/complete' && request.method === 'POST') return handlePairingComplete(request, env, origin);

    const device = await authenticate(request, env);
    if (!device) return fail('unauthorized', { status: 401, origin, env });
    if (!(await rateLimit(env, `device:${device.id}`, 120))) {
      return fail('rateLimited', { status: 429, origin, env });
    }
    await touchDevice(env, device.id, text(request.headers.get('x-client-version'), 40), '');

    if (path === '/v2/queues' && request.method === 'GET') return handleGetQueues(env, device, origin);
    if (path === '/v2/entitlement' && request.method === 'GET') {
      return json(await entitlementFor(env, device.group_id), { origin, env });
    }
    if (path === '/v2/entitlement' && request.method === 'POST') {
      return handlePostEntitlement(request, env, device, origin);
    }
    if (path === '/v2/devices' && request.method === 'GET') {
      return json({ devices: await listDevices(env, device.group_id), self: device.id }, { origin, env });
    }
    if (path === '/v2/devices/revoke' && request.method === 'POST') return handleRevoke(request, env, device, origin);

    const queueMatch = /^\/v2\/queues\/([^/]+)$/.exec(path);
    if (queueMatch) {
      // 書き込みは拡張だけ（アプリ側は再生・選択・削除）。削除は両方から可能。
      if (request.method === 'PUT') {
        if (device.platform !== 'extension') return fail('forbidden', { status: 403, origin, env });
        if (!isAllowedOrigin(origin, env)) return fail('forbidden', { status: 403, origin, env });
        return handlePutQueue(request, env, device, queueMatch[1], origin);
      }
      if (request.method === 'DELETE') return handleDeleteQueue(env, device, queueMatch[1], origin);
    }

    return fail('notFound', { status: 404, origin, env });
  },
};
