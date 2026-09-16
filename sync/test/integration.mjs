// Watch Queue Sync — 実際の HTTP で API をひと通り確かめる統合テスト。
//
//   npm run test:integration
//
// wrangler dev（--local）を立ち上げ、ペアリング → 同期 → 競合 → 権限 → Feature Flag OFF まで通す。
// D1 はローカルのファイル（.wrangler/state）を使うので、本番には一切触れない。
import { spawn } from 'node:child_process';
import { setTimeout as sleep } from 'node:timers/promises';

const PORT = Number(process.env.PORT || 8799);
const BASE = `http://127.0.0.1:${PORT}`;
const EXT_ORIGIN = 'chrome-extension://testextensionidtestextensionid00';
const SITE_ORIGIN = 'https://channeltimeline.jewelrysunflower.com';
const ADMIN_TOKEN = 'dev-admin-token-for-integration-test';

const A = 'aaaaaaaaaa1';
const B = 'bbbbbbbbbb2';
const C = 'ccccccccccc';

let failures = 0;
const check = (name, ok, detail = '') => {
  if (!ok) failures += 1;
  const text = typeof detail === 'string' ? detail : JSON.stringify(detail);
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || !text ? '' : `  (${text.slice(0, 300)})`}`);
};

async function call(path, { method = 'GET', body, token, origin, adminToken } = {}) {
  const headers = { 'content-type': 'application/json' };
  if (origin) headers.origin = origin;
  if (token) headers.authorization = `Bearer ${token}`;
  if (adminToken) headers.authorization = `Bearer ${adminToken}`;
  const res = await fetch(BASE + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  let data = null;
  try {
    data = await res.json();
  } catch {
    data = null;
  }
  return { status: res.status, data };
}

const wrangler = spawn(
  process.platform === 'win32' ? 'npx.cmd' : 'npx',
  [
    'wrangler',
    'dev',
    '--port',
    String(PORT),
    '--persist-to',
    '.wrangler/state',
    '--var',
    'WATCH_QUEUE_V2_ENABLED:true',
    '--var',
    `ALLOWED_ORIGINS:${SITE_ORIGIN},${EXT_ORIGIN}`,
    '--var',
    'TOKEN_PEPPER:integration-test-pepper',
    '--var',
    `ADMIN_TOKEN:${ADMIN_TOKEN}`,
  ],
  { stdio: ['ignore', 'pipe', 'pipe'], shell: process.platform === 'win32' },
);
let serverLog = '';
wrangler.stdout.on('data', (chunk) => (serverLog += chunk.toString()));
wrangler.stderr.on('data', (chunk) => (serverLog += chunk.toString()));

async function waitForServer() {
  for (let i = 0; i < 120; i += 1) {
    try {
      const res = await fetch(`${BASE}/health`);
      if (res.ok) return true;
    } catch {
      // not up yet
    }
    await sleep(500);
  }
  return false;
}

try {
  if (!(await waitForServer())) {
    console.error('wrangler dev did not start:\n' + serverLog.slice(-2000));
    process.exit(1);
  }

  // --- config
  let res = await call('/v2/config');
  check('config: feature flag is readable', res.status === 200 && res.data.watchQueueV2Enabled === true, res.data);
  check('config: contract version 2', res.data?.contractVersion === 2, res.data);

  // --- pairing (required backend tests 1-4, 10)
  res = await call('/v2/pairing/start', { method: 'POST', origin: EXT_ORIGIN });
  const pairing = res.data;
  check('pairing: start returns a code', res.status === 200 && /^[ACDEFGHJKMNPQRTUVWXY34679]{8}$/.test(pairing?.code || ''), res.data);

  res = await call('/v2/pairing/start', { method: 'POST', origin: 'https://evil.example' });
  check('pairing: an unknown origin cannot start pairing', res.status === 403, res.data);

  res = await call('/v2/pairing/complete', {
    method: 'POST',
    origin: EXT_ORIGIN,
    body: { pairingId: pairing.pairingId, pollToken: pairing.pollToken },
  });
  check('pairing: still pending before the app claims it', res.status === 200 && res.data.status === 'pending', res.data);

  res = await call('/v2/pairing/claim', {
    method: 'POST',
    body: { code: ` ${pairing.code.toLowerCase()} `, platform: 'ios', capabilities: 'watch_queue_v2', clientVersion: '1.3.0' },
  });
  const appToken = res.data?.deviceToken;
  check('pairing: the app claims the code (case/spacing tolerated)', res.status === 200 && /^[0-9a-f]{64}$/.test(appToken || ''), res.data);

  res = await call('/v2/pairing/claim', { method: 'POST', body: { code: pairing.code, platform: 'android' } });
  check('pairing: a code can be used only once', res.status === 409, res.data);

  res = await call('/v2/pairing/claim', { method: 'POST', body: { code: 'AAAAAAAA', platform: 'ios' } });
  check('pairing: an unknown code is rejected', res.status === 404, res.data);

  res = await call('/v2/pairing/complete', {
    method: 'POST',
    origin: EXT_ORIGIN,
    body: { pairingId: pairing.pairingId, pollToken: 'deadbeef'.repeat(8) },
  });
  check('pairing: the poll token is checked', res.status === 403, res.data);

  res = await call('/v2/pairing/complete', {
    method: 'POST',
    origin: EXT_ORIGIN,
    body: { pairingId: pairing.pairingId, pollToken: pairing.pollToken, capabilities: 'watch_queue_v2', clientVersion: '0.3.0' },
  });
  const extToken = res.data?.deviceToken;
  check('pairing: the extension receives its own device token', res.status === 200 && /^[0-9a-f]{64}$/.test(extToken || ''), res.data);

  res = await call('/v2/pairing/complete', {
    method: 'POST',
    origin: EXT_ORIGIN,
    body: { pairingId: pairing.pairingId, pollToken: pairing.pollToken },
  });
  check('pairing: completing twice is refused', res.status === 409, res.data);

  // --- authorization (required backend tests 4, 10)
  res = await call('/v2/queues');
  check('auth: no token is rejected', res.status === 401, res.data);
  res = await call('/v2/queues', { token: 'f'.repeat(64) });
  check('auth: an unknown token is rejected', res.status === 401, res.data);

  // --- queues (required backend tests 5-8, 15)
  res = await call('/v2/queues', { token: extToken, origin: EXT_ORIGIN });
  check('queues: a fresh pairing has none', res.status === 200 && res.data.queues.length === 0, res.data);
  check('entitlement: free can still create the first collection', res.data?.entitlement?.canCreateAnother === true, res.data?.entitlement);

  const queueId = crypto.randomUUID();
  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: {
      name: 'Watch Queue',
      baseVersion: null,
      items: [
        { videoId: A, title: 'first', addedAt: '2026-09-16T00:00:00Z' },
        { videoId: B, title: 'second' },
        { videoId: C, title: 'third' },
      ],
    },
  });
  check('queues: created with version 1', res.status === 200 && res.data.version === 1, res.data);

  res = await call('/v2/queues', { token: appToken });
  const queue = res.data?.queues?.[0];
  check('queues: the app sees the queue in the same order', queue?.items?.map((item) => item.videoId).join(',') === `${A},${B},${C}`, queue);
  check('queues: the name is kept', queue?.name === 'Watch Queue', queue);

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'Watch Queue', baseVersion: 1, items: [{ videoId: C }, { videoId: A }] },
  });
  check('queues: reordering bumps the version', res.status === 200 && res.data.version === 2, res.data);

  res = await call('/v2/queues', { token: appToken });
  check(
    'queues: the new order is stored as positions',
    res.data?.queues?.[0]?.items?.map((item) => item.videoId).join(',') === `${C},${A}`,
    res.data?.queues?.[0]?.items,
  );

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'stale write', baseVersion: 1, items: [{ videoId: A }] },
  });
  check('queues: a stale baseVersion is refused (409 conflict)', res.status === 409 && res.data.error === 'conflict', res.data);

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'x', baseVersion: 2, items: [{ videoId: 'bad' }] },
  });
  check('queues: malformed ids are refused', res.status === 400, res.data);

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'x', baseVersion: 2, items: [], evil: true },
  });
  check('queues: unexpected keys are refused', res.status === 400, res.data);

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: appToken,
    body: { name: 'from the app', baseVersion: 2, items: [{ videoId: A }] },
  });
  check('queues: only the extension may write', res.status === 403, res.data);

  res = await call(`/v2/queues/${queueId}`, {
    method: 'PUT',
    token: extToken,
    origin: 'https://evil.example',
    body: { name: 'x', baseVersion: 2, items: [{ videoId: A }] },
  });
  check('queues: writes from an unknown origin are refused', res.status === 403, res.data);

  // --- entitlement (required backend test 13)
  const secondQueueId = crypto.randomUUID();
  res = await call(`/v2/queues/${secondQueueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'Second', baseVersion: null, items: [{ videoId: A }] },
  });
  check('entitlement: a second collection needs Pro (402)', res.status === 402 && res.data.error === 'proRequired', res.data);

  res = await call('/v2/entitlement', { method: 'POST', token: extToken, origin: EXT_ORIGIN, body: { isPro: true, channelCount: 0 } });
  check('entitlement: the extension cannot report purchases', res.status === 403, res.data);

  res = await call('/v2/entitlement', { method: 'POST', token: appToken, body: { isPro: false, channelCount: 1 } });
  check('entitlement: 1 channel + 1 queue is already two collections', res.status === 200 && res.data.canCreateAnother === false, res.data);

  res = await call('/v2/entitlement', { method: 'POST', token: appToken, body: { isPro: true, channelCount: 1 } });
  check('entitlement: Pro allows several collections', res.status === 200 && res.data.canCreateAnother === true, res.data);

  res = await call(`/v2/queues/${secondQueueId}`, {
    method: 'PUT',
    token: extToken,
    origin: EXT_ORIGIN,
    body: { name: 'Second', baseVersion: null, items: [{ videoId: A }] },
  });
  check('entitlement: with Pro the second queue is accepted', res.status === 200 && res.data.version === 1, res.data);

  // --- devices
  res = await call('/v2/devices', { token: appToken });
  check('devices: both devices are listed in the group', res.status === 200 && res.data.devices.length === 2, res.data);

  // --- delete (required backend test 8)
  res = await call(`/v2/queues/${secondQueueId}`, { method: 'DELETE', token: appToken });
  check('queues: the app may delete a queue', res.status === 200 && res.data.deleted === true, res.data);
  res = await call('/v2/queues', { token: extToken, origin: EXT_ORIGIN });
  check('queues: a deleted queue disappears', res.status === 200 && res.data.queues.length === 1, res.data.queues?.length);

  // --- shared read for the web viewer (Queue Launch Contract V2)
  res = await call(`/v2/shared/queues/${queueId}`, { origin: SITE_ORIGIN });
  check(
    'shared: the web viewer reads the queue without a token',
    res.status === 200 && res.data?.videoIds?.join(',') === `${C},${A}`,
    res.data,
  );
  check(
    'shared: nothing but the ids, the name and the version is returned',
    Object.keys(res.data ?? {}).sort().join(',') === 'name,queueId,updatedAt,version,videoIds',
    res.data,
  );
  res = await call(`/v2/shared/queues/${crypto.randomUUID()}`, { origin: SITE_ORIGIN });
  check('shared: an unknown queue is not found', res.status === 404, res.data);
  res = await call('/v2/shared/queues/not a valid id!', { origin: SITE_ORIGIN });
  check('shared: a malformed queue id is refused', res.status === 400, res.data);
  res = await call(`/v2/shared/queues/${queueId}`, {
    method: 'PUT',
    origin: SITE_ORIGIN,
    body: { name: 'x', baseVersion: 2, items: [] },
  });
  check('shared: the shared link cannot write', res.status === 401, res.data);

  // --- feature flag / kill switch (required backend test 14)
  res = await call('/v2/admin/flag', { method: 'POST', body: { enabled: false }, adminToken: 'wrong-token' });
  check('flag: a wrong admin token looks like 404', res.status === 404, res.data);

  res = await call('/v2/admin/flag', { method: 'POST', body: { enabled: false }, adminToken: ADMIN_TOKEN });
  check('flag: the kill switch can be turned off', res.status === 200 && res.data.watchQueueV2Enabled === false, res.data);

  res = await call('/v2/queues', { token: extToken, origin: EXT_ORIGIN });
  check('flag OFF: sync stops answering (503 disabled)', res.status === 503 && res.data.error === 'disabled', res.data);
  res = await call('/v2/pairing/start', { method: 'POST', origin: EXT_ORIGIN });
  check('flag OFF: pairing stops too', res.status === 503, res.data);
  res = await call(`/v2/shared/queues/${queueId}`, { origin: SITE_ORIGIN });
  check('flag OFF: the web viewer cannot read shared queues either', res.status === 503, res.data);
  res = await call('/v2/config');
  check('flag OFF: config still answers so clients can see the state', res.status === 200 && res.data.watchQueueV2Enabled === false, res.data);

  res = await call('/v2/admin/flag', { method: 'POST', body: { enabled: true }, adminToken: ADMIN_TOKEN });
  check('flag: it can be turned back on', res.status === 200 && res.data.watchQueueV2Enabled === true, res.data);
  res = await call('/v2/queues', { token: extToken, origin: EXT_ORIGIN });
  check('flag ON: the queue is still there afterwards', res.status === 200 && res.data.queues.length === 1, res.data.queues?.length);

  // --- revoke
  res = await call('/v2/devices/revoke', { method: 'POST', token: appToken, body: {} });
  check('devices: a device can revoke itself', res.status === 200 && res.data.revoked === true, res.data);
  res = await call('/v2/queues', { token: appToken });
  check('devices: a revoked token no longer works', res.status === 401, res.data);
} catch (error) {
  check('integration run completed', false, String(error?.stack ?? error));
} finally {
  wrangler.kill();
  await sleep(500);
}

console.log(`\nIntegration: ${failures === 0 ? 'all checks passed' : `${failures} failed`}`);
if (failures > 0 && serverLog) console.log('--- wrangler log (tail) ---\n' + serverLog.slice(-1500));
process.exit(failures === 0 ? 0 : 1);
