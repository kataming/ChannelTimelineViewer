// 為替。レートは doc.currencies（1 単位 = 何円）。公式サイト版は毎朝 6 時に Worker が
// ExchangeRate-API から入れ直す（worker/fx-sync.js）。計算側は toJPY だけを使う。
import { finite, mul } from './num.js';

/**
 * ローカル通貨の金額を円にする。
 * @param {number|null} amount
 * @param {string} currency 例 'BDT'
 * @param {Record<string, {rateToJPY: number|null}>} currencies
 * @returns {number|null} レート未入力なら null
 */
export function toJPY(amount, currency, currencies) {
  if (finite(amount) === null || !currency) return null;
  if (currency === 'JPY') return amount;
  const rate = finite(currencies?.[currency]?.rateToJPY);
  if (rate === null || rate <= 0) return null;
  return mul(amount, rate);
}

export function hasRate(currency, currencies) {
  if (currency === 'JPY') return true;
  const rate = finite(currencies?.[currency]?.rateToJPY);
  return rate !== null && rate > 0;
}
