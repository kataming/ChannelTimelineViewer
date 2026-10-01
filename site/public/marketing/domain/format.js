// 表示用の整形。不明（null）や計算できない値は「—」にする。NaN / Infinity は絶対に出さない。
import { finite } from './num.js';

export const DASH = '—';

export function int(v) {
  const x = finite(v);
  return x === null ? DASH : Math.round(x).toLocaleString('en-US');
}

export function yen(v, { digits } = {}) {
  const x = finite(v);
  if (x === null) return DASH;
  const d = digits ?? (Math.abs(x) < 100 && x % 1 !== 0 ? 2 : 0);
  const text = Math.abs(x).toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d });
  return `${x < 0 ? '−' : ''}¥${text}`;
}

export function pct(v, digits = 2) {
  const x = finite(v);
  return x === null ? DASH : `${(x * 100).toFixed(digits)}%`;
}

export function money(v, currency) {
  const x = finite(v);
  if (x === null) return DASH;
  const text = x.toLocaleString('en-US', { maximumFractionDigits: 4 });
  return currency ? `${text} ${currency}` : text;
}

export function ratio(v, digits = 2) {
  const x = finite(v);
  return x === null ? DASH : `${x.toFixed(digits)}×`;
}

export function sign(v) {
  const x = finite(v);
  if (x === null || x === 0) return '';
  return x > 0 ? 'positive' : 'negative';
}

export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  }[c]));
}

/** 入力欄の初期値（null は空欄）。 */
export function inputValue(v) {
  const x = finite(v);
  return x === null ? '' : String(x);
}
