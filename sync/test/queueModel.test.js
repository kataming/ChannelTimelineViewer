import { describe, expect, it } from 'vitest';
import { checkVersion, collectionLimitState, hasWatchQueueV2Capability, normalizeItems, normalizeQueueName } from '../src/queueModel.js';
import { generatePairingCode, generateToken, hash, normalizeCode, safeEqual } from '../src/crypto.js';
import { bearerToken, hasOnlyKeys, isAllowedOrigin, isToken, isVideoId, text } from '../src/http.js';

const A = 'aaaaaaaaaa1';
const B = 'bbbbbbbbbb2';

describe('normalizeItems (required backend tests 6, 7, 9, 12)', () => {
  it('keeps the order it was given and numbers the positions from 0', () => {
    const result = normalizeItems(
      [
        { videoId: B, title: ' Second  video ' },
        { videoId: A, title: 'First', channelName: 'Ch', durationText: '1:23', addedAt: '2026-09-16T00:00:00Z' },
      ],
      500,
    );
    expect(result.ok).toBe(true);
    expect(result.items.map((item) => [item.videoId, item.position])).toEqual([
      [B, 0],
      [A, 1],
    ]);
    expect(result.items[0].title).toBe('Second video');
    expect(result.items[1].channelName).toBe('Ch');
  });

  it('drops duplicates but keeps the first occurrence', () => {
    const result = normalizeItems([{ videoId: A }, { videoId: B }, { videoId: A }], 500);
    expect(result.items.map((item) => item.videoId)).toEqual([A, B]);
  });

  it('rejects broken payloads and oversized queues', () => {
    expect(normalizeItems('nope', 500)).toEqual({ ok: false, reason: 'items' });
    expect(normalizeItems([{ videoId: 'short' }], 500)).toEqual({ ok: false, reason: 'videoId' });
    expect(normalizeItems([null], 500)).toEqual({ ok: false, reason: 'item' });
    expect(normalizeItems([{ videoId: A }, { videoId: B }], 1)).toEqual({ ok: false, reason: 'tooManyItems' });
  });

  it('truncates long text fields', () => {
    const result = normalizeItems([{ videoId: A, title: 'x'.repeat(1000), channelName: 'y'.repeat(200) }], 500);
    expect(result.items[0].title).toHaveLength(300);
    expect(result.items[0].channelName).toHaveLength(60);
    expect(normalizeQueueName('  Study   queue ')).toBe('Study queue');
  });
});

describe('collectionLimitState (required backend test 13)', () => {
  it('free allows exactly one collection', () => {
    expect(collectionLimitState({ isPro: false, channelCount: 0, queueCount: 0 })).toMatchObject({ total: 0, canCreateAnother: true });
    expect(collectionLimitState({ isPro: false, channelCount: 0, queueCount: 1 })).toMatchObject({ total: 1, canCreateAnother: false });
    expect(collectionLimitState({ isPro: false, channelCount: 1, queueCount: 0 })).toMatchObject({ total: 1, canCreateAnother: false });
    expect(collectionLimitState({ isPro: false, channelCount: 1, queueCount: 1 })).toMatchObject({ total: 2, canCreateAnother: false });
  });

  it('pro allows several collections', () => {
    expect(collectionLimitState({ isPro: true, channelCount: 3, queueCount: 2 })).toMatchObject({
      total: 5,
      isPro: true,
      canCreateAnother: true,
    });
  });
});

describe('checkVersion (required backend test 15)', () => {
  it('accepts a matching base version and bumps it', () => {
    expect(checkVersion(3, 3)).toEqual({ ok: true, next: 4 });
    expect(checkVersion(0, null)).toEqual({ ok: true, next: 1 });
  });

  it('refuses stale or malformed versions', () => {
    expect(checkVersion(5, 4)).toEqual({ ok: false, reason: 'conflict' });
    expect(checkVersion(5, '4')).toEqual({ ok: false, reason: 'baseVersion' });
    expect(checkVersion(5, -1)).toEqual({ ok: false, reason: 'baseVersion' });
  });
});

describe('capabilities (required backend test 14 / capability handling)', () => {
  it('detects clients that understand Watch Queue V2', () => {
    expect(hasWatchQueueV2Capability('watch_queue_v2')).toBe(true);
    expect(hasWatchQueueV2Capability('tutorial, watch_queue_v2 ,x')).toBe(true);
    expect(hasWatchQueueV2Capability('')).toBe(false);
    expect(hasWatchQueueV2Capability('watch_queue_v1')).toBe(false);
  });
});

describe('pairing codes and tokens (required backend tests 1-3)', () => {
  it('generates unambiguous 8-character codes', () => {
    const codes = new Set();
    for (let i = 0; i < 200; i += 1) {
      const code = generatePairingCode();
      expect(code).toMatch(/^[ACDEFGHJKMNPQRTUVWXY34679]{8}$/);
      codes.add(code);
    }
    expect(codes.size).toBeGreaterThan(190); // practically no repeats
  });

  it('accepts the code however the user typed it', () => {
    expect(normalizeCode(' acde-fghj ')).toBe('ACDEFGHJ');
    expect(normalizeCode(null)).toBe('');
  });

  it('never stores the plain value: hashing is stable and peppered', async () => {
    const code = 'ACDEFGHJ';
    expect(await hash(code, 'pepper')).toBe(await hash(code, 'pepper'));
    expect(await hash(code, 'pepper')).not.toBe(await hash(code, 'other'));
    expect(await hash(code, '')).toMatch(/^[0-9a-f]{64}$/);
  });

  it('generates opaque device tokens', () => {
    const token = generateToken();
    expect(isToken(token)).toBe(true);
    expect(token).not.toBe(generateToken());
  });

  it('compares in constant time', () => {
    expect(safeEqual('abc', 'abc')).toBe(true);
    expect(safeEqual('abc', 'abd')).toBe(false);
    expect(safeEqual('abc', 'ab')).toBe(false);
  });
});

describe('request validation (required backend tests 4, 12)', () => {
  it('rejects unexpected keys', () => {
    expect(hasOnlyKeys({ name: 'x', items: [] }, ['name', 'items', 'baseVersion'])).toBe(true);
    expect(hasOnlyKeys({ name: 'x', evil: 1 }, ['name'])).toBe(false);
    expect(hasOnlyKeys(null, ['name'])).toBe(false);
    expect(hasOnlyKeys([], ['name'])).toBe(false);
  });

  it('validates ids and tokens', () => {
    expect(isVideoId(A)).toBe(true);
    expect(isVideoId('too-short')).toBe(false);
    expect(isToken('zz')).toBe(false);
  });

  it('reads bearer tokens only in the expected shape', () => {
    const token = generateToken();
    const request = new Request('https://x.test/', { headers: { authorization: `Bearer ${token}` } });
    expect(bearerToken(request)).toBe(token);
    expect(bearerToken(new Request('https://x.test/', { headers: { authorization: 'Bearer nope' } }))).toBeNull();
    expect(bearerToken(new Request('https://x.test/'))).toBeNull();
  });

  it('allows only the configured origins, and app requests without an Origin header', () => {
    const env = { ALLOWED_ORIGINS: 'https://channeltimeline.jewelrysunflower.com,chrome-extension://abcdef' };
    expect(isAllowedOrigin('https://channeltimeline.jewelrysunflower.com', env)).toBe(true);
    expect(isAllowedOrigin('chrome-extension://abcdef', env)).toBe(true);
    expect(isAllowedOrigin('https://evil.example', env)).toBe(false);
    expect(isAllowedOrigin('', env)).toBe(true);
  });

  it('trims and caps free text', () => {
    expect(text('  a   b  ', 10)).toBe('a b');
    expect(text('x'.repeat(50), 10)).toHaveLength(10);
    expect(text(42, 10)).toBe('');
  });
});
