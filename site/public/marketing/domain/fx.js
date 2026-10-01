// 為替。Phase 1 は手入力のレートだけを使う（API は呼ばない）。
// 将来は rates を為替 API から埋める実装に差し替える（呼び出し側は toJPY だけを使う）。
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
