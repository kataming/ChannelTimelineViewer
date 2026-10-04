// 追加 28 言語（src/i18n/locales/<code>.js）の形を英語の原本と突き合わせる。
//   node scripts/check-locales.mjs          # 全言語
//   node scripts/check-locales.mjs it pt    # 指定した言語だけ
//
// 見ること:
//   - site / manual / trial / watchQueue の 4 つがそろっている
//   - キーが英語と同じ（足りない・余計なキーが無い）、配列の長さが同じ
//   - 文字列が空でない
//   - id / only / href / url のような「訳さない値」は英語と同じ
//   - 差し込み（{1} や %s）、HTML タグ、URL、Channel Timeline Viewer / YouTube / Pro が残っている
import { dict } from '../src/i18n/translations.js';
import { manuals } from '../src/i18n/manual/index.js';
import { trial } from '../src/i18n/trial.js';
import { watchQueue } from '../src/i18n/watchQueue.js';
import { extraLocales } from '../src/i18n/locales/index.js';

const SOURCES = { site: dict.en, manual: manuals.en, trial: trial.en, watchQueue: watchQueue.en };
const KEEP_AS_IS = new Set(['id', 'only', 'href', 'url', 'slug', 'code', 'icon', 'key', 'kind', 'platform']);
const NAMES = ['Channel Timeline Viewer', 'YouTube'];

const tokens = (s, re) => (s.match(re) || []).sort().join('|');
const problems = [];

function compare(code, where, en, tr) {
  if (Array.isArray(en)) {
    if (!Array.isArray(tr)) return problems.push(`${code} ${where}: 配列ではない`);
    if (tr.length !== en.length) problems.push(`${code} ${where}: 配列の長さ ${tr.length}（英語 ${en.length}）`);
    en.forEach((v, i) => compare(code, `${where}[${i}]`, v, tr[i]));
    return;
  }
  if (en && typeof en === 'object') {
    if (!tr || typeof tr !== 'object' || Array.isArray(tr)) return problems.push(`${code} ${where}: オブジェクトではない`);
    for (const k of Object.keys(en)) {
      if (!(k in tr)) problems.push(`${code} ${where}.${k}: 無い`);
      else compare(code, `${where}.${k}`, en[k], tr[k], k);
    }
    for (const k of Object.keys(tr)) if (!(k in en)) problems.push(`${code} ${where}.${k}: 英語に無いキー`);
    return;
  }
  const key = where.split('.').pop().replace(/\[\d+\]$/, '');
  if (typeof en !== 'string' || KEEP_AS_IS.has(key)) {
    if (tr !== en) problems.push(`${code} ${where}: 英語と同じ値のままにする（${JSON.stringify(en)}）`);
    return;
  }
  if (typeof tr !== 'string') return problems.push(`${code} ${where}: 文字列ではない`);
  if (en.trim() && !tr.trim()) problems.push(`${code} ${where}: 空`);
  if (tokens(en, /\{\d+\}|%\d*\$?[sd@]/g) !== tokens(tr, /\{\d+\}|%\d*\$?[sd@]/g)) problems.push(`${code} ${where}: 差し込みが違う`);
  if (tokens(en, /<\/?[a-z][^>]*>/gi) !== tokens(tr, /<\/?[a-z][^>]*>/gi)) problems.push(`${code} ${where}: HTML タグが違う`);
  for (const url of en.match(/https?:\/\/[^\s'"<)]+/g) || []) {
    if (!tr.includes(url)) problems.push(`${code} ${where}: URL が無い ${url}`);
  }
  for (const name of NAMES) {
    if (en.includes(name) && !tr.includes(name)) problems.push(`${code} ${where}: 「${name}」が無い`);
  }
}

const wanted = process.argv.slice(2);
const codes = wanted.length ? wanted : Object.keys(extraLocales);
let done = 0;
for (const code of codes) {
  const l = extraLocales[code];
  if (!l) { problems.push(`${code}: locales/${code}.js が無い`); continue; }
  for (const [section, en] of Object.entries(SOURCES)) {
    if (!l[section]) { problems.push(`${code}: ${section} が無い`); continue; }
    compare(code, section, en, l[section]);
  }
  done += 1;
}

if (problems.length) {
  console.error(problems.slice(0, 200).join('\n'));
  console.error(`NG: ${problems.length} 件`);
  process.exit(1);
}
console.log(`OK: ${done} 言語（site / manual / trial / watchQueue が英語と同じ形）`);
