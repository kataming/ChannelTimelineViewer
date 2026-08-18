// dist/ の中身を機械的に点検する。Windows でも実行できるよう Node だけで完結させる。
//   node scripts/check-build.mjs
// 見るのは「7言語×3ページが揃っているか」「canonical / hreflang / title が入っているか」
// 「英語の見出しが他言語ページに漏れていないか（＝翻訳漏れ）」。
import { readFile, access } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const dist = path.join(here, '..', 'dist');

const { languages } = await import('../src/i18n/translations.js');
const { PAGES } = await import('../src/i18n/pages.js');

const problems = [];
const note = (m) => problems.push(m);

async function read(rel) {
  const file = path.join(dist, rel);
  try {
    await access(file);
  } catch {
    note(`欠落: ${rel}`);
    return null;
  }
  return readFile(file, 'utf8');
}

let checked = 0;
for (const page of PAGES) {
  for (const l of languages) {
    const rel = page ? `${l.slug}/${page}/index.html` : `${l.slug}/index.html`;
    const html = await read(rel);
    if (!html) continue;
    checked += 1;

    if (!html.includes(`<html lang="${l.htmlLang}"`)) note(`${rel}: <html lang> が ${l.htmlLang} でない`);
    if (!html.includes('rel="canonical"')) note(`${rel}: canonical が無い`);
    for (const other of languages) {
      if (!html.includes(`hreflang="${other.htmlLang}"`)) note(`${rel}: hreflang ${other.htmlLang} が無い`);
    }
    if (!html.includes('hreflang="x-default"')) note(`${rel}: hreflang x-default が無い`);
    if (!/<title>[^<]{5,}<\/title>/.test(html)) note(`${rel}: title が空`);
  }
}

// 翻訳漏れの検出: 英語版の見出しが他言語ページにそのまま出ていないか。
const { dict } = await import('../src/i18n/translations.js');
for (const l of languages) {
  if (l.code === 'en') continue;
  const html = await read(`${l.slug}/index.html`);
  if (!html) continue;
  if (html.includes(dict.en.hero.title)) note(`${l.slug}/index.html: 英語の見出しが残っている（翻訳漏れ）`);
  if (html.includes(dict.en.featuresTitle) && dict[l.code].featuresTitle !== dict.en.featuresTitle) {
    note(`${l.slug}/index.html: 英語の見出し「${dict.en.featuresTitle}」が残っている`);
  }
}

const sitemap = await read('sitemap.xml');
if (sitemap) {
  const count = (sitemap.match(/<loc>/g) || []).length;
  const expected = languages.length * PAGES.length;
  if (count !== expected) note(`sitemap.xml: URL が ${count} 件（期待 ${expected} 件）`);
}
if (!(await read('robots.txt'))) note('robots.txt が無い');
if (!(await read('404.html'))) note('404.html が無い');

if (problems.length) {
  console.error(`問題が ${problems.length} 件あります:`);
  for (const p of problems) console.error('  -', p);
  process.exit(1);
}
console.log(`OK: ${checked} ページ（${languages.length} 言語 × ${PAGES.length} ページ）+ sitemap / robots / 404`);
