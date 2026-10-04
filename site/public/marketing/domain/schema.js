// データの形と初期データ。
// ⚠️ 初期データには「確実に分かっている値」だけを入れる。分からない数字は null（推測で埋めない）。
export const SCHEMA_VERSION = 1;

/** CTV が対応している 35 言語（2026-10-01 時点）。コードは CTV の Localization/strings.json と同じ。 */
export const LANGUAGES = [
  ['en', 'English'], ['ar', 'Arabic'], ['bn', 'Bengali'], ['cs', 'Czech'], ['nl', 'Dutch'],
  ['fil', 'Filipino'], ['fr', 'French'], ['de', 'German'], ['el', 'Greek'], ['hi', 'Hindi'],
  ['hu', 'Hungarian'], ['id', 'Indonesian'], ['it', 'Italian'], ['ja', 'Japanese'], ['kn', 'Kannada'],
  ['ko', 'Korean'], ['ms', 'Malay'], ['mr', 'Marathi'], ['pl', 'Polish'], ['pt-BR', 'Portuguese (pt-BR)'],
  ['pa', 'Punjabi'], ['ro', 'Romanian'], ['ru', 'Russian'], ['zh-Hans', 'Simplified Chinese'],
  ['es', 'Spanish'], ['sv', 'Swedish'], ['ta', 'Tamil'], ['te', 'Telugu'], ['th', 'Thai'],
  ['zh-Hant', 'Traditional Chinese'], ['tr', 'Turkish'], ['uk', 'Ukrainian'], ['ur', 'Urdu'],
  ['vi', 'Vietnamese'], ['zu', 'Zulu'],
];
export const LANGUAGE_NAMES = Object.fromEntries(LANGUAGES);

export const PRIORITIES = ['A', 'B', 'C', 'Hold'];
export const TAGS = [
  'High YouTube Usage', 'Strong IAP Market', 'Low Ad Cost', 'High Purchasing Power',
  'Existing Installs', 'Price Test', 'Localization Ready',
];
export const PRICE_STATUSES = ['Monitoring', 'Lower Price Next', 'Keep', 'Raise Price Next', 'Paused'];
export const PLATFORMS = ['Google Ads Android', 'Google Ads iOS', 'Apple Ads'];
export const CAMPAIGN_STATUSES = ['Active', 'Paused', 'Ended', 'Draft'];
export const LOCALIZATION_ITEMS = [
  ['appUI', 'App UI'], ['appStore', 'App Store'], ['googlePlay', 'Google Play'],
  ['adHeadline', 'Ad headline'], ['adDescription', 'Ad description'], ['screenshot', 'Screenshot'],
];

/**
 * 国の指標（手入力）。金額は円。
 * adRevenueJPY / admobImpressions は AdMob の自動取得の値（アプリ内広告の収入。worker/admob-sync.js）。
 */
export const METRIC_FIELDS = [
  'adSpend', 'impressions', 'clicks', 'installs', 'cpiManual',
  'proScreenViews', 'purchaseStarts', 'purchaseSuccess', 'grossRevenueJPY',
  'adRevenueJPY', 'admobImpressions',
];
export const INTEGER_METRICS = new Set([
  'impressions', 'clicks', 'installs', 'proScreenViews', 'purchaseStarts', 'purchaseSuccess', 'admobImpressions',
]);

export function emptyMetrics() {
  return Object.fromEntries(METRIC_FIELDS.map((k) => [k, null]));
}

/** 状態は true（対応済み）/ false（未対応）/ null（未確認）の3つ。 */
export function emptyLocalization() {
  return Object.fromEntries(LOCALIZATION_ITEMS.map(([k]) => [k, null]));
}

export function newCountry(fields = {}) {
  return {
    id: fields.id ?? `c_${(fields.code || 'xx').toLowerCase()}_${Math.random().toString(36).slice(2, 8)}`,
    code: '',
    name: '',
    languages: [],
    currency: '',
    price: null,
    previousPrice: null,
    priceChangedAt: null,
    priority: null,
    tags: [],
    notes: '',
    nextCandidatePrice: null,
    candidateReason: '',
    priceStatus: null,
    ...fields,
    metrics: { ...emptyMetrics(), ...(fields.metrics ?? {}) },
    localization: { ...emptyLocalization(), ...(fields.localization ?? {}) },
  };
}

/**
 * 空のデータ（国も実績も無い状態）。公開サイトで初めて開いたとき用。
 * ⚠️ 実際の初期データ（CPI など社内の数字）はここに書かない。このファイルは公開リポジトリにも載るため、
 *    初期データはローカル版の server/seed.mjs にだけ置く。
 */
export function emptyDocument(now = new Date().toISOString()) {
  return {
    schemaVersion: SCHEMA_VERSION,
    createdAt: now,
    updatedAt: now,
    settings: {
      googleFeeRate: 0.15,
      otherFeeRate: 0,
      global: { installs: null, installsApprox: false, purchaseStarts: null, purchaseSuccess: null },
    },
    currencies: {},
    countries: [],
    priceTests: [],
    campaigns: [],
    priceHistory: [],
  };
}

/** 読み込んだデータの形を整える（欠けた項目を補う）。壊れていれば例外。 */
export function normalize(doc) {
  if (!doc || typeof doc !== 'object') throw new Error('データが空です');
  if (doc.schemaVersion !== SCHEMA_VERSION) {
    throw new Error(`対応していないデータ形式です（schemaVersion=${doc.schemaVersion}）`);
  }
  for (const key of ['countries', 'priceTests', 'campaigns', 'priceHistory']) {
    if (!Array.isArray(doc[key])) throw new Error(`${key} が配列ではありません`);
  }
  return {
    ...doc,
    settings: {
      googleFeeRate: 0.15, otherFeeRate: 0, ...doc.settings,
      global: { installs: null, installsApprox: false, purchaseStarts: null, purchaseSuccess: null, ...doc.settings?.global },
    },
    currencies: { ...doc.currencies },
    countries: doc.countries.map((c) => newCountry(c)),
  };
}
