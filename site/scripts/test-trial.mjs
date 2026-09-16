// Web体験版（src/trial/）の点検。ブラウザを使わず Node だけで回せるものだけを見る。
//   node scripts/test-trial.mjs
//
// 見るのは3つ:
//   1) URL解析（アプリ側の ChannelResolver と同じ結果になるか）
//   2) 一覧・進捗・自動再生の次の行き先など、画面に出る数字の計算
//   3) 画面（TrialApp.astro）と処理（app.js）の食い違い
//      ― app.js が触る id が画面に無い / 使っている文言キーが trial.js に無い、を検出する
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(here, '..');

const { parseInput, isChannelId, isVideoId } = await import('../src/trial/resolve.js');
const model = await import('../src/trial/model.js');
const { trial } = await import('../src/i18n/trial.js');

let failures = 0;
const fail = (message) => {
  failures += 1;
  console.error('  ✗', message);
};
const eq = (actual, expected, label) => {
  const a = JSON.stringify(actual);
  const b = JSON.stringify(expected);
  if (a !== b) fail(`${label}: ${a} ≠ ${b}`);
};

// ---------------------------------------------------------------- 1) URL解析

const CHANNEL_ID = 'UC1234567890abcdefghijkl'; // UC + 22文字
const VIDEO_ID = 'dQw4w9WgXcQ';

eq(isChannelId(CHANNEL_ID), true, 'isChannelId');
eq(isChannelId('UCshort'), false, 'isChannelId(短い)');
eq(isVideoId(VIDEO_ID), true, 'isVideoId');
eq(isVideoId('too-short'), false, 'isVideoId(短い)');

const cases = [
  ['@handle', { kind: 'handle', value: 'handle' }],
  [CHANNEL_ID, { kind: 'channelId', value: CHANNEL_ID }],
  [`https://www.youtube.com/channel/${CHANNEL_ID}`, { kind: 'channelId', value: CHANNEL_ID }],
  ['https://www.youtube.com/@handle', { kind: 'handle', value: 'handle' }],
  ['youtube.com/@handle', { kind: 'handle', value: 'handle' }],
  ['https://www.youtube.com/@handle/videos', { kind: 'handle', value: 'handle' }],
  ['https://www.youtube.com/user/SomeUser', { kind: 'username', value: 'SomeUser' }],
  ['https://www.youtube.com/c/SomeName', { kind: 'name', value: 'SomeName' }],
  ['https://www.youtube.com/SomeName', { kind: 'name', value: 'SomeName' }],
  [`https://www.youtube.com/watch?v=${VIDEO_ID}`, { kind: 'video', value: VIDEO_ID }],
  [`https://www.youtube.com/watch?v=${VIDEO_ID}&t=30s`, { kind: 'video', value: VIDEO_ID }],
  [`https://youtu.be/${VIDEO_ID}`, { kind: 'video', value: VIDEO_ID }],
  [`https://www.youtube.com/shorts/${VIDEO_ID}`, { kind: 'video', value: VIDEO_ID }],
  [`https://www.youtube.com/live/${VIDEO_ID}`, { kind: 'video', value: VIDEO_ID }],
  [`https://m.youtube.com/watch?v=${VIDEO_ID}`, { kind: 'video', value: VIDEO_ID }],
  ['  https://www.youtube.com/@handle  ', { kind: 'handle', value: 'handle' }],
  ['https://example.com/@handle', null],
  ['https://www.youtube.com/watch?v=broken', null],
  ['', null],
  ['ただの文字列', null],
];
for (const [input, expected] of cases) {
  eq(parseInput(input), expected, `parseInput(${JSON.stringify(input)})`);
}

// ---------------------------------------------------------------- 2) 計算

const day = 24 * 60 * 60 * 1000;
const videos = [
  { id: 'a', title: '1本目', published: day * 1 },
  { id: 'b', title: '2本目', published: day * 2 },
  { id: 'c', title: '3本目', published: day * 3 },
  { id: 'd', title: '4本目', published: day * 4 },
];
const watched = new Set(['a', 'c']);
const skipped = new Set(['b']);
const isWatched = (id) => watched.has(id);
const isSkipped = (id) => skipped.has(id);

eq(model.sortVideos(videos, true).map((v) => v.id), ['a', 'b', 'c', 'd'], '古い順');
eq(model.sortVideos(videos, false).map((v) => v.id), ['d', 'c', 'b', 'a'], '新しい順');
eq(
  model.visibleVideos(videos, { sort: 'oldest', filter: 'unwatched', isWatched }).map((v) => v.id),
  ['b', 'd'],
  '未視聴のみ'
);
eq(
  model.visibleVideos(videos, { sort: 'newest', filter: 'watched', isWatched }).map((v) => v.id),
  ['c', 'a'],
  '視聴済みのみ（新しい順）'
);
eq(model.progressOf(videos, isWatched), { done: 2, total: 4, percent: 50 }, '進捗');
eq(model.progressOf([], isWatched), { done: 0, total: 0, percent: 0 }, '進捗（空）');

// 「次に見る」はスキップ指定を飛ばす
eq(model.nextUnwatchedIndex(videos, isWatched, isSkipped), 3, '次に見る');
eq(model.nextUnwatchedIndex(videos, () => true, () => false), -1, '次に見る（全部視聴済み）');

// 自動再生の行き先
eq(
  model.nextIndexForAutoAdvance(videos, 0, { isWatched, isSkipped }),
  2,
  '自動再生: スキップを飛ばす'
);
eq(
  model.nextIndexForAutoAdvance(videos, 0, { isWatched, isSkipped, unwatchedOnly: true }),
  3,
  '自動再生: 未視聴のみ'
);
eq(model.nextIndexForAutoAdvance(videos, 3, { isWatched, isSkipped }), -1, '自動再生: 末尾で止まる');
eq(
  model.nextIndexForAutoAdvance(videos, 3, { isWatched, isSkipped, repeatAll: true }),
  0,
  '自動再生: 全体リピートで先頭へ'
);
eq(
  model.nextIndexForAutoAdvance(videos, 3, { isWatched: () => true, isSkipped, unwatchedOnly: true, repeatAll: true }),
  -1,
  '自動再生: 進める先が無ければ止まる'
);

// 再生位置の保存規則（アプリと同じ: 10秒未満は捨てる／終端15秒以内も捨てる）
eq(model.positionToStore(5, 600), null, '位置: 冒頭すぎる');
eq(model.positionToStore(120, 600), { t: 120, d: 600 }, '位置: 保存する');
eq(model.positionToStore(590, 600), null, '位置: ほぼ見終わっている');
eq(model.resumeSeconds({ t: 120, d: 600 }, true), 120, '再開: 設定オン');
eq(model.resumeSeconds({ t: 120, d: 600 }, false), 0, '再開: 設定オフ');
eq(model.resumeSeconds(null, true), 0, '再開: 記録なし');

eq(model.formatSeconds(0), '0:00', '時間表示 0');
eq(model.formatSeconds(75), '1:15', '時間表示 分');
eq(model.formatSeconds(3725), '1:02:05', '時間表示 時');
eq(model.fmt('{1} / {2}', 3, 10), '3 / 10', '差し込み');

// ---------------------------------------------------------------- 3) 画面と処理の食い違い

const appSource = await readFile(path.join(root, 'src/trial/app.js'), 'utf8');
const pageSource = await readFile(path.join(root, 'src/components/TrialApp.astro'), 'utf8');

const usedIds = new Set([...appSource.matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]));
const pageIds = new Set([...pageSource.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));
for (const id of usedIds) {
  if (!pageIds.has(id)) fail(`app.js が触る id が TrialApp.astro に無い: #${id}`);
}

// 絞り込みの値（並び替えは #ctv-sort-toggle の1ボタンで切り替える）
for (const value of ['all', 'unwatched', 'watched']) {
  if (!pageSource.includes(`data-filter="${value}"`)) fail(`TrialApp.astro に data-filter="${value}" が無い`);
}

// アプリに寄せた部品が揃っているか（作り直しで欠けやすいところ）
const parts = {
  '上部バー': 'class="ctv-appbar"',
  '戻るボタン': 'id="ctv-back"',
  'iOS風スイッチ': 'class="ctv-switch"',
  '丸い移動ボタン': 'class="ctv-nav-btn"',
  '「次に見る」カード': 'class="ctv-next-card"',
  '全幅のYouTubeボタン': 'class="ctv-yt"',
};
for (const [name, needle] of Object.entries(parts)) {
  if (!pageSource.includes(needle)) fail(`TrialApp.astro に${name}（${needle}）が無い`);
}
// 一覧画面と再生画面を切り替える土台
if (!pageSource.includes('data-screen="list"')) fail('TrialApp.astro に data-screen が無い');
if (!appSource.includes('setScreen(')) fail('app.js に setScreen() が無い');

// 文言キー（app.js が使うものが7言語すべてに在るか）
const usedKeys = new Set([...appSource.matchAll(/\bui\.([A-Za-z][A-Za-z0-9]*)/g)].map((m) => m[1]));
for (const key of usedKeys) {
  if (!(key in trial.en)) {
    if (!(key in trial.en.ui)) fail(`app.js が使う文言キーが trial.js(en) に無い: ui.${key}`);
  }
}
for (const [code, dict] of Object.entries(trial)) {
  for (const key of Object.keys(trial.en.ui)) {
    if (!(key in dict.ui)) fail(`trial.js(${code}) に ui.${key} が無い`);
  }
  for (const key of Object.keys(trial.en)) {
    if (!(key in dict)) fail(`trial.js(${code}) に ${key} が無い`);
  }
  if (dict.notes.length !== trial.en.notes.length) fail(`trial.js(${code}) の notes の数が違う`);
  if (dict.faq.length !== trial.en.faq.length) fail(`trial.js(${code}) の faq の数が違う`);
}

// 画面が2か所（/try/ とトップのヒーロー）で同じ中身を使っているか
const tryPage = await readFile(path.join(root, 'src/pages/[lang]/try.astro'), 'utf8');
const homePage = await readFile(path.join(root, 'src/pages/[lang]/index.astro'), 'utf8');
if (!/<TrialApp[^>]*variant="full"/.test(tryPage)) fail('try.astro が TrialApp(variant="full") を使っていない');
if (!/<TrialApp[^>]*variant="phone"/.test(homePage)) fail('index.astro が TrialApp(variant="phone") を使っていない');
// CSS と起動は TrialApp.astro 自身が持つ（使う側は置くだけでよい）
if (!pageSource.includes("import '../trial/trial.css'")) fail('TrialApp.astro が trial.css を読み込んでいない');
if (!pageSource.includes('startTrial()')) fail('TrialApp.astro が startTrial() を呼んでいない');

// ---------------------------------------------------------------- 4) Watch Queue モード

const queueModel = await import('../src/trial/queue-model.js');
const { watchQueue } = await import('../src/i18n/watchQueue.js');

const A = 'aaaaaaaaaa1';
const B = 'bbbbbbbbbb2';
const C = 'cc-cc_cccc3';
eq(queueModel.parseQueueHash(`#v=1&ids=${A},${B},${C}`), { ok: true, version: 1, ids: [A, B, C], truncated: false }, 'キュー: 正規形');
eq(queueModel.parseQueueHash(`v=1&ids=${A}`), { ok: true, version: 1, ids: [A], truncated: false }, 'キュー: # なし');
eq(queueModel.parseQueueHash(`#ids=${A}&v=1`), { ok: true, version: 1, ids: [A], truncated: false }, 'キュー: 並び順が逆');
eq(
  queueModel.parseQueueHash(`#v=1&ids=${B},bad,${A},${B},%3Cx%3E,${C}`),
  { ok: true, version: 1, ids: [B, A, C], truncated: false },
  'キュー: 不正・重複を捨てて順番は守る'
);
eq(queueModel.parseQueueHash(`#v=1&ids=${A}%2C${B}`), { ok: true, version: 1, ids: [A, B], truncated: false }, 'キュー: カンマがエンコード');
eq(queueModel.parseQueueHash(''), { ok: false, reason: 'missing' }, 'キュー: 空');
eq(queueModel.parseQueueHash('#'), { ok: false, reason: 'missing' }, 'キュー: # だけ');
// V2: キュー本体は同期サーバーにあり、URL には queueId だけが載る
{
  const queueId = '7f1d9a2c-0b44-4f6e-9a11-2c3d4e5f6a7b';
  eq(queueModel.parseQueueHash(`#v=2&q=${queueId}`), { ok: true, version: 2, queueId }, 'キュー: V2 は queueId を受け取る');
}
eq(queueModel.parseQueueHash('#v=2'), { ok: false, reason: 'empty' }, 'キュー: V2 で queueId が無い');
eq(queueModel.parseQueueHash('#v=2&q=bad%20id!'), { ok: false, reason: 'empty' }, 'キュー: V2 の queueId が不正');
eq(queueModel.parseQueueHash(`#v=3&ids=${A}`), { ok: false, reason: 'version' }, 'キュー: 未知の版');
eq(queueModel.parseQueueHash(`#ids=${A}`), { ok: false, reason: 'version' }, 'キュー: 版なし');
eq(queueModel.parseQueueHash('#v=1&ids='), { ok: false, reason: 'empty' }, 'キュー: ids 空');
eq(queueModel.parseQueueHash('#v=1&ids=bad,worse'), { ok: false, reason: 'empty' }, 'キュー: 有効な ID なし');
{
  const many = Array.from({ length: queueModel.QUEUE_MAX_IDS + 3 }, (_, i) => `v${String(i).padStart(10, '0')}`);
  const r = queueModel.parseQueueHash(`#v=1&ids=${many.join(',')}`);
  eq([r.ok, r.ids.length, r.truncated], [true, queueModel.QUEUE_MAX_IDS, true], 'キュー: 上限で打ち切り');
}

const unplayable = new Set([1, 3]);
eq(queueModel.nextPlayableIndex(5, 0, (i) => unplayable.has(i)), 2, 'キュー: 再生できない動画を飛ばす');
eq(queueModel.nextPlayableIndex(5, 3, (i) => unplayable.has(i)), 4, 'キュー: 次');
eq(queueModel.nextPlayableIndex(5, 4), -1, 'キュー: 末尾で終わり');
eq(queueModel.nextPlayableIndex(3, -1, (i) => i === 0), 1, 'キュー: 先頭から探す');
eq(queueModel.upNextIndex(4, (i) => i < 2, (i) => i === 2), 3, 'キュー: 次に見る');
eq(queueModel.upNextIndex(2, () => true), -1, 'キュー: 全部再生済み');

eq(queueModel.countText(watchQueue.en, 1, 'en'), '1 video', '件数: en 単数');
eq(queueModel.countText(watchQueue.en, 3, 'en'), '3 videos', '件数: en 複数');
eq(queueModel.countText(watchQueue.ja, 3, 'ja'), '3本', '件数: ja');
eq(queueModel.countText(watchQueue.de, 1200, 'de'), '1.200 Videos', '件数: de 桁区切り');

// 文言: 7言語すべてに同じキー・空でない・差し込みの数が同じ
const placeholders = (s) => (String(s).match(/\{\d+\}/g) || []).sort().join(',');
for (const code of Object.keys(trial)) {
  const dict = watchQueue[code];
  if (!dict) {
    fail(`watchQueue.js に ${code} が無い`);
    continue;
  }
  for (const key of Object.keys(watchQueue.en)) {
    if (key === 'meta') continue;
    if (!(key in dict)) fail(`watchQueue.js(${code}) に ${key} が無い`);
    else if (!String(dict[key]).trim()) fail(`watchQueue.js(${code}).${key} が空`);
    else if (placeholders(dict[key]) !== placeholders(watchQueue.en[key])) fail(`watchQueue.js(${code}).${key} の差し込みが英語と違う`);
  }
  for (const key of ['title', 'description']) {
    if (!dict.meta || !String(dict.meta[key] || '').trim()) fail(`watchQueue.js(${code}).meta.${key} が空`);
  }
}
if (Object.keys(watchQueue).length !== Object.keys(trial).length) fail('watchQueue.js の言語数が trial.js と違う');

// queue.js と画面・文言の対応（未翻訳キーの露出を防ぐ）
const queueSource = await readFile(path.join(root, 'src/trial/queue.js'), 'utf8');
for (const id of new Set([...queueSource.matchAll(/\$\('([^']+)'\)/g)].map((m) => m[1]))) {
  if (!pageIds.has(id)) fail(`queue.js が触る id が TrialApp.astro に無い: #${id}`);
}
for (const key of new Set([...queueSource.matchAll(/\bui\.([A-Za-z][A-Za-z0-9]*)/g)].map((m) => m[1]))) {
  if (!(key in trial.en.ui)) fail(`queue.js が使う文言キーが trial.js(en) に無い: ui.${key}`);
}
for (const key of new Set([...queueSource.matchAll(/\bq\.([A-Za-z][A-Za-z0-9]*)/g)].map((m) => m[1]))) {
  if (!(key in watchQueue.en)) fail(`queue.js が使う文言キーが watchQueue.js(en) に無い: q.${key}`);
}
for (const id of ['ctv-queue-invalid', 'ctv-queue-unplayable', 'ctv-queue-completed', 'ctv-queue-skip', 'ctv-queue-restart']) {
  if (!pageIds.has(id)) fail(`TrialApp.astro に #${id} が無い`);
}
if (!appSource.includes("root.dataset.mode === 'queue'")) fail('app.js が Watch Queue モードで体験版を起動しないようになっていない');

// Watch Queue は通常ページから参照しない
for (const rel of ['src/pages/[lang]/index.astro', 'src/pages/[lang]/try.astro', 'src/pages/[lang]/manual.astro', 'src/pages/[lang]/support.astro', 'src/pages/[lang]/privacy.astro', 'src/components/Header.astro', 'src/components/Footer.astro', 'src/i18n/pages.js']) {
  const source = await readFile(path.join(root, rel), 'utf8');
  if (/watch-queue|watchQueue|mode="queue"/.test(source)) fail(`${rel} が Watch Queue を参照している（通常ページに出さない）`);
}

// ---------------------------------------------------------------- 結果

if (failures) {
  console.error(`\n体験版の点検で ${failures} 件の問題がありました。`);
  process.exit(1);
}
console.log('OK: Web体験版（URL解析・計算・画面と処理の対応・7言語の文言）');
