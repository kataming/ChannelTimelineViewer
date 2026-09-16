// D1 への問い合わせをまとめたところ。SQL はここだけに書く。

import { generateId } from './crypto.js';

const now = () => Math.floor(Date.now() / 1000);

export async function getSetting(env, key) {
  const row = await env.DB.prepare('SELECT value FROM settings WHERE key = ?').bind(key).first();
  return row ? row.value : null;
}

export async function setSetting(env, key, value) {
  await env.DB.prepare(
    'INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) ' +
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
  )
    .bind(key, value, now())
    .run();
}

export async function createGroup(env) {
  const id = generateId();
  await env.DB.prepare('INSERT INTO groups (id, created_at) VALUES (?, ?)').bind(id, now()).run();
  return id;
}

export async function createDevice(env, { groupId, platform, capabilities, clientVersion, tokenHash }) {
  const id = generateId();
  await env.DB.prepare(
    'INSERT INTO devices (id, group_id, platform, capabilities, client_version, token_hash, created_at, last_seen_at) ' +
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
  )
    .bind(id, groupId, platform, capabilities || '', clientVersion || '', tokenHash, now(), now())
    .run();
  return id;
}

export async function deviceByTokenHash(env, tokenHash) {
  return env.DB.prepare(
    'SELECT id, group_id, platform, capabilities, client_version, revoked_at FROM devices WHERE token_hash = ?',
  )
    .bind(tokenHash)
    .first();
}

export async function touchDevice(env, deviceId, clientVersion, capabilities) {
  await env.DB.prepare(
    'UPDATE devices SET last_seen_at = ?, client_version = COALESCE(NULLIF(?, \'\'), client_version), ' +
      'capabilities = COALESCE(NULLIF(?, \'\'), capabilities) WHERE id = ?',
  )
    .bind(now(), clientVersion || '', capabilities || '', deviceId)
    .run();
}

export async function revokeDevice(env, groupId, deviceId) {
  const result = await env.DB.prepare('UPDATE devices SET revoked_at = ? WHERE id = ? AND group_id = ?')
    .bind(now(), deviceId, groupId)
    .run();
  return result.meta.changes > 0;
}

export async function listDevices(env, groupId) {
  const { results } = await env.DB.prepare(
    'SELECT id, platform, capabilities, client_version, created_at, last_seen_at, revoked_at FROM devices WHERE group_id = ? ORDER BY created_at',
  )
    .bind(groupId)
    .all();
  return results ?? [];
}

export async function createPairing(env, { codeHash, pollTokenHash, ttlSeconds }) {
  const id = generateId();
  const createdAt = now();
  await env.DB.prepare(
    'INSERT INTO pairings (id, code_hash, poll_token_hash, created_at, expires_at) VALUES (?, ?, ?, ?, ?)',
  )
    .bind(id, codeHash, pollTokenHash, createdAt, createdAt + ttlSeconds)
    .run();
  return { id, expiresAt: createdAt + ttlSeconds };
}

export async function pairingByCodeHash(env, codeHash) {
  return env.DB.prepare(
    'SELECT id, code_hash, poll_token_hash, group_id, platform, expires_at, claimed_at, completed_at, attempts FROM pairings WHERE code_hash = ?',
  )
    .bind(codeHash)
    .first();
}

export async function pairingById(env, id) {
  return env.DB.prepare(
    'SELECT id, poll_token_hash, group_id, platform, expires_at, claimed_at, completed_at FROM pairings WHERE id = ?',
  )
    .bind(id)
    .first();
}

export async function bumpPairingAttempts(env, id) {
  await env.DB.prepare('UPDATE pairings SET attempts = attempts + 1 WHERE id = ?').bind(id).run();
}

export async function markPairingClaimed(env, id, groupId, platform) {
  await env.DB.prepare('UPDATE pairings SET group_id = ?, platform = ?, claimed_at = ? WHERE id = ?')
    .bind(groupId, platform, now(), id)
    .run();
}

export async function markPairingCompleted(env, id) {
  await env.DB.prepare('UPDATE pairings SET completed_at = ? WHERE id = ?').bind(now(), id).run();
}

export async function deleteExpiredPairings(env) {
  await env.DB.prepare('DELETE FROM pairings WHERE expires_at < ?').bind(now() - 3600).run();
}

export async function getGroup(env, groupId) {
  return env.DB.prepare('SELECT id, is_pro, channel_count, entitlement_updated_at FROM groups WHERE id = ?')
    .bind(groupId)
    .first();
}

export async function updateEntitlement(env, groupId, { isPro, channelCount }) {
  await env.DB.prepare('UPDATE groups SET is_pro = ?, channel_count = ?, entitlement_updated_at = ? WHERE id = ?')
    .bind(isPro ? 1 : 0, Math.max(0, channelCount | 0), now(), groupId)
    .run();
}

export async function countQueues(env, groupId) {
  const row = await env.DB.prepare('SELECT COUNT(*) AS n FROM queues WHERE group_id = ? AND deleted_at IS NULL')
    .bind(groupId)
    .first();
  return row ? Number(row.n) : 0;
}

export async function listQueuesWithItems(env, groupId) {
  const { results: queues } = await env.DB.prepare(
    'SELECT id, name, version, created_at, updated_at FROM queues WHERE group_id = ? AND deleted_at IS NULL ORDER BY created_at',
  )
    .bind(groupId)
    .all();
  if (!queues || queues.length === 0) return [];

  const { results: items } = await env.DB.prepare(
    'SELECT queue_id, video_id, position, title, channel_name, duration_text, added_at FROM queue_items ' +
      'WHERE queue_id IN (SELECT id FROM queues WHERE group_id = ? AND deleted_at IS NULL) ORDER BY queue_id, position',
  )
    .bind(groupId)
    .all();

  const byQueue = new Map();
  for (const item of items ?? []) {
    const list = byQueue.get(item.queue_id) ?? [];
    list.push({
      videoId: item.video_id,
      title: item.title,
      channelName: item.channel_name,
      durationText: item.duration_text,
      addedAt: item.added_at,
    });
    byQueue.set(item.queue_id, list);
  }

  return queues.map((queue) => ({
    queueId: queue.id,
    name: queue.name,
    version: queue.version,
    createdAt: queue.created_at,
    updatedAt: queue.updated_at,
    items: byQueue.get(queue.id) ?? [],
  }));
}

/**
 * 共有リンク（Queue Launch Contract V2）からの読み取り。グループを問わない。
 * queueId は推測できない乱数で、URL そのものが鍵。返すのは再生に要る最小限だけで、
 * 端末・購入状態・ほかのキューのことは返さない。
 */
export async function sharedQueueWithItems(env, queueId) {
  const queue = await env.DB.prepare(
    'SELECT id, name, version, updated_at FROM queues WHERE id = ? AND deleted_at IS NULL',
  )
    .bind(queueId)
    .first();
  if (!queue) return null;

  const { results } = await env.DB.prepare('SELECT video_id FROM queue_items WHERE queue_id = ? ORDER BY position')
    .bind(queueId)
    .all();

  return {
    queueId: queue.id,
    name: queue.name,
    version: queue.version,
    updatedAt: queue.updated_at,
    videoIds: (results ?? []).map((row) => row.video_id),
  };
}

export async function getQueue(env, groupId, queueId) {
  return env.DB.prepare('SELECT id, name, version, deleted_at FROM queues WHERE id = ? AND group_id = ?')
    .bind(queueId, groupId)
    .first();
}

/** キューを丸ごと置き換える（順番の正本は拡張側なので、items は毎回入れ替える）。 */
export async function replaceQueue(env, { groupId, queueId, name, items, version, isNew }) {
  const timestamp = now();
  const statements = [];
  if (isNew) {
    statements.push(
      env.DB.prepare(
        'INSERT INTO queues (id, group_id, name, version, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      ).bind(queueId, groupId, name, version, timestamp, timestamp),
    );
  } else {
    statements.push(
      env.DB.prepare('UPDATE queues SET name = ?, version = ?, updated_at = ?, deleted_at = NULL WHERE id = ? AND group_id = ?').bind(
        name,
        version,
        timestamp,
        queueId,
        groupId,
      ),
    );
    statements.push(env.DB.prepare('DELETE FROM queue_items WHERE queue_id = ?').bind(queueId));
  }
  for (const item of items) {
    statements.push(
      env.DB.prepare(
        'INSERT INTO queue_items (queue_id, video_id, position, title, channel_name, duration_text, added_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ).bind(queueId, item.videoId, item.position, item.title, item.channelName, item.durationText, item.addedAt),
    );
  }
  await env.DB.batch(statements);
  return { queueId, version, updatedAt: timestamp };
}

export async function softDeleteQueue(env, groupId, queueId, version) {
  const timestamp = now();
  await env.DB.batch([
    env.DB.prepare('UPDATE queues SET deleted_at = ?, updated_at = ?, version = ? WHERE id = ? AND group_id = ?').bind(
      timestamp,
      timestamp,
      version,
      queueId,
      groupId,
    ),
    env.DB.prepare('DELETE FROM queue_items WHERE queue_id = ?').bind(queueId),
  ]);
}
