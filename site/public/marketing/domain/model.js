// データを変える操作。画面からもテストからも、ここを通して変更する。
// 各操作は元の doc を変えずに新しい doc を返す。入力が不正なら ValidationError を投げる。
import { parseAmount } from './num.js';
import {
  INTEGER_METRICS, LANGUAGE_NAMES, LOCALIZATION_ITEMS, METRIC_FIELDS, PRICE_STATUSES, PRIORITIES,
  newCountry,
} from './schema.js';

export class ValidationError extends Error {
  constructor(errors) {
    super(Object.entries(errors).map(([k, v]) => `${k}: ${v}`).join(' / '));
    this.errors = errors;
  }
}

const clone = (doc) => structuredClone(doc);
const today = () => new Date().toISOString().slice(0, 10);
const uid = (prefix) => `${prefix}_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;

function touch(doc) {
  doc.updatedAt = new Date().toISOString();
  return doc;
}

/** 数値の項目をまとめて読む。errors に溜めて最後にまとめて投げる。 */
function readNumbers(input, specs, errors) {
  const out = {};
  for (const [key, opts] of Object.entries(specs)) {
    if (!(key in input)) continue;
    const r = parseAmount(input[key], opts);
    if (r.ok) out[key] = r.value; else errors[key] = r.error;
  }
  return out;
}

function findCountry(doc, id) {
  const country = doc.countries.find((c) => c.id === id);
  if (!country) throw new ValidationError({ country: '国が見つかりません' });
  return country;
}

function readDate(value, key, errors) {
  if (value === null || value === undefined || String(value).trim() === '') return null;
  const text = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text) || Number.isNaN(Date.parse(text))) {
    errors[key] = '日付は YYYY-MM-DD で入力してください';
    return null;
  }
  return text;
}

// --- 国 ------------------------------------------------------------------------

function readCountryFields(input, errors) {
  const out = {};
  if ('name' in input) {
    out.name = String(input.name ?? '').trim();
    if (!out.name) errors.name = '国名は必須です';
  }
  if ('code' in input) {
    out.code = String(input.code ?? '').trim().toUpperCase();
    if (!/^[A-Z]{2}$/.test(out.code)) errors.code = '国コードは 2 文字（例 BD）';
  }
  if ('currency' in input) {
    out.currency = String(input.currency ?? '').trim().toUpperCase();
    if (out.currency && !/^[A-Z]{3}$/.test(out.currency)) errors.currency = '通貨は 3 文字（例 BDT）';
  }
  if ('languages' in input) {
    const list = Array.isArray(input.languages) ? input.languages : String(input.languages ?? '').split(/[;|]/);
    out.languages = [...new Set(list.map((s) => String(s).trim()).filter(Boolean))];
    const unknown = out.languages.filter((l) => !LANGUAGE_NAMES[l]);
    if (unknown.length) errors.languages = `不明な言語コード: ${unknown.join(', ')}`;
  }
  if ('priority' in input) {
    out.priority = input.priority || null;
    if (out.priority && !PRIORITIES.includes(out.priority)) errors.priority = '優先度は A / B / C / Hold';
  }
  if ('priceStatus' in input) {
    out.priceStatus = input.priceStatus || null;
    if (out.priceStatus && !PRICE_STATUSES.includes(out.priceStatus)) errors.priceStatus = '不明なステータス';
  }
  if ('tags' in input) {
    const list = Array.isArray(input.tags) ? input.tags : String(input.tags ?? '').split(/[;|]/);
    out.tags = [...new Set(list.map((s) => String(s).trim()).filter(Boolean))];
  }
  for (const key of ['notes', 'candidateReason']) {
    if (key in input) out[key] = String(input[key] ?? '');
  }
  Object.assign(out, readNumbers(input, { price: {}, nextCandidatePrice: {} }, errors));
  return out;
}

export function addCountry(doc, input) {
  const errors = {};
  const fields = readCountryFields({ name: '', code: '', ...input }, errors);
  if (doc.countries.some((c) => c.code === fields.code)) errors.code = 'この国コードはすでにあります';
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  const country = newCountry(fields);
  next.countries.push(country);
  if (country.currency) ensureCurrency(next, country.currency);
  return { doc: touch(next), id: country.id };
}

/**
 * 国の基本情報を直す。⚠️ 価格はここでは変えない（変更履歴を残すため changePrice を使う）。
 */
export function updateCountry(doc, id, input) {
  const errors = {};
  const { price: _ignored, ...rest } = input;
  const fields = readCountryFields(rest, errors);
  if (fields.code && doc.countries.some((c) => c.code === fields.code && c.id !== id)) {
    errors.code = 'この国コードはすでにあります';
  }
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(findCountry(next, id), fields);
  if (fields.currency) ensureCurrency(next, fields.currency);
  return touch(next);
}

export function updateMetrics(doc, id, input) {
  const errors = {};
  const specs = Object.fromEntries(METRIC_FIELDS.map((k) => [k, { integer: INTEGER_METRICS.has(k) }]));
  const values = readNumbers(input, specs, errors);
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(findCountry(next, id).metrics, values);
  return touch(next);
}

/** 価格を変える。変更履歴（priceHistory）に必ず1行残す。 */
export function changePrice(doc, id, { newPrice, date, reason = '', notes = '' }) {
  const errors = {};
  const parsed = parseAmount(newPrice);
  if (!parsed.ok) errors.newPrice = parsed.error;
  else if (parsed.value === null) errors.newPrice = '新しい価格を入力してください';
  const when = readDate(date || today(), 'date', errors);
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  const country = findCountry(next, id);
  next.priceHistory.push({
    id: uid('h'),
    date: when,
    countryId: country.id,
    countryName: country.name,
    currency: country.currency,
    oldPrice: country.price,
    newPrice: parsed.value,
    reason: String(reason),
    notes: String(notes),
    recordedAt: new Date().toISOString(),
  });
  country.previousPrice = country.price;
  country.price = parsed.value;
  country.priceChangedAt = when;
  return touch(next);
}

/** 履歴は消さない。あとから補足だけ書き足せる。 */
export function annotateHistory(doc, historyId, notes) {
  const next = clone(doc);
  const row = next.priceHistory.find((h) => h.id === historyId);
  if (!row) throw new ValidationError({ history: '履歴が見つかりません' });
  row.notes = String(notes ?? '');
  return touch(next);
}

export function setLocalization(doc, id, key, value) {
  if (!LOCALIZATION_ITEMS.some(([k]) => k === key)) throw new ValidationError({ key: '不明な項目' });
  if (![true, false, null].includes(value)) throw new ValidationError({ value: 'true / false / null のみ' });
  const next = clone(doc);
  findCountry(next, id).localization[key] = value;
  return touch(next);
}

// --- 為替・設定 ------------------------------------------------------------------

function ensureCurrency(doc, code) {
  if (code === 'JPY' || doc.currencies[code]) return;
  doc.currencies[code] = { rateToJPY: null, updatedAt: null };
}

export function setRate(doc, currency, rawRate, updatedAt) {
  const errors = {};
  const code = String(currency ?? '').trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(code)) errors.currency = '通貨は 3 文字';
  const r = parseAmount(rawRate);
  if (!r.ok) errors.rate = r.error;
  else if (r.value === 0) errors.rate = '0 は入力できません（未入力なら空欄）';
  const when = readDate(updatedAt || today(), 'updatedAt', errors);
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  next.currencies[code] = { rateToJPY: r.value, updatedAt: r.value === null ? null : when };
  return touch(next);
}

/** 手数料はパーセントで受け取り、率（0.15 など）で保存する。 */
export function setFees(doc, { googleFeePercent, otherFeePercent }) {
  const errors = {};
  const values = {};
  for (const [key, raw] of [['googleFeeRate', googleFeePercent], ['otherFeeRate', otherFeePercent]]) {
    if (raw === undefined) continue;
    const r = parseAmount(raw);
    if (!r.ok) errors[key] = r.error;
    else if (r.value === null) errors[key] = '必須です（無ければ 0）';
    else if (r.value >= 100) errors[key] = '100% 未満にしてください';
    else values[key] = r.value / 100;
  }
  if ((values.googleFeeRate ?? doc.settings.googleFeeRate) + (values.otherFeeRate ?? doc.settings.otherFeeRate) >= 1) {
    errors.otherFeeRate = '手数料の合計が 100% 以上になります';
  }
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(next.settings, values);
  return touch(next);
}

export function setGlobal(doc, input) {
  const errors = {};
  const values = readNumbers(input, {
    installs: { integer: true }, purchaseStarts: { integer: true }, purchaseSuccess: { integer: true },
  }, errors);
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(next.settings.global, values);
  if ('installsApprox' in input) next.settings.global.installsApprox = Boolean(input.installsApprox);
  return touch(next);
}

// --- 価格テスト ------------------------------------------------------------------

function readTest(input, errors) {
  const out = readNumbers(input, {
    price: {}, installs: { integer: true }, purchaseStarts: { integer: true },
    purchaseSuccess: { integer: true }, adSpend: {}, grossRevenueJPY: {},
  }, errors);
  if ('start' in input) out.start = readDate(input.start, 'start', errors);
  if ('end' in input) out.end = readDate(input.end, 'end', errors);
  for (const key of ['label', 'notes']) if (key in input) out[key] = String(input[key] ?? '');
  return out;
}

export function addPriceTest(doc, countryId, input) {
  const errors = {};
  const fields = readTest(input, errors);
  if (fields.price === null || fields.price === undefined) errors.price = '価格は必須です';
  if (fields.start && fields.end && fields.end < fields.start) errors.end = '終了日が開始日より前です';
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  const country = findCountry(next, countryId);
  const test = {
    id: uid('t'), countryId, currency: country.currency, label: '', start: null, end: null,
    installs: null, purchaseStarts: null, purchaseSuccess: null, adSpend: null, grossRevenueJPY: null, notes: '',
    ...fields,
  };
  next.priceTests.push(test);
  return { doc: touch(next), id: test.id };
}

export function updatePriceTest(doc, testId, input) {
  const errors = {};
  const fields = readTest(input, errors);
  if ('price' in fields && fields.price === null) errors.price = '価格は必須です';
  const current = doc.priceTests.find((t) => t.id === testId);
  if (!current) errors.test = 'テストが見つかりません';
  const merged = { ...current, ...fields };
  if (merged.start && merged.end && merged.end < merged.start) errors.end = '終了日が開始日より前です';
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(next.priceTests.find((t) => t.id === testId), fields);
  return touch(next);
}

// --- 広告キャンペーン --------------------------------------------------------------

function readCampaign(input, errors) {
  const out = readNumbers(input, {
    dailyBudget: {}, spend: {}, impressions: { integer: true }, clicks: { integer: true }, installs: { integer: true },
  }, errors);
  if ('start' in input) out.start = readDate(input.start, 'start', errors);
  if ('end' in input) out.end = readDate(input.end, 'end', errors);
  for (const key of ['platform', 'name', 'status', 'notes']) if (key in input) out[key] = String(input[key] ?? '').trim();
  return out;
}

export function addCampaign(doc, countryId, input) {
  const errors = {};
  const fields = readCampaign(input, errors);
  if (!fields.name) errors.name = 'キャンペーン名は必須です';
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  findCountry(next, countryId);
  const campaign = {
    id: uid('a'), countryId, platform: '', name: '', dailyBudget: null, spend: null, impressions: null,
    clicks: null, installs: null, start: null, end: null, status: 'Active', notes: '', ...fields,
  };
  next.campaigns.push(campaign);
  return { doc: touch(next), id: campaign.id };
}

export function updateCampaign(doc, campaignId, input) {
  const errors = {};
  const fields = readCampaign(input, errors);
  if ('name' in fields && !fields.name) errors.name = 'キャンペーン名は必須です';
  if (!doc.campaigns.some((c) => c.id === campaignId)) errors.campaign = 'キャンペーンが見つかりません';
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  Object.assign(next.campaigns.find((c) => c.id === campaignId), fields);
  return touch(next);
}

// --- Google 広告の自動取得の設定 -----------------------------------------------------

/** お客様 ID は「123-456-7890」でも「1234567890」でもよい（保存は数字 10 桁）。 */
export function setAdsSettings(doc, { customerId, loginCustomerId, startDate }) {
  const errors = {};
  const readId = (raw, key, required) => {
    const digits = String(raw ?? '').replace(/[\s-]/g, '');
    if (!digits) { if (required) errors[key] = 'お客様 ID を入力してください'; return ''; }
    if (!/^\d{10}$/.test(digits)) errors[key] = 'お客様 ID は 10 桁の数字（例 123-456-7890）';
    return digits;
  };
  const values = {
    customerId: readId(customerId, 'customerId', true),
    loginCustomerId: readId(loginCustomerId, 'loginCustomerId', false),
    startDate: readDate(startDate, 'startDate', errors) || '2025-01-01',
  };
  if (Object.keys(errors).length) throw new ValidationError(errors);
  const next = clone(doc);
  next.settings.adsSync = { ...(next.settings.adsSync ?? {}), ...values };
  return touch(next);
}
