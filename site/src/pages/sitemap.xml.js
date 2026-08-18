// 言語 × ページ の全URLを列挙する sitemap。
import { languages, path } from '../i18n/index.js';
import { PAGES } from '../i18n/pages.js';
import { SITE_URL } from '../config.js';

export function GET() {
  const urls = [];
  for (const page of PAGES) {
    for (const l of languages) {
      const loc = SITE_URL + path(l.code, page);
      const alternates = languages
        .map((a) => `    <xhtml:link rel="alternate" hreflang="${a.htmlLang}" href="${SITE_URL + path(a.code, page)}"/>`)
        .join('\n');
      urls.push(
        `  <url>\n    <loc>${loc}</loc>\n${alternates}\n` +
        `    <xhtml:link rel="alternate" hreflang="x-default" href="${SITE_URL + path('en', page)}"/>\n` +
        `    <changefreq>monthly</changefreq>\n  </url>`
      );
    }
  }
  const body =
    '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">\n' +
    urls.join('\n') +
    '\n</urlset>\n';
  return new Response(body, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
}
