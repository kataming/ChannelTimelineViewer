// 指標の計算。すべて純粋関数で、不明な値は null のまま返す（推測で埋めない）。
// 金額はすべて円（JPY）。広告費も円で入力する前提。
import { div, finite, mul, sub, sum } from './num.js';
import { toJPY } from './fx.js';

/** 手数料率の合計（Google 手数料＋その他の控除）。 */
export function deductionRate(settings) {
  const google = finite(settings?.googleFeeRate) ?? 0;
  const other = finite(settings?.otherFeeRate) ?? 0;
  return google + other;
}

/** 1購入あたりの価格（円）。 */
export function priceJPY(country, currencies) {
  return toJPY(country.price, country.currency, currencies);
}

/** 1購入あたりの手取り（円）= 価格(円) × (1 − Google手数料率 − その他控除率) */
export function netPerPurchase(country, settings, currencies) {
  return mul(priceJPY(country, currencies), 1 - deductionRate(settings));
}

/** CPI。広告費とインストールの両方があれば実績から、無ければ手入力の CPI。 */
export function cpi(metrics) {
  const fromActual = div(metrics?.adSpend, metrics?.installs);
  return fromActual ?? finite(metrics?.cpiManual);
}

/** 総売上（円）。手入力があればそれを使い、無ければ 成功件数 × 価格(円)。成功 0 件なら 0。 */
export function grossRevenue(country, currencies) {
  const m = country.metrics ?? {};
  const manual = finite(m.grossRevenueJPY);
  if (manual !== null) return manual;
  const success = finite(m.purchaseSuccess);
  if (success === 0) return 0;
  return mul(success, priceJPY(country, currencies));
}

/** 国 1 行ぶんの指標をまとめて出す。 */
export function countryStats(country, settings, currencies) {
  const m = country.metrics ?? {};
  const feeRate = finite(settings?.googleFeeRate) ?? 0;
  const otherRate = finite(settings?.otherFeeRate) ?? 0;
  const gross = grossRevenue(country, currencies);
  const googleFee = mul(gross, feeRate);
  const otherFees = mul(gross, otherRate);
  const net = sub(sub(gross, googleFee), otherFees);
  const adSpend = finite(m.adSpend);
  const netPer = netPerPurchase(country, settings, currencies);
  const cpiValue = cpi(m);
  // アプリ内広告（AdMob）の収入。AdMob の「見積もり収益」は手数料を引いた後の額なので、そのまま足す
  const adRevenue = finite(m.adRevenueJPY);
  const income = sum([net, adRevenue]);
  return {
    priceJPY: priceJPY(country, currencies),
    netPerPurchase: netPer,
    cpc: div(m.adSpend, m.clicks),
    cpi: cpiValue,
    cpiIsManual: div(m.adSpend, m.installs) === null && finite(m.cpiManual) !== null,
    installToPro: div(m.proScreenViews, m.installs),
    installToStart: div(m.purchaseStarts, m.installs),
    installToSuccess: div(m.purchaseSuccess, m.installs),
    startToSuccess: div(m.purchaseSuccess, m.purchaseStarts),
    gross,
    googleFee,
    otherFees,
    net,
    adRevenue,
    adEcpm: div(mul(adRevenue, 1000), m.admobImpressions),
    income,
    profit: sub(income, adSpend),
    roas: div(income, adSpend),
    breakEvenRate: div(cpiValue, netPer),
    flowNeedsReview: isFlowNeedsReview(m),
  };
}

/** Purchase Start はあるのに Success が 0。原因は断定しない（表示は中立的な文言だけ）。 */
export function isFlowNeedsReview(m) {
  return (finite(m?.purchaseStarts) ?? 0) > 0 && finite(m?.purchaseSuccess) === 0;
}

/** 価格テスト 1 件ぶんの指標。 */
export function testStats(test, settings, currencies) {
  const gross = finite(test.grossRevenueJPY) ?? (
    finite(test.purchaseSuccess) === 0 ? 0 : mul(test.purchaseSuccess, toJPY(test.price, test.currency, currencies)));
  const net = mul(gross, 1 - deductionRate(settings));
  return {
    startRate: div(test.purchaseStarts, test.installs),
    successRate: div(test.purchaseSuccess, test.installs),
    startToSuccess: div(test.purchaseSuccess, test.purchaseStarts),
    gross,
    net,
    profit: sub(net, test.adSpend),
  };
}

/** キャンペーン 1 件ぶんの指標。 */
export function campaignStats(c) {
  return { cpc: div(c.spend, c.clicks), cpi: div(c.spend, c.installs) };
}

/**
 * ダッシュボードの合計。全体値（設定の global）が入っていればそれを優先する
 * （国別の内訳が揃っていなくても、全体の数字は正確に持てるようにするため）。
 */
export function totals(doc) {
  const { settings, currencies, countries } = doc;
  const rows = countries.map((c) => ({ c, s: countryStats(c, settings, currencies) }));
  const g = settings.global ?? {};
  const pick = (globalValue, key) => finite(globalValue) ?? sum(rows.map(({ c }) => c.metrics?.[key]));
  const installs = pick(g.installs, 'installs');
  const purchaseStarts = pick(g.purchaseStarts, 'purchaseStarts');
  const purchaseSuccess = pick(g.purchaseSuccess, 'purchaseSuccess');
  const adSpend = sum(rows.map(({ c }) => c.metrics?.adSpend));
  const gross = sum(rows.map(({ s }) => s.gross));
  const googleFee = sum(rows.map(({ s }) => s.googleFee));
  const otherFees = sum(rows.map(({ s }) => s.otherFees));
  const net = sum(rows.map(({ s }) => s.net));
  const adRevenue = sum(rows.map(({ s }) => s.adRevenue));
  const admobImpressions = sum(rows.map(({ c }) => c.metrics?.admobImpressions));
  const income = sum([net, adRevenue]);
  return {
    installs,
    installsApprox: finite(g.installs) !== null && Boolean(g.installsApprox),
    adSpend,
    purchaseStarts,
    purchaseSuccess,
    startRate: div(purchaseStarts, installs),
    successRate: div(purchaseSuccess, installs),
    startToSuccess: div(purchaseSuccess, purchaseStarts),
    gross,
    googleFee,
    otherFees,
    net,
    adRevenue,
    admobImpressions,
    adEcpm: div(mul(adRevenue, 1000), admobImpressions),
    income,
    profit: sub(income ?? 0, adSpend),
    roas: div(income, adSpend),
    flowNeedsReview: (finite(purchaseStarts) ?? 0) > 0 && finite(purchaseSuccess) === 0,
  };
}
