// i18n ヘルパ。文言のコピーを他所に持たず、translations.js だけを見る。
import dict, { languages } from './translations.js';

export { dict, languages };

/** 全言語コード。['en','ja','zh','es','de','fr','ko'] */
export const codes = languages.map((l) => l.code);

/** 既定言語（未知のパスや / のフォールバック先）。 */
export const DEFAULT_CODE = 'en';

/** 言語定義を取り出す（不明なら既定言語）。 */
export const langOf = (code) =>
  languages.find((l) => l.code === code) || languages.find((l) => l.code === DEFAULT_CODE);

/** 辞書（未翻訳キーは英語にフォールバック）。 */
export const t = (code) => ({ ...dict[DEFAULT_CODE], ...(dict[code] || {}) });

/** ページのパス。例: path('ja', 'privacy') → '/ja/privacy/' */
export function path(code, page = '') {
  const slug = langOf(code).slug;
  return page ? `/${slug}/${page}/` : `/${slug}/`;
}
