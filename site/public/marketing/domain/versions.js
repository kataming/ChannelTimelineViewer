// Version Performance（アプリのバージョン別の入口・離脱の確認）。画面とテストで共用。
//
// データは GA4 / Firebase（Android 版のみ）の「日別 × イベント別」の集計を、CSV / JSON / 手入力で取り込んだもの。
// 1 行 = VersionMetric:
//   { date, endDate, platform, appVersion, buildVersion, country, eventName, eventCount, users, source }
//   - date: その行の日（YYYY-MM-DD）。endDate が無い（null）なら「日別の行」
//   - endDate: 期間の合計を 1 行で入れるときの終了日（GA4 で期間をまとめて書き出した行）。date〜endDate の合計
//   - country: 国コード（2 文字）または GA4 の国名。空 = 全世界の合計の行
//   - buildVersion: 任意（GA4 の標準ディメンションにビルド番号は無い）
// 同じキー（date + endDate + platform + appVersion + buildVersion + country + eventName）の行は上書きする。
//
// ⚠️ ここで出す数字は「同じ期間に起きたイベントの人数」であって、同じ利用者を追ったコホートではない。
//    D1 / D3 / D7 Retention やアンインストール率は、このデータからは正確に出せない（画面にも明記する）。
import { div, finite, parseAmount, sub, sum } from './num.js';
import { ValidationError } from './model.js';
import { parseCsv, toCsv } from './csv.js';

/** 画面で扱うイベント（この順に並べる）。ほかのイベント名も保存はする。 */
export const VERSION_EVENTS = [
  'first_open', 'session_start', 'channel_tutorial_view', 'channel_open', 'video_open', 'user_engagement', 'app_remove',
];
export const FUNNEL_EVENTS = ['first_open', 'channel_tutorial_view', 'channel_open', 'video_open'];
export const VERSION_PLATFORMS = ['Android', 'iOS', 'Web'];

const clone = (doc) => structuredClone(doc);
const touch = (doc) => { doc.updatedAt = new Date().toISOString(); return doc; };

// --- 入力の読み取り -------------------------------------------------------------------

/** 2026-10-07 / 20261007 / 2026/10/07 を YYYY-MM-DD にする。空なら null、読めなければ undefined。 */
export function readVersionDate(raw) {
  const text = String(raw ?? '').trim();
  if (!text) return null;
  const m = text.match(/^(\d{4})[-/]?(\d{2})[-/]?(\d{2})$/);
  if (!m) return undefined;
  const iso = `${m[1]}-${m[2]}-${m[3]}`;
  const d = new Date(`${iso}T00:00:00Z`);
  return Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== iso ? undefined : iso;
}

export function normalizePlatform(raw) {
  const text = String(raw ?? '').trim();
  const known = { android: 'Android', ios: 'iOS', web: 'Web' }[text.toLowerCase()];
  return known ?? text;
}

/** 国は 2 文字なら国コード（大文字）、それ以外（GA4 の国名・"(not set)"）はそのまま。空 = 全世界の合計。 */
export function normalizeCountry(raw) {
  const text = String(raw ?? '').trim();
  return /^[a-z]{2}$/i.test(text) ? text.toUpperCase() : text;
}

export function versionMetricKey(r) {
  return [r.date, r.endDate ?? '', r.platform, r.appVersion, r.buildVersion, r.country, r.eventName].join('|');
}

/** 1 行を検査して整える。戻り値は行。不正なら ValidationError。 */
export function readVersionMetric(input, { source = 'manual' } = {}) {
  const errors = {};
  const date = readVersionDate(input.date);
  if (date === undefined) errors.date = '日付は YYYY-MM-DD か YYYYMMDD';
  else if (date === null) errors.date = '日付は必須です';
  let endDate = readVersionDate(input.endDate);
  if (endDate === undefined) { errors.endDate = '終了日は YYYY-MM-DD か YYYYMMDD'; endDate = null; }
  if (endDate && date && endDate < date) errors.endDate = '終了日が日付より前です';
  if (endDate && endDate === date) endDate = null; // 1 日だけの期間は日別の行と同じ
  const appVersion = String(input.appVersion ?? '').trim();
  if (!appVersion) errors.appVersion = 'App Version は必須です';
  const eventName = String(input.eventName ?? '').trim();
  if (!eventName) errors.eventName = 'Event Name は必須です';
  else if (!/^[A-Za-z0-9_]+$/.test(eventName)) errors.eventName = 'Event Name は英数字と _ だけ';
  const numbers = {};
  for (const key of ['eventCount', 'users']) {
    const r = parseAmount(input[key], { integer: true });
    if (r.ok) numbers[key] = r.value; else errors[key] = r.error;
  }
  if (!errors.eventCount && !errors.users && numbers.eventCount === null && numbers.users === null) {
    errors.users = 'Users か Event Count のどちらかは必要です';
  }
  if (Object.keys(errors).length) throw new ValidationError(errors);
  return {
    date,
    endDate,
    platform: normalizePlatform(input.platform),
    appVersion,
    buildVersion: String(input.buildVersion ?? '').trim(),
    country: normalizeCountry(input.country),
    eventName,
    eventCount: numbers.eventCount,
    users: numbers.users,
    source: String(input.source ?? source),
  };
}

// --- 保存の操作（元の doc は変えずに新しい doc を返す） ------------------------------------

/** 行をまとめて入れる。同じキーは上書き。戻り値: { doc, added, updated }。 */
export function upsertVersionMetrics(doc, rows) {
  const next = clone(doc);
  const list = Array.isArray(next.versionMetrics) ? next.versionMetrics : [];
  const index = new Map(list.map((r, i) => [versionMetricKey(r), i]));
  let added = 0;
  let updated = 0;
  for (const row of rows) {
    const key = versionMetricKey(row);
    if (index.has(key)) { list[index.get(key)] = row; updated += 1; }
    else { index.set(key, list.length); list.push(row); added += 1; }
  }
  next.versionMetrics = list;
  return { doc: touch(next), added, updated };
}

/** 手入力の 1 行（同じキーがあれば上書き）。 */
export function addVersionMetric(doc, input) {
  return upsertVersionMetrics(doc, [readVersionMetric(input, { source: 'manual' })]).doc;
}

export function deleteVersionMetric(doc, key) {
  const list = doc.versionMetrics ?? [];
  if (!list.some((r) => versionMetricKey(r) === key)) throw new ValidationError({ row: '行が見つかりません' });
  const next = clone(doc);
  next.versionMetrics = list.filter((r) => versionMetricKey(r) !== key);
  return touch(next);
}

// --- CSV / JSON --------------------------------------------------------------------------

export const VERSION_COLUMNS = [
  'date', 'end_date', 'platform', 'appVersion', 'buildVersion', 'country', 'eventName', 'eventCount', 'users',
];

/** 列名の表記ゆれ（GA4 の書き出し・日本語 UI も含む）。比較は小文字・空白/_ 除去で行う。 */
const HEADER_ALIASES = {
  date: ['date', '日付', 'startdate', 'start_date'],
  endDate: ['enddate', 'end_date', '終了日', 'dateto'],
  platform: ['platform', 'プラットフォーム', 'stream', 'streamname'],
  appVersion: ['appversion', 'アプリのバージョン', 'versionname', 'version'],
  buildVersion: ['buildversion', 'build', 'versioncode', 'ビルド'],
  country: ['country', 'countryid', 'countrycode', 'country_code', '国', '国id'],
  eventName: ['eventname', 'event', 'イベント名'],
  eventCount: ['eventcount', 'イベント数'],
  users: ['users', 'totalusers', 'activeusers', '総ユーザー数', 'アクティブユーザー数', 'ユーザー', 'ユーザー数'],
};
const squash = (h) => String(h).trim().toLowerCase().replace(/[\s_]/g, '');
const ALIAS_TO_FIELD = new Map(Object.entries(HEADER_ALIASES).flatMap(([field, list]) => list.map((a) => [squash(a), field])));

function mapRow(raw) {
  const out = {};
  for (const [header, value] of Object.entries(raw)) {
    const field = ALIAS_TO_FIELD.get(squash(header));
    // 同じ意味の列が 2 つある（Country と Country ID など）ときは、国コードを優先
    if (!field || (field in out && out[field] !== '' && !(field === 'country' && /^[a-z]{2}$/i.test(value)))) continue;
    out[field] = value;
  }
  return out;
}

/** 行の配列（列名つき）を取り込む。不正な行は飛ばしてエラーとして返す。 */
function importRows(doc, rawRows, { source, firstLine }) {
  const rows = [];
  const errors = [];
  rawRows.forEach((raw, i) => {
    try {
      rows.push(readVersionMetric(mapRow(raw), { source }));
    } catch (e) {
      errors.push({ line: i + firstLine, message: e.message });
    }
  });
  const res = upsertVersionMetrics(doc, rows);
  return { ...res, errors };
}

/**
 * CSV の取り込み。GA4 の探索の書き出し（先頭の「# 」で始まるコメント行・数字の桁区切り・日付 20261007）も読む。
 * 1 行目（コメントを除く）が列名。
 */
export function importVersionMetricsCsv(doc, text) {
  const lines = String(text).replace(/^﻿/, '').split(/\r?\n/);
  const skipped = lines.findIndex((l) => l.trim() !== '' && !l.trim().startsWith('#'));
  const body = skipped < 0 ? '' : lines.slice(skipped).filter((l) => !l.trim().startsWith('#')).join('\n');
  return importRows(doc, parseCsv(body), { source: 'csv', firstLine: skipped + 2 });
}

/**
 * JSON の取り込み。次のどれでもよい:
 *   - VersionMetric の配列
 *   - { versionMetrics: [...] }（このサイトの JSON バックアップ）
 *   - GA4 Data API の runReport の応答（dimensionHeaders / metricHeaders / rows）。将来の自動連携と同じ形
 */
export function importVersionMetricsJson(doc, text) {
  let data;
  try { data = JSON.parse(text); } catch (e) { return { doc, added: 0, updated: 0, errors: [{ line: 0, message: `JSON を読めません: ${e.message}` }] }; }
  let rows = null;
  if (Array.isArray(data)) rows = data;
  else if (Array.isArray(data?.versionMetrics)) rows = data.versionMetrics;
  else if (Array.isArray(data?.dimensionHeaders) && Array.isArray(data?.metricHeaders)) rows = fromGa4Report(data);
  if (!rows) return { doc, added: 0, updated: 0, errors: [{ line: 0, message: '配列・{ versionMetrics } ・GA4 runReport のどれでもありません' }] };
  return importRows(doc, rows.map((r) => (r && typeof r === 'object' ? r : {})), { source: 'json', firstLine: 1 });
}

/** GA4 Data API の runReport 応答を、列名つきの行に直す（呼び出しはしない。形を合わせるだけ）。 */
export function fromGa4Report(report) {
  const dims = report.dimensionHeaders.map((h) => h.name);
  const mets = report.metricHeaders.map((h) => h.name);
  return (report.rows ?? []).map((row) => {
    const out = {};
    dims.forEach((name, i) => { out[name] = row.dimensionValues?.[i]?.value ?? ''; });
    mets.forEach((name, i) => { out[name] = row.metricValues?.[i]?.value ?? ''; });
    return out;
  });
}

export function exportVersionMetricsCsv(doc) {
  return toCsv(VERSION_COLUMNS, (doc.versionMetrics ?? []).map((r) => ({
    date: r.date, end_date: r.endDate, platform: r.platform, appVersion: r.appVersion, buildVersion: r.buildVersion,
    country: r.country, eventName: r.eventName, eventCount: r.eventCount, users: r.users,
  })));
}

// --- 集計 --------------------------------------------------------------------------------

/** "1.9" < "1.18" < "1.19" のように数字の部分を数として比べる。 */
export function compareVersions(a, b) {
  const pa = String(a).split(/[.\-+]/);
  const pb = String(b).split(/[.\-+]/);
  for (let i = 0; i < Math.max(pa.length, pb.length); i += 1) {
    const x = pa[i] ?? '';
    const y = pb[i] ?? '';
    const nx = /^\d+$/.test(x) ? Number(x) : null;
    const ny = /^\d+$/.test(y) ? Number(y) : null;
    const c = nx !== null && ny !== null ? nx - ny : x.localeCompare(y);
    if (c) return c;
  }
  return 0;
}

/** 取り込んだデータの日付の範囲と、選べる値の一覧（フィルターの選択肢）。 */
export function versionMetricFacets(rows = []) {
  const dates = rows.flatMap((r) => [r.date, r.endDate]).filter(Boolean).sort();
  const uniq = (key) => [...new Set(rows.map((r) => r[key]))];
  return {
    minDate: dates[0] ?? null,
    maxDate: dates[dates.length - 1] ?? null,
    platforms: uniq('platform').sort(),
    countries: uniq('country').filter(Boolean).sort(),
    versions: uniq('appVersion').sort(compareVersions),
    events: uniq('eventName').sort(),
  };
}

/** 期間に入る行か。日別の行は日付が範囲内、期間の行は期間ごと範囲内に収まるときだけ。 */
function inRange(r, start, end) {
  const from = r.date;
  const to = r.endDate ?? r.date;
  return (!start || from >= start) && (!end || to <= end);
}

/**
 * 1 つの国（または全世界の合計の行）について、あるイベントの Users / Event Count を決める。
 * - 期間の合計の行（endDate あり）が範囲内にあれば、その中で一番長い期間の行を使う（GA4 の期間で一意の Users）
 * - 無ければ日別の行を足す。2 日以上を足した Users は「日別 Users の合計」で、同じ人を重ねて数えうる
 */
function pickCell(rows) {
  const periods = rows.filter((r) => r.endDate);
  if (periods.length) {
    const span = (r) => Date.parse(r.endDate) - Date.parse(r.date);
    const best = periods.slice().sort((a, b) => span(b) - span(a) || b.endDate.localeCompare(a.endDate))[0];
    return { users: finite(best.users), eventCount: finite(best.eventCount), basis: 'period', days: span(best) / 86400000 + 1 };
  }
  const days = new Set(rows.map((r) => r.date)).size;
  return {
    users: sum(rows.map((r) => r.users)),
    eventCount: sum(rows.map((r) => r.eventCount)),
    basis: days > 1 ? 'daily-sum' : 'daily',
    days,
  };
}

function addCells(cells) {
  if (!cells.length) return null;
  return {
    users: sum(cells.map((c) => c.users)),
    eventCount: sum(cells.map((c) => c.eventCount)),
    basis: cells.some((c) => c.basis === 'daily-sum') ? 'daily-sum' : cells.some((c) => c.basis === 'period') ? 'period' : 'daily',
    days: Math.max(...cells.map((c) => c.days)),
  };
}

/** 率の計算（バージョン 1 つ分）。分母が 0 や不明なら null。 */
export function versionRates(events) {
  const u = (name) => events[name]?.users ?? null;
  return {
    firstOpenToChannelOpen: div(u('channel_open'), u('first_open')),
    firstOpenToVideoOpen: div(u('video_open'), u('first_open')),
    channelOpenToVideoOpen: div(u('video_open'), u('channel_open')),
    firstOpenToTutorial: div(u('channel_tutorial_view'), u('first_open')),
    // 同じ期間に起きた app_remove と first_open の人数の単純な比。削除した人が同じ期間に入れた人とは限らない
    removePerFirstOpen: div(u('app_remove'), u('first_open')),
  };
}

/**
 * バージョン別の集計。filters: { start, end, platform, country, version }（空 = すべて）。
 * 戻り値はバージョン × プラットフォームごとの行（新しいバージョンが先）。
 *
 * 国の扱い: 国を選んだらその国の行だけ。「すべての国」のときは、全世界の合計の行（country 空）が
 * あればそれを使い、無ければ国別の行を足す（両方を足すと二重になるため）。
 */
export function summarizeVersions(rows = [], filters = {}) {
  const { start = '', end = '', platform = '', country = '', version = '' } = filters;
  const base = rows.filter((r) => (!platform || r.platform === platform) && (!version || r.appVersion === version));
  const byCountry = (r) => (country ? r.country === country : true);
  const groups = new Map();
  for (const r of base) {
    const key = `${r.appVersion}\u0000${r.platform}`;
    if (!groups.has(key)) groups.set(key, { appVersion: r.appVersion, platform: r.platform, all: [] });
    groups.get(key).all.push(r);
  }
  const out = [];
  for (const g of groups.values()) {
    const scoped = g.all.filter(byCountry);
    const firstSeen = scoped.map((r) => r.date).sort()[0] ?? null;
    let rowsIn = scoped.filter((r) => inRange(r, start, end));
    if (!country) {
      const totalRows = rowsIn.filter((r) => !r.country);
      rowsIn = totalRows.length ? totalRows : rowsIn;
    }
    if (!rowsIn.length) continue;
    const events = {};
    for (const name of [...new Set(rowsIn.map((r) => r.eventName))]) {
      const ofEvent = rowsIn.filter((r) => r.eventName === name);
      const perCountry = new Map();
      for (const r of ofEvent) {
        if (!perCountry.has(r.country)) perCountry.set(r.country, []);
        perCountry.get(r.country).push(r);
      }
      events[name] = addCells([...perCountry.values()].map(pickCell));
    }
    const countries = [...new Set(rowsIn.map((r) => r.country))];
    out.push({
      key: `${g.appVersion}|${g.platform}`,
      appVersion: g.appVersion,
      platform: g.platform,
      buildVersions: [...new Set(rowsIn.map((r) => r.buildVersion).filter(Boolean))].sort(compareVersions),
      firstSeen,
      countries: countries.filter(Boolean).sort(),
      hasWorldTotal: countries.includes(''),
      events,
      rates: versionRates(events),
      usersMayDuplicate: Object.values(events).some((e) => e?.basis === 'daily-sum'),
    });
  }
  return out.sort((a, b) => compareVersions(b.appVersion, a.appVersion) || a.platform.localeCompare(b.platform));
}

/** ファネル（first_open → channel_tutorial_view → channel_open → video_open）。 */
export function versionFunnel(summary) {
  const users = (name) => summary?.events[name]?.users ?? null;
  const first = users('first_open');
  return FUNNEL_EVENTS.map((name, i) => {
    const value = users(name);
    return {
      eventName: name,
      users: value,
      fromPrevious: i === 0 ? null : div(value, users(FUNNEL_EVENTS[i - 1])),
      fromFirstOpen: i === 0 ? null : div(value, first),
    };
  });
}

/** 比べる項目。kind: count（人数・絶対差）/ rate（率・pt 差）。 */
export const COMPARE_ITEMS = [
  ['first_open', 'first_open Users', 'count'],
  ['firstOpenToChannelOpen', 'channel_open rate（÷ first_open）', 'rate'],
  ['firstOpenToVideoOpen', 'video_open rate（÷ first_open）', 'rate'],
  ['channelOpenToVideoOpen', 'video_open ÷ channel_open', 'rate'],
  ['removePerFirstOpen', 'app_remove ÷ first_open（同じ期間の単純比・参考値）', 'rate'],
  ['session_start', 'session_start Users', 'count'],
  ['user_engagement', 'user_engagement Users', 'count'],
];

/** 旧版（a）と新版（b）の比較。率の差は percentage point（0.055 → +5.5pt）。 */
export function compareVersionSummaries(a, b) {
  const value = (s, key, kind) => (!s ? null : kind === 'rate' ? s.rates[key] ?? null : s.events[key]?.users ?? null);
  return COMPARE_ITEMS.map(([key, label, kind]) => {
    const va = value(a, key, kind);
    const vb = value(b, key, kind);
    const diff = sub(vb, va);
    return {
      key, label, kind, a: va, b: vb,
      diff: kind === 'count' ? diff : null,
      diffPt: kind === 'rate' && diff !== null ? finite(Math.round(diff * 100 * 1000) / 1000) : null,
      relative: kind === 'count' ? div(diff, va) : null,
    };
  });
}

/** 国 × バージョンの表（国ごとに summarizeVersions を回す）。値は first_open Users と channel_open rate。 */
export function countryVersionMatrix(rows = [], filters = {}) {
  const facets = versionMetricFacets(rows);
  const countries = filters.country ? [filters.country] : facets.countries;
  const versions = new Set();
  const table = countries.map((code) => {
    const cells = {};
    for (const s of summarizeVersions(rows, { ...filters, country: code })) {
      versions.add(s.key);
      cells[s.key] = { firstOpen: s.events.first_open?.users ?? null, channelRate: s.rates.firstOpenToChannelOpen, usersMayDuplicate: s.usersMayDuplicate };
    }
    return { country: code, cells };
  }).filter((r) => Object.keys(r.cells).length);
  const columns = [...versions].sort((x, y) => compareVersions(y.split('|')[0], x.split('|')[0]) || x.localeCompare(y));
  return { columns, rows: table };
}

/** 差の表示（人数）: +12 / −3 / ±0。不明は —。 */
export function formatDiff(v) {
  const x = finite(v);
  if (x === null) return '—';
  if (x === 0) return '±0';
  return `${x > 0 ? '+' : '−'}${Math.abs(Math.round(x)).toLocaleString('en-US')}`;
}

/** percentage point の表示: +5.5pt / −0.8pt / ±0.0pt。不明は —。 */
export function formatPt(v, digits = 1) {
  const x = finite(v);
  if (x === null) return '—';
  const text = Math.abs(x).toFixed(digits);
  if (Number(text) === 0) return `±${text}pt`;
  return `${x > 0 ? '+' : '−'}${text}pt`;
}
