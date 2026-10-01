// 数値の共通処理。null は「不明」を意味し、0 とは区別する。
// 画面に NaN / Infinity を出さないため、計算はすべてここを通す。

/** 有限の数なら数、それ以外は null。 */
export function finite(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null;
}

/** 割り算。どちらかが不明、または分母が 0 なら null（率を出せない）。 */
export function div(a, b) {
  const x = finite(a);
  const y = finite(b);
  if (x === null || y === null || y === 0) return null;
  return finite(x / y);
}

export function mul(...values) {
  let out = 1;
  for (const v of values) {
    const x = finite(v);
    if (x === null) return null;
    out *= x;
  }
  return finite(out);
}

export function sub(a, b) {
  const x = finite(a);
  const y = finite(b);
  if (x === null || y === null) return null;
  return finite(x - y);
}

/** 合計。全部不明なら null、ひとつでも分かっていればその合計。 */
export function sum(values) {
  let total = null;
  for (const v of values) {
    const x = finite(v);
    if (x === null) continue;
    total = (total ?? 0) + x;
  }
  return total;
}

/**
 * 入力欄の文字列を数にする。
 * 空欄 → null、数でない／負数 → エラー。
 */
export function parseAmount(raw, { allowNegative = false, integer = false } = {}) {
  if (raw === null || raw === undefined) return { ok: true, value: null };
  const text = String(raw).trim().replace(/,/g, '');
  if (text === '') return { ok: true, value: null };
  const value = Number(text);
  if (!Number.isFinite(value)) return { ok: false, error: '数値を入力してください' };
  if (!allowNegative && value < 0) return { ok: false, error: '負の数は入力できません' };
  if (integer && !Number.isInteger(value)) return { ok: false, error: '整数を入力してください' };
  return { ok: true, value };
}
