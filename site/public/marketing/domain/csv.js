// CTV Marketing Ops 独自の CSV 形式。
// 取り込みは「列名で読む」だけにして、他社の書き出し形式を推測して解析することはしない。
// Google Ads などの CSV は、列名をこの形式に合わせてから取り込む。
//
// 取り込みの規則:
//   - 1 行目は列名。知らない列は無視する（計算列を含む書き出しをそのまま戻せる）
//   - 空のセルは「変更しない」。値を消したいときは画面で消す
//   - 国は country_code で突き合わせる（無ければ追加）
//   - 価格が変わる行は価格変更履歴に「CSV import」として残す
import { countryStats, campaignStats } from './calc.js';
import {
  addCampaign, addCountry, changePrice, updateCampaign, updateCountry, updateMetrics, setLocalization,
} from './model.js';
import { LOCALIZATION_ITEMS, METRIC_FIELDS } from './schema.js';

export function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  const src = String(text).replace(/^﻿/, '');
  for (let i = 0; i < src.length; i += 1) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"' && src[i + 1] === '"') { field += '"'; i += 1; }
      else if (ch === '"') quoted = false;
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === ',') { row.push(field); field = ''; }
    else if (ch === '\n' || ch === '\r') {
      if (ch === '\r' && src[i + 1] === '\n') i += 1;
      row.push(field); field = '';
      if (row.some((v) => v !== '')) rows.push(row);
      row = [];
    } else field += ch;
  }
  row.push(field);
  if (row.some((v) => v !== '')) rows.push(row);
  if (!rows.length) return [];
  const header = rows[0].map((h) => h.trim());
  return rows.slice(1).map((r) => Object.fromEntries(header.map((h, i) => [h, (r[i] ?? '').trim()])));
}

function cell(value) {
  if (value === null || value === undefined) return '';
  const text = Array.isArray(value) ? value.join(';') : String(value);
  return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
}

export function toCsv(columns, rows) {
  const lines = [columns.join(',')];
  for (const r of rows) lines.push(columns.map((c) => cell(r[c])).join(','));
  return `﻿${lines.join('\r\n')}\r\n`;
}

// appUI → app_ui、grossRevenueJPY → gross_revenue_jpy（略語は 1 語として扱う）
const snake = (s) => s.replace(/([a-z0-9])([A-Z]+)/g, '$1_$2').toLowerCase();
const LOC_COLUMNS = LOCALIZATION_ITEMS.map(([k]) => `loc_${snake(k)}`);

export const COUNTRY_COLUMNS = [
  'country_code', 'country', 'languages', 'currency', 'price', 'previous_price', 'price_changed_at',
  'priority', 'tags', 'price_status', 'next_candidate_price', 'candidate_reason',
  ...METRIC_FIELDS.map(snake), ...LOC_COLUMNS,
  // 以下は書き出し専用の計算列（取り込み時は無視）
  'calc_price_jpy', 'calc_net_per_purchase_jpy', 'calc_cpi', 'calc_cpc', 'calc_install_to_start',
  'calc_install_to_success', 'calc_start_to_success', 'calc_gross_jpy', 'calc_google_fee_jpy',
  'calc_net_jpy', 'calc_profit_jpy', 'calc_roas', 'calc_break_even_rate',
];

export function exportCountriesCsv(doc) {
  const rows = doc.countries.map((c) => {
    const s = countryStats(c, doc.settings, doc.currencies);
    const row = {
      country_code: c.code, country: c.name, languages: c.languages, currency: c.currency, price: c.price,
      previous_price: c.previousPrice, price_changed_at: c.priceChangedAt, priority: c.priority, tags: c.tags,
      price_status: c.priceStatus, next_candidate_price: c.nextCandidatePrice, candidate_reason: c.candidateReason,
      calc_price_jpy: s.priceJPY, calc_net_per_purchase_jpy: s.netPerPurchase, calc_cpi: s.cpi, calc_cpc: s.cpc,
      calc_install_to_start: s.installToStart, calc_install_to_success: s.installToSuccess,
      calc_start_to_success: s.startToSuccess, calc_gross_jpy: s.gross, calc_google_fee_jpy: s.googleFee,
      calc_net_jpy: s.net, calc_profit_jpy: s.profit, calc_roas: s.roas, calc_break_even_rate: s.breakEvenRate,
    };
    for (const k of METRIC_FIELDS) row[snake(k)] = c.metrics[k];
    LOCALIZATION_ITEMS.forEach(([k], i) => {
      const v = c.localization[k];
      row[LOC_COLUMNS[i]] = v === true ? 'yes' : v === false ? 'no' : '';
    });
    return row;
  });
  return toCsv(COUNTRY_COLUMNS, rows);
}

const present = (v) => v !== undefined && v !== '';

/** 戻り値: { doc, added, updated, errors: [{line, message}] }。エラーの行は飛ばして続ける。 */
export function importCountriesCsv(doc, text, { date } = {}) {
  let next = doc;
  let added = 0;
  let updated = 0;
  const errors = [];
  parseCsv(text).forEach((r, index) => {
    const line = index + 2;
    try {
      const code = String(r.country_code ?? '').trim().toUpperCase();
      if (!code) throw new Error('country_code が空です');
      let country = next.countries.find((c) => c.code === code);
      const basics = {};
      if (present(r.country)) basics.name = r.country;
      if (present(r.languages)) basics.languages = r.languages;
      if (present(r.currency)) basics.currency = r.currency;
      if (present(r.priority)) basics.priority = r.priority;
      if (present(r.tags)) basics.tags = r.tags;
      if (present(r.price_status)) basics.priceStatus = r.price_status;
      if (present(r.next_candidate_price)) basics.nextCandidatePrice = r.next_candidate_price;
      if (present(r.candidate_reason)) basics.candidateReason = r.candidate_reason;
      let candidate = next;
      if (!country) {
        const res = addCountry(candidate, { code, name: basics.name ?? code, ...basics, price: r.price || null });
        candidate = res.doc;
        country = candidate.countries.find((c) => c.id === res.id);
        added += 1;
      } else {
        candidate = updateCountry(candidate, country.id, basics);
        if (present(r.price) && Number(r.price) !== country.price) {
          candidate = changePrice(candidate, country.id, {
            newPrice: r.price, date, reason: 'CSV import', notes: '',
          });
        }
        updated += 1;
      }
      const metrics = {};
      for (const k of METRIC_FIELDS) if (present(r[snake(k)])) metrics[k] = r[snake(k)];
      candidate = updateMetrics(candidate, country.id, metrics);
      LOCALIZATION_ITEMS.forEach(([k], i) => {
        const v = String(r[LOC_COLUMNS[i]] ?? '').toLowerCase();
        if (v === 'yes') candidate = setLocalization(candidate, country.id, k, true);
        if (v === 'no') candidate = setLocalization(candidate, country.id, k, false);
      });
      next = candidate;
    } catch (e) {
      errors.push({ line, message: e.message });
    }
  });
  return { doc: next, added, updated, errors };
}

export const CAMPAIGN_COLUMNS = [
  'country_code', 'platform', 'campaign_name', 'daily_budget', 'spend', 'impressions', 'clicks', 'installs',
  'start_date', 'end_date', 'status', 'notes', 'calc_cpc', 'calc_cpi',
];

export function exportCampaignsCsv(doc) {
  const byId = Object.fromEntries(doc.countries.map((c) => [c.id, c]));
  return toCsv(CAMPAIGN_COLUMNS, doc.campaigns.map((c) => {
    const s = campaignStats(c);
    return {
      country_code: byId[c.countryId]?.code, platform: c.platform, campaign_name: c.name,
      daily_budget: c.dailyBudget, spend: c.spend, impressions: c.impressions, clicks: c.clicks,
      installs: c.installs, start_date: c.start, end_date: c.end, status: c.status, notes: c.notes,
      calc_cpc: s.cpc, calc_cpi: s.cpi,
    };
  }));
}

/** 国コード＋プラットフォーム＋キャンペーン名が同じなら更新、無ければ追加。 */
export function importCampaignsCsv(doc, text) {
  let next = doc;
  let added = 0;
  let updated = 0;
  const errors = [];
  parseCsv(text).forEach((r, index) => {
    try {
      const code = String(r.country_code ?? '').trim().toUpperCase();
      const country = next.countries.find((c) => c.code === code);
      if (!country) throw new Error(`国 ${code || '(空)'} が未登録です（先に国を追加）`);
      const fields = {};
      const map = {
        platform: 'platform', campaign_name: 'name', daily_budget: 'dailyBudget', spend: 'spend',
        impressions: 'impressions', clicks: 'clicks', installs: 'installs', start_date: 'start',
        end_date: 'end', status: 'status', notes: 'notes',
      };
      for (const [col, key] of Object.entries(map)) if (present(r[col])) fields[key] = r[col];
      const existing = next.campaigns.find((c) => c.countryId === country.id
        && c.platform === (fields.platform ?? '') && c.name === fields.name);
      if (existing) { next = updateCampaign(next, existing.id, fields); updated += 1; }
      else { next = addCampaign(next, country.id, fields).doc; added += 1; }
    } catch (e) {
      errors.push({ line: index + 2, message: e.message });
    }
  });
  return { doc: next, added, updated, errors };
}

export function exportPriceTestsCsv(doc) {
  const byId = Object.fromEntries(doc.countries.map((c) => [c.id, c]));
  const cols = ['country_code', 'label', 'price', 'currency', 'start_date', 'end_date', 'installs',
    'purchase_starts', 'purchase_success', 'ad_spend', 'gross_revenue_jpy', 'notes'];
  return toCsv(cols, doc.priceTests.map((t) => ({
    country_code: byId[t.countryId]?.code, label: t.label, price: t.price, currency: t.currency,
    start_date: t.start, end_date: t.end, installs: t.installs, purchase_starts: t.purchaseStarts,
    purchase_success: t.purchaseSuccess, ad_spend: t.adSpend, gross_revenue_jpy: t.grossRevenueJPY, notes: t.notes,
  })));
}

export function exportHistoryCsv(doc) {
  const byId = Object.fromEntries(doc.countries.map((c) => [c.id, c]));
  const cols = ['date', 'country_code', 'country', 'currency', 'old_price', 'new_price', 'reason', 'notes'];
  return toCsv(cols, doc.priceHistory.map((h) => ({
    date: h.date, country_code: byId[h.countryId]?.code, country: h.countryName, currency: h.currency,
    old_price: h.oldPrice, new_price: h.newPrice, reason: h.reason, notes: h.notes,
  })));
}
