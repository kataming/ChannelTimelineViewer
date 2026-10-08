// CTV Marketing Ops の画面。データの変更は必ず domain/model.js の操作を Store 経由で当てる。
// ⚠️ 価格を自動で決めたり、ストアの価格を変えたりする処理は持たない（判断は人が行う）。
import { ConflictError, Store, HttpRepository } from './store.js';
import * as model from './domain/model.js';
import { ValidationError } from './domain/model.js';
import { campaignStats, countryStats, testStats, totals } from './domain/calc.js';
import { hasRate } from './domain/fx.js';
import { fillDailyGaps } from './domain/admob.js';
import { finite, parseAmount } from './domain/num.js';
import { DASH, esc, inputValue, int, money, pct, ratio, sign, yen } from './domain/format.js';
import {
  CAMPAIGN_STATUSES, LANGUAGES, LANGUAGE_NAMES, LOCALIZATION_ITEMS, PLATFORMS, PRICE_STATUSES, PRIORITIES, TAGS,
} from './domain/schema.js';
import {
  exportCampaignsCsv, exportCountriesCsv, exportHistoryCsv, exportPriceTestsCsv, importCampaignsCsv,
  importCountriesCsv,
} from './domain/csv.js';
import * as versions from './domain/versions.js';

const store = new Store(new HttpRepository());
const view = document.getElementById('view');
const ui = {
  search: '', sort: 'cpi_asc', historyCountry: '', adsCountry: '', testsCountry: '',
  editTest: null, editCampaign: null, errors: {}, lastImport: null,
  // Version Performance のフィルター（空 = すべて／データの最初〜最後の日）
  vp: { start: '', end: '', platform: '', country: '', version: '', a: '', b: '' }, vpImport: null,
};

// --- 小物 ------------------------------------------------------------------------

const today = () => new Date().toISOString().slice(0, 10);
const doc = () => store.doc;
const countryById = (id) => doc().countries.find((c) => c.id === id);
const stats = (c) => countryStats(c, doc().settings, doc().currencies);
const langs = (c) => c.languages.map((l) => LANGUAGE_NAMES[l] ?? l).join(', ') || DASH;
const isActiveTest = (t) => t.start && t.start <= today() && (!t.end || t.end >= today());
const hasActiveTest = (c) => doc().priceTests.some((t) => t.countryId === c.id && isActiveTest(t));

function toast(message) {
  const el = document.getElementById('toast');
  el.textContent = message;
  el.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => el.classList.remove('show'), 2200);
}

function errorsFor(form) {
  const e = ui.errors[form];
  if (!e) return '';
  return `<div class="error" data-errors="${esc(form)}">${Object.entries(e).map(([k, v]) => `${esc(k)}: ${esc(v)}`).join('<br>')}</div>`;
}

function download(name, text, type = 'text/csv;charset=utf-8') {
  const url = URL.createObjectURL(new Blob([text], { type }));
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

const numInput = (name, value, attrs = '') => `<input class="num" name="${name}" inputmode="decimal" value="${esc(inputValue(value))}" ${attrs}>`;
const field = (label, html) => `<label>${esc(label)}${html}</label>`;
const options = (list, current, { blank = true } = {}) =>
  `${blank ? `<option value="">${DASH}</option>` : ''}${list.map((v) => {
    const [value, text] = Array.isArray(v) ? v : [v, v];
    return `<option value="${esc(value)}" ${value === current ? 'selected' : ''}>${esc(text)}</option>`;
  }).join('')}`;

function priceStatusBadge(c) {
  const parts = [];
  if (c.priceStatus) parts.push(`<span class="badge">${esc(c.priceStatus)}</span>`);
  if (hasActiveTest(c)) parts.push('<span class="badge info">Price Test</span>');
  return parts.join(' ') || DASH;
}

// --- ルーティング --------------------------------------------------------------------

function route() {
  const [name = 'dashboard', id] = location.hash.replace(/^#\/?/, '').split('/');
  return { name: name || 'dashboard', id };
}

function render() {
  if (!doc()) return;
  const r = route();
  document.querySelectorAll('.nav a').forEach((a) => {
    const active = r.name === 'country' ? 'countries' : r.name === 'admob' ? 'dashboard' : r.name;
    a.classList.toggle('active', a.dataset.route === active);
  });
  const views = {
    dashboard: renderDashboard, countries: renderCountries, country: () => renderCountry(r.id),
    tests: renderTests, ads: renderAds, localization: renderLocalization, history: renderHistory,
    settings: renderSettings, admob: renderAdmob, versions: renderVersions,
  };
  view.innerHTML = (views[r.name] ?? renderDashboard)();
  document.getElementById('save-state').textContent = `保存: ${new Date(doc().updatedAt).toLocaleString()}`;
}

// --- Google 広告の自動取得 -------------------------------------------------------------

function adsSyncLine() {
  const a = doc().adsSync;
  const configured = Boolean(doc().settings.adsSync?.customerId);
  if (!a?.lastRunAt) {
    return `<div class="muted small" data-testid="ads-sync">Google 広告の自動取得: ${configured ? 'まだ取得していません' : '未設定（<a href="#/settings">Settings</a> でお客様 ID を入力）'}</div>`;
  }
  const cls = a.status === 'ok' ? 'positive' : a.status === 'warning' ? 'warning' : 'negative';
  const label = { ok: 'OK', warning: '要確認', error: '失敗' }[a.status] ?? a.status;
  return `<div class="small" data-testid="ads-sync">Google 広告の自動取得: <span class="badge ${cls}">${label}</span>
    最終 ${esc(new Date(a.lastRunAt).toLocaleString())}${a.status !== 'error' ? `（${esc(a.from)}〜${esc(a.to)}・${int(a.countries)} 国・${int(a.campaigns)} キャンペーン）` : ''}
    ${a.message ? `<span class="${cls === 'positive' ? '' : 'negative'}">${esc(a.message)}</span>` : ''}</div>`;
}

const isAuto = (c, field) => c.metricsSource?.[field] === 'google-ads';

function playPriceSyncLine() {
  const a = doc().playPriceSync;
  if (!a?.lastRunAt) return '<div class="muted small" data-testid="play-price-sync">Google Play の価格の自動取得: まだ取得していません（毎朝 6:00）</div>';
  const cls = a.status === 'ok' ? 'positive' : 'negative';
  return `<div class="small" data-testid="play-price-sync">Google Play の価格の自動取得: <span class="badge ${cls}">${a.status === 'ok' ? 'OK' : '失敗'}</span>
    最終 ${esc(new Date(a.lastRunAt).toLocaleString())}${a.status === 'ok' ? `（登録済み ${int(a.countries)} 国に反映・変更 ${int(a.changed)} 国）` : ''}
    ${a.message ? `<span class="negative">${esc(a.message)}</span>` : ''}</div>`;
}

/** 「今すぐ取得」ボタン（為替 → Google 広告 → AdMob をまとめて実行。毎朝 6:00 の自動取得と同じ処理）。 */
function syncNowButton() {
  return `<div class="row" style="margin:6px 0"><button type="button" data-action="ads-sync" data-testid="sync-now">今すぐ取得（為替・Play 価格・Google 広告・AdMob・GA4・BigQuery）</button>
    <span class="muted small">毎朝 6:00（日本時間）にも自動で取得します。AdMob の数字は AdMob 側で約 4 時間遅れて反映されます。</span></div>`;
}

// --- AdMob（アプリ内広告の収入）の自動取得 ----------------------------------------------

function admobSyncLine() {
  const a = doc().admobSync;
  if (!a?.lastRunAt) return '<div class="muted small" data-testid="admob-sync">AdMob の自動取得: まだ取得していません（毎朝 6:00）</div>';
  const cls = a.status === 'ok' ? 'positive' : a.status === 'warning' ? 'warning' : 'negative';
  const label = { ok: 'OK', warning: '要確認', error: '失敗' }[a.status] ?? a.status;
  const platforms = Object.entries(a.byPlatform ?? {}).map(([p, v]) => `${esc(p)} ${yen(v.earningsJPY)}`).join(' / ');
  return `<div class="small" data-testid="admob-sync">AdMob の自動取得: <span class="badge ${cls}">${label}</span>
    最終 ${esc(new Date(a.lastRunAt).toLocaleString())}${a.status === 'ok' ? `（${esc(a.from)}〜${esc(a.to)}・${int(a.countries)} 国・収益 ${yen(a.earningsJPY)}${platforms ? `［${platforms}］` : ''}）` : ''}
    ${a.message ? `<span class="${cls === 'positive' ? '' : 'negative'}">${esc(a.message)}</span>` : ''}</div>`;
}

function fxSyncLine() {
  const f = doc().fxSync;
  const source = '出典: <a href="https://www.exchangerate-api.com" target="_blank" rel="noopener">Rates By Exchange Rate API</a>';
  if (!f?.lastRunAt) return `<div class="muted small" data-testid="fx-sync">為替の自動取得: まだ取得していません（毎朝 6:00）。${source}</div>`;
  const cls = f.status === 'ok' ? 'positive' : f.status === 'warning' ? 'warning' : 'negative';
  const label = { ok: 'OK', warning: '要確認', error: '失敗' }[f.status] ?? f.status;
  return `<div class="small" data-testid="fx-sync">為替の自動取得: <span class="badge ${cls}">${label}</span>
    最終 ${esc(new Date(f.lastRunAt).toLocaleString())}${f.ratesAsOf ? `（レートの基準 ${esc(new Date(f.ratesAsOf).toLocaleString())}・${int(f.currencies)} 通貨）` : ''}
    ${f.message ? `<span class="${cls === 'positive' ? '' : 'negative'}">${esc(f.message)}</span>` : ''} ${source}</div>`;
}

// --- Version Performance の自動取得（GA4 / BigQuery） --------------------------------------

function syncBadge(status) {
  const cls = status === 'ok' ? 'positive' : status === 'warning' ? 'warning' : 'negative';
  return { cls, label: `<span class="badge ${cls}">${{ ok: 'OK', warning: '要確認', error: '失敗' }[status] ?? esc(status)}</span>` };
}

function ga4SyncLine() {
  const a = doc().ga4Sync;
  if (!a?.lastRunAt) return '<div class="muted small" data-testid="ga4-sync">GA4 の自動取得: まだ取得していません（毎朝 6:00）</div>';
  const { cls, label } = syncBadge(a.status);
  return `<div class="small" data-testid="ga4-sync">GA4 の自動取得: ${label}
    最終 ${esc(new Date(a.lastRunAt).toLocaleString())}${a.status !== 'error' && a.from ? `（${esc(a.from)}〜${esc(a.to)}・${int(a.rows)} 行・${int(a.versions)} バージョン・Android のみ）` : ''}
    ${a.message ? `<span class="${cls === 'positive' ? '' : 'negative'}">${esc(a.message)}</span>` : ''}</div>`;
}

function cohortSyncLine() {
  const a = doc().cohortSync;
  if (!a?.lastRunAt) return '<div class="muted small" data-testid="cohort-sync">BigQuery のコホート: まだ取得していません（毎朝 6:00・書き出しは 2026-10-09 のデータから）</div>';
  const { cls, label } = syncBadge(a.status);
  const scanned = finite(a.bytesProcessed) !== null ? `・読んだ量 ${(a.bytesProcessed / 1e6).toFixed(1)} MB` : '';
  return `<div class="small" data-testid="cohort-sync">BigQuery のコホート: ${label}
    最終 ${esc(new Date(a.lastRunAt).toLocaleString())}${a.status === 'ok' ? `（データの最後の日 ${esc(a.asOf) || DASH}・${int(a.users)} 人・${int(a.rows)} 行${scanned}）` : ''}
    ${a.message ? `<span class="${cls === 'positive' ? '' : 'negative'}">${esc(a.message)}</span>` : ''}</div>`;
}

// --- Dashboard ---------------------------------------------------------------------

function kpi(label, value, { key = false, cls = '', href = '' } = {}) {
  const inner = `<div class="label">${esc(label)}${href ? ' <span class="kpi-more">›</span>' : ''}</div><div class="value ${cls}">${value}</div>`;
  // href があるカードは押すと詳しい画面へ（例: Ad Revenue → 日ごとの推移）
  return href
    ? `<a class="kpi kpi-link ${key ? 'key' : ''}" href="${esc(href)}" data-testid="kpi-link">${inner}</a>`
    : `<div class="kpi ${key ? 'key' : ''}">${inner}</div>`;
}

function renderDashboard() {
  const t = totals(doc());
  const rows = doc().countries.map((c) => ({ c, s: stats(c) }));
  const review = rows.filter(({ s }) => s.flowNeedsReview);
  // 広告の自動取得で国が増えるので、損益分岐は価格を登録した国だけ（広告費の大きい順）
  const priced = rows.filter(({ c }) => finite(c.price) !== null)
    .sort((a, b) => (finite(b.c.metrics.adSpend) ?? -1) - (finite(a.c.metrics.adSpend) ?? -1));
  return `
    <h1>Dashboard</h1>
    ${adsSyncLine()}
    ${admobSyncLine()}
    ${playPriceSyncLine()}
    ${fxSyncLine()}
    ${syncNowButton()}
    ${t.flowNeedsReview ? `<div class="notice" data-testid="flow-notice"><strong>Purchase flow needs review</strong> —
      Purchase Start は ${int(t.purchaseStarts)} 件ありますが Purchase Success は 0 件です。原因はここでは判断しません。</div>`
      : (finite(t.purchaseSuccess) === 0 ? `<div class="notice" data-testid="success-zero">Purchase Success は 0 件です（Purchase Start の件数は${finite(t.purchaseStarts) === null ? '未入力' : ` ${int(t.purchaseStarts)} 件`}）。</div>` : '')}
    <div class="kpis" data-testid="kpis">
      ${kpi('Purchase Success ÷ Install', pct(t.successRate, 3), { key: true, cls: finite(t.purchaseSuccess) === 0 ? 'negative' : '' })}
      ${kpi('Purchase Success ÷ Purchase Start', pct(t.startToSuccess), { key: true, cls: t.flowNeedsReview ? 'negative' : '' })}
      ${kpi('Total Installs', `${t.installsApprox ? '≈ ' : ''}${int(t.installs)}`)}
      ${kpi('Ad Spend', yen(t.adSpend))}
      ${kpi('Purchase Starts', int(t.purchaseStarts))}
      ${kpi('Purchase Success', int(t.purchaseSuccess), { cls: finite(t.purchaseSuccess) === 0 ? 'negative' : '' })}
      ${kpi('Purchase Start Rate', pct(t.startRate))}
      ${kpi('Purchase Success Rate', pct(t.successRate, 3))}
      ${kpi('Total Revenue', yen(t.gross))}
      ${kpi('Google Fee', yen(t.googleFee))}
      ${kpi('Net Revenue (Pro)', yen(t.net))}
      ${kpi('Ad Revenue (AdMob)', yen(t.adRevenue), { href: '#/admob' })}
      ${kpi('AdMob eCPM', yen(t.adEcpm))}
      ${kpi('Total Income', yen(t.income))}
      ${kpi('Profit / Loss', yen(t.profit), { cls: sign(t.profit) })}
      ${kpi('ROAS (income)', ratio(t.roas))}
    </div>
    <p class="muted small">Installs / Purchase Starts / Purchase Success は Settings の「全体の値」が入っていればそれを、無ければ国別の合計を使います。
      広告費・売上は国別の合計です。${t.installsApprox ? 'Installs は概数（≈）です。' : ''}<br>
      Total Income = Net Revenue（Pro の手取り）＋ Ad Revenue（AdMob の見積もり収益・手数料控除後）。Profit / Loss = Total Income − Ad Spend。</p>

    <h2>Purchase Start 後の離脱がある国</h2>
    ${review.length ? `<div class="table-wrap"><table><thead><tr><th class="l">Country</th><th>Installs</th><th>Purchase Starts</th><th>Purchase Success</th><th>Start→Success</th><th class="l">Status</th></tr></thead><tbody>
      ${review.map(({ c, s }) => `<tr class="clickable" data-href="#/country/${c.id}"><td class="l">${esc(c.name)}</td><td>${int(c.metrics.installs)}</td><td>${int(c.metrics.purchaseStarts)}</td>
        <td class="warning">${int(c.metrics.purchaseSuccess)}</td><td>${pct(s.startToSuccess)}</td><td class="l"><span class="badge warning">Purchase flow needs review</span></td></tr>`).join('')}
    </tbody></table></div>` : '<p class="muted">国別の Purchase Start が入力されると、ここに表示されます。</p>'}

    <h2>損益分岐（価格を登録した国）</h2>
    <div class="table-wrap"><table><thead><tr><th class="l">Country</th><th>Price</th><th>Price ¥</th><th>Net / Purchase</th><th>CPI</th><th>Break-even Purchase Rate</th><th>Install→Success</th><th class="l">Price status</th></tr></thead><tbody>
      ${priced.map(({ c, s }) => `<tr class="clickable" data-href="#/country/${c.id}"><td class="l">${esc(c.name)}</td><td>${money(c.price, c.currency)}</td>
        <td>${yen(s.priceJPY)}</td><td>${yen(s.netPerPurchase)}</td><td>${yen(s.cpi)}${s.cpiIsManual ? '<span class="muted small"> 手入力</span>' : ''}</td>
        <td>${pct(s.breakEvenRate)}</td><td class="${finite(c.metrics.purchaseSuccess) === 0 ? 'warning' : ''}">${pct(s.installToSuccess, 3)}</td>
        <td class="l">${priceStatusBadge(c)}</td></tr>`).join('')}
    </tbody></table></div>
    <p class="muted small">価格が未登録の国（${rows.length - priced.length} か国）は <a href="#/countries">Countries</a> にあります。
      ${priced.some(({ c }) => !hasRate(c.currency, doc().currencies)) ? '為替レートが未入力の通貨があると、円換算・損益分岐は「—」になります（Settings で入力）。' : ''}</p>`;
}

// --- Ad Revenue（AdMob）の日ごとの推移 -------------------------------------------------

const PLATFORM_COLORS = { IOS: 'var(--accent)', ANDROID: 'var(--positive)' };
const platformKey = (p) => String(p).toUpperCase();
const platformLabel = (k) => ({ IOS: 'iOS', ANDROID: 'Android' }[k] ?? k);
/** その日の、あるプラットフォームの収益。 */
const platformEarnings = (d, key) => Object.entries(d.byPlatform ?? {})
  .filter(([k]) => platformKey(k) === key).reduce((sum, [, v]) => sum + v.earningsJPY, 0);

/** 日ごとの収益の棒グラフ（iOS / Android の積み上げ）＋累計の折れ線。インラインの SVG。 */
function admobChart(daily) {
  const W = 760; const H = 260; const L = 64; const R = 64; const T = 16; const B = 40;
  const iw = W - L - R; const ih = H - T - B;
  const max = Math.max(...daily.map((d) => d.earningsJPY), 1);
  let run = 0;
  const cum = daily.map((d) => (run += d.earningsJPY));
  const cmax = Math.max(run, 1);
  const step = iw / daily.length;
  const bw = Math.max(2, Math.min(28, step * 0.7));
  const y = (v) => T + ih - (v / max) * ih;
  const yc = (v) => T + ih - (v / cmax) * ih;
  const platforms = [...new Set(daily.flatMap((d) => Object.keys(d.byPlatform ?? {}).map(platformKey)))];
  const bars = daily.map((d, i) => {
    const x = L + step * i + (step - bw) / 2;
    let acc = 0;
    return (platforms.length ? platforms : ['ALL']).map((pk) => {
      const v = pk === 'ALL' ? d.earningsJPY : platformEarnings(d, pk);
      const y0 = y(acc);
      acc += v;
      const y1 = y(acc);
      return v > 0 ? `<rect x="${x.toFixed(1)}" y="${y1.toFixed(1)}" width="${bw.toFixed(1)}" height="${(y0 - y1).toFixed(1)}"
        fill="${PLATFORM_COLORS[pk] ?? 'var(--muted)'}"><title>${esc(d.date)} ${esc(platformLabel(pk))} ${esc(yen(v))}</title></rect>` : '';
    }).join('');
  }).join('');
  const line = cum.map((v, i) => `${(L + step * i + step / 2).toFixed(1)},${yc(v).toFixed(1)}`).join(' ');
  const every = Math.ceil(daily.length / 10);
  const labels = daily.map((d, i) => ((i % every === 0 || i === daily.length - 1)
    ? `<text x="${(L + step * i + step / 2).toFixed(1)}" y="${H - B + 16}" text-anchor="middle">${esc(d.date.slice(5))}</text>` : '')).join('');
  const ticks = [0, 0.5, 1].map((f) => `<line x1="${L}" x2="${W - R}" y1="${y(max * f).toFixed(1)}" y2="${y(max * f).toFixed(1)}" class="grid"/>
    <text x="${L - 6}" y="${(y(max * f) + 4).toFixed(1)}" text-anchor="end">${esc(yen(max * f, { digits: 0 }))}</text>
    <text x="${W - R + 6}" y="${(yc(cmax * f) + 4).toFixed(1)}" text-anchor="start" class="cum">${esc(yen(cmax * f, { digits: 0 }))}</text>`).join('');
  const legend = [
    ...platforms.map((pk) => `<span><i style="background:${PLATFORM_COLORS[pk] ?? 'var(--muted)'}"></i>${esc(platformLabel(pk))}（日ごとの収益・左の目盛り）</span>`),
    '<span><i class="cum-swatch"></i>累計の収益（右の目盛り）</span>',
  ].join('');
  return `<div class="panel chart" data-testid="admob-chart">
    <svg viewBox="0 0 ${W} ${H}" role="img" aria-label="AdMob の日ごとの収益">
      ${ticks}${bars}
      <polyline points="${line}" class="cum-line" fill="none"/>
      ${labels}
    </svg>
    <div class="legend">${legend}</div></div>`;
}

function renderAdmob() {
  const a = doc().admobSync ?? {};
  const daily = fillDailyGaps(a.daily ?? [], a.from, a.to);
  const total = daily.reduce((sum, d) => ({
    earningsJPY: sum.earningsJPY + d.earningsJPY,
    impressions: sum.impressions + d.impressions,
    clicks: sum.clicks + d.clicks,
    adRequests: sum.adRequests + d.adRequests,
    matchedRequests: sum.matchedRequests + d.matchedRequests,
  }), { earningsJPY: 0, impressions: 0, clicks: 0, adRequests: 0, matchedRequests: 0 });
  const ecpm = (e, i) => (i > 0 ? (e / i) * 1000 : null);
  const matchRate = (d) => (d.adRequests > 0 ? d.matchedRequests / d.adRequests : null);
  const last7 = daily.slice(-7);
  const avg7 = last7.length ? last7.reduce((sum, d) => sum + d.earningsJPY, 0) / last7.length : null;
  let run = 0;
  const rows = daily.map((d) => ({ d, cum: (run += d.earningsJPY) })).reverse();
  return `
    <p class="small"><a href="#/dashboard">← Dashboard</a></p>
    <h1>Ad Revenue (AdMob) · 日ごとの推移</h1>
    ${admobSyncLine()}
    ${syncNowButton()}
    <div class="kpis" data-testid="admob-kpis">
      ${kpi('収益（期間の合計）', yen(total.earningsJPY), { key: true })}
      ${kpi('直近7日の1日平均', yen(avg7))}
      ${kpi('表示回数', int(total.impressions))}
      ${kpi('eCPM', yen(ecpm(total.earningsJPY, total.impressions)))}
      ${kpi('クリック', int(total.clicks))}
      ${kpi('マッチ率', pct(matchRate(total)))}
    </div>
    ${daily.length ? admobChart(daily) : `<div class="notice" data-testid="admob-empty">日ごとのデータはまだありません。毎朝 6:00 の自動取得（または「今すぐ取得」）のあとに表示されます。</div>`}
    ${daily.length ? `<h2>日ごとの数字（新しい順）</h2>
    <div class="table-wrap"><table data-testid="admob-daily"><thead><tr><th class="l">日付</th><th>収益</th><th>iOS</th><th>Android</th>
      <th>表示回数</th><th>eCPM</th><th>クリック</th><th>リクエスト</th><th>マッチ率</th><th>累計の収益</th></tr></thead><tbody>
      ${rows.map(({ d, cum }) => `<tr><td class="l">${esc(d.date)}</td><td>${yen(d.earningsJPY)}</td><td>${yen(platformEarnings(d, 'IOS'))}</td>
        <td>${yen(platformEarnings(d, 'ANDROID'))}</td><td>${int(d.impressions)}</td><td>${yen(ecpm(d.earningsJPY, d.impressions))}</td>
        <td>${int(d.clicks)}</td><td>${int(d.adRequests)}</td><td>${pct(matchRate(d))}</td><td>${yen(cum)}</td></tr>`).join('')}
    </tbody></table></div>` : ''}
    <p class="muted small">収益は AdMob の「見積もり収益」（円・パブリッシャーの取り分）。期間は Settings の「集計の開始日」から今日まで。
      当日の数字は AdMob 側で約 4 時間遅れて反映され、数日は見積もりのため少し変わることがあります。国別の内訳は <a href="#/countries">Countries</a> の Ad Revenue。</p>`;
}

// --- Countries ---------------------------------------------------------------------

const SORTS = {
  cpi_asc: ['CPI が安い順', (a, b) => nullLast(a.s.cpi, b.s.cpi, 1)],
  starts_desc: ['Purchase Start が多い順', (a, b) => nullLast(a.c.metrics.purchaseStarts, b.c.metrics.purchaseStarts, -1)],
  success_desc: ['Purchase Success が多い順', (a, b) => nullLast(a.c.metrics.purchaseSuccess, b.c.metrics.purchaseSuccess, -1)],
  rate_desc: ['課金率（Install→Success）が高い順', (a, b) => nullLast(a.s.installToSuccess, b.s.installToSuccess, -1)],
  loss_desc: ['赤字が大きい順', (a, b) => nullLast(a.s.profit, b.s.profit, 1)],
  profit_desc: ['利益が大きい順', (a, b) => nullLast(a.s.profit, b.s.profit, -1)],
  spend_desc: ['広告費が大きい順', (a, b) => nullLast(a.c.metrics.adSpend, b.c.metrics.adSpend, -1)],
};

/** 不明（null）は常に最後。dir=1 で昇順、-1 で降順。 */
function nullLast(x, y, dir) {
  const a = finite(x);
  const b = finite(y);
  if (a === null && b === null) return 0;
  if (a === null) return 1;
  if (b === null) return -1;
  return (a - b) * dir;
}

function renderCountries() {
  const q = ui.search.trim().toLowerCase();
  const rows = doc().countries
    .filter((c) => !q || c.name.toLowerCase().includes(q) || c.code.toLowerCase().includes(q))
    .map((c) => ({ c, s: stats(c) }))
    .sort(SORTS[ui.sort][1]);
  const th = (label, cls = '') => `<th class="${cls}">${label}</th>`;
  return `
    <h1>Countries</h1>
    <div class="row">
      <input type="search" id="country-search" placeholder="国名・国コードで検索" value="${esc(ui.search)}">
      <select id="country-sort">${Object.entries(SORTS).map(([k, [label]]) => `<option value="${k}" ${k === ui.sort ? 'selected' : ''}>${label}</option>`).join('')}</select>
      <span class="muted">${rows.length} 件</span>
    </div>
    <div class="table-wrap" data-testid="countries-table"><table>
      <thead>
        <tr><th class="group sticky-col l"></th><th class="group" colspan="8">基本・価格</th><th class="group" colspan="6">広告</th>
          <th class="group" colspan="7">課金ファネル</th><th class="group" colspan="3">1購入あたり</th><th class="group" colspan="5">収益</th></tr>
        <tr>${th('Country', 'l sticky-col')}${th('Code', 'l')}${th('Language', 'l')}${th('Currency', 'l')}${th('Current Pro Price')}${th('Previous Price')}${th('Price Changed At')}${th('Priority', 'l')}${th('Status', 'l')}
          ${th('Ad Spend')}${th('Impressions')}${th('Clicks')}${th('CPC')}${th('Installs')}${th('CPI')}
          ${th('Pro Screen Views')}${th('Purchase Starts')}${th('Purchase Success')}${th('Install→Pro')}${th('Install→Start')}${th('Install→Success')}${th('Start→Success')}
          ${th('Price ¥')}${th('Net / Purchase')}${th('Break-even Rate')}
          ${th('Gross Revenue')}${th('Google Fee')}${th('Net Revenue')}${th('Ad Revenue')}${th('Profit / Loss')}${th('ROAS')}</tr>
      </thead>
      <tbody>
        ${rows.map(({ c, s }) => `<tr class="clickable" data-href="#/country/${c.id}" data-code="${esc(c.code)}">
          <td class="l sticky-col"><a href="#/country/${c.id}">${esc(c.name)}</a></td><td class="l">${esc(c.code)}</td><td class="l">${esc(langs(c))}</td><td class="l">${esc(c.currency) || DASH}</td>
          <td>${money(c.price)}</td><td>${money(c.previousPrice)}</td><td>${esc(c.priceChangedAt) || DASH}</td><td class="l">${esc(c.priority) || DASH}</td><td class="l">${priceStatusBadge(c)}</td>
          <td>${yen(c.metrics.adSpend)}</td><td>${int(c.metrics.impressions)}</td><td>${int(c.metrics.clicks)}</td><td>${yen(s.cpc)}</td><td>${int(c.metrics.installs)}</td>
          <td>${yen(s.cpi)}${s.cpiIsManual ? '*' : ''}</td>
          <td>${int(c.metrics.proScreenViews)}</td><td>${int(c.metrics.purchaseStarts)}</td>
          <td class="${finite(c.metrics.purchaseSuccess) === 0 ? 'warning' : ''}">${int(c.metrics.purchaseSuccess)}</td>
          <td>${pct(s.installToPro)}</td><td>${pct(s.installToStart)}</td><td>${pct(s.installToSuccess, 3)}</td>
          <td class="${s.flowNeedsReview ? 'warning' : ''}">${pct(s.startToSuccess)}</td>
          <td>${yen(s.priceJPY)}</td><td>${yen(s.netPerPurchase)}</td><td>${pct(s.breakEvenRate)}</td>
          <td>${yen(s.gross)}</td><td>${yen(s.googleFee)}</td><td>${yen(s.net)}</td><td>${yen(s.adRevenue)}</td><td class="${sign(s.profit)}">${yen(s.profit)}</td><td>${ratio(s.roas)}</td>
        </tr>`).join('')}
      </tbody>
    </table></div>
    <p class="muted small">* は手入力の CPI（広告費とインストールが揃うと実績から計算）。不明な値は「—」。行をクリックすると編集画面へ。</p>

    <h2>国を追加</h2>
    <form class="panel" data-op="addCountry">
      <div class="form-grid">
        ${field('Country（国名）', '<input name="name" required>')}
        ${field('Country Code（2文字）', '<input name="code" maxlength="2" required>')}
        ${field('Currency（3文字）', '<input name="currency" maxlength="3">')}
        ${field('Current Pro Price（現地通貨）', numInput('price', null))}
      </div>
      <div class="row"><button class="primary">追加</button></div>
      ${errorsFor('addCountry')}
    </form>`;
}

// --- 国の詳細 -----------------------------------------------------------------------

function funnel(c) {
  const m = c.metrics;
  const base = finite(m.installs);
  const steps = [
    ['Install', m.installs, null],
    ['Pro Screen', m.proScreenViews, m.installs],
    ['Purchase Start', m.purchaseStarts, m.proScreenViews],
    ['Purchase Success', m.purchaseSuccess, m.purchaseStarts],
  ];
  const width = (v) => (base && finite(v) !== null ? Math.min(100, (v / base) * 100) : 0);
  const s = stats(c);
  return `
    <div class="funnel" data-testid="funnel">
      <div class="muted small">段階</div><div></div><div class="num muted small">人数</div><div class="num muted small hide-sm">÷ Install</div><div class="num muted small hide-sm">÷ 前の段階</div>
      ${steps.map(([label, v, prev]) => {
        const warn = label === 'Purchase Success' && s.flowNeedsReview;
        return `<div>${label}</div><div class="bar"><span style="width:${width(v)}%"></span></div>
          <div class="num ${warn ? 'negative' : ''}">${int(v)}</div>
          <div class="num hide-sm">${label === 'Install' ? DASH : pct(finite(v) !== null && base ? v / base : null, 3)}</div>
          <div class="num hide-sm">${prev === null ? DASH : pct(finite(prev) ? (finite(v) ?? NaN) / prev : null)}</div>`;
      }).join('')}
    </div>
    ${s.flowNeedsReview ? '<div class="notice" data-testid="country-flow-notice"><strong>Purchase flow needs review</strong> — Purchase Start 後に Success がありません（原因は断定しません）。</div>' : ''}`;
}

function renderCountry(id) {
  const c = countryById(id);
  if (!c) return '<h1>国が見つかりません</h1><p><a href="#/countries">Countries に戻る</a></p>';
  const s = stats(c);
  const m = c.metrics;
  const fee = doc().settings;
  const tests = doc().priceTests.filter((t) => t.countryId === c.id).sort((a, b) => String(a.start).localeCompare(String(b.start)));
  const camps = doc().campaigns.filter((a) => a.countryId === c.id);
  const hist = doc().priceHistory.filter((h) => h.countryId === c.id).slice().reverse();
  return `
    <div class="row"><a href="#/countries">← Countries</a></div>
    <h1>${esc(c.name)} <span class="muted">${esc(c.code)}</span> ${priceStatusBadge(c) === DASH ? '' : priceStatusBadge(c)}</h1>

    <div class="cols">
      <div>
        <h2>課金ファネル</h2>
        <div class="panel">${funnel(c)}</div>

        <h2>計算結果</h2>
        <div class="panel"><table data-testid="calc-table"><tbody>
          <tr><td class="l">Price（現地）</td><td>${money(c.price, c.currency)}${c.priceSource === 'google-play' ? ' <span class="badge info">Google Play</span>' : ''}</td></tr>
          <tr><td class="l">Price in JPY</td><td>${yen(s.priceJPY)}</td></tr>
          <tr><td class="l">Net Revenue / Purchase</td><td data-testid="net-per">${yen(s.netPerPurchase)}</td></tr>
          <tr><td class="l">CPI${s.cpiIsManual ? '（手入力）' : ''}</td><td>${yen(s.cpi)}</td></tr>
          <tr><td class="l">Break-even Purchase Rate</td><td data-testid="break-even">${pct(s.breakEvenRate)}</td></tr>
          <tr><td class="l">Install → Purchase Success（実績）</td><td>${pct(s.installToSuccess, 3)}</td></tr>
          <tr><td class="l">Gross / Google Fee / Net</td><td>${yen(s.gross)} / ${yen(s.googleFee)} / ${yen(s.net)}</td></tr>
          <tr><td class="l">Ad Revenue（AdMob）· eCPM</td><td data-testid="ad-revenue">${yen(s.adRevenue)} · ${yen(s.adEcpm)}</td></tr>
          <tr><td class="l">Profit / Loss · ROAS（Net + Ad Revenue − Ad Spend）</td><td><span class="${sign(s.profit)}">${yen(s.profit)}</span> · ${ratio(s.roas)}</td></tr>
        </tbody></table>
        <p class="formula muted">Net/Purchase = Price¥ × (1 − ${pct(fee.googleFeeRate, 1)} − ${pct(fee.otherFeeRate, 1)})<br>
          Break-even = CPI ÷ Net/Purchase</p>
        ${hasRate(c.currency, doc().currencies) ? '' : `<p class="notice">${esc(c.currency || '通貨')} の為替レートが未入力のため、円換算できません。<a href="#/settings">Settings で入力</a></p>`}
        </div>
      </div>

      <div>
        <h2>価格</h2>
        <div class="panel">
          <div>現在 <strong>${money(c.price, c.currency)}</strong> ／ 以前 ${money(c.previousPrice, c.currency)} ／ 変更日 ${esc(c.priceChangedAt) || DASH}</div>
          <form data-op="changePrice" data-id="${c.id}">
            <div class="form-grid">
              ${field('新しい価格（現地通貨）', numInput('newPrice', null))}
              ${field('変更日', `<input name="date" type="date" value="${today()}">`)}
              ${field('理由', '<input name="reason">')}
              ${field('メモ', '<input name="notes">')}
            </div>
            <div class="row"><button class="primary">価格変更を記録</button>
              <span class="muted small">記録のみ。Google Play / App Store の価格は変わりません。</span></div>
            ${errorsFor('changePrice')}
          </form>
        </div>

        <h2>次の価格候補（人が判断）</h2>
        <form class="panel" data-op="updateCountry" data-id="${c.id}">
          <div class="form-grid">
            ${field('Current Price', `<input disabled value="${esc(money(c.price, c.currency))}">`)}
            ${field('Next Candidate Price', numInput('nextCandidatePrice', c.nextCandidatePrice))}
            ${field('Status', `<select name="priceStatus">${options(PRICE_STATUSES, c.priceStatus)}</select>`)}
          </div>
          ${field('Reason', `<textarea name="candidateReason">${esc(c.candidateReason)}</textarea>`)}
          <div class="row"><button class="primary">保存</button></div>
          ${errorsFor('updateCountry')}
        </form>
      </div>
    </div>

    <h2>実績（手入力。金額は円）</h2>
    <form class="panel" data-op="updateMetrics" data-id="${c.id}">
      <div class="form-grid">
        ${field(`Ad Spend（¥）${isAuto(c, 'adSpend') ? '（Google 広告から自動）' : ''}`, numInput('adSpend', m.adSpend, isAuto(c, 'adSpend') ? 'readonly' : ''))}
        ${field(`Impressions${isAuto(c, 'impressions') ? '（Google 広告から自動）' : ''}`, numInput('impressions', m.impressions, isAuto(c, 'impressions') ? 'readonly' : ''))}
        ${field(`Clicks${isAuto(c, 'clicks') ? '（Google 広告から自動）' : ''}`, numInput('clicks', m.clicks, isAuto(c, 'clicks') ? 'readonly' : ''))}
        ${field(`Installs${isAuto(c, 'installs') ? '（Google 広告から自動）' : ''}`, numInput('installs', m.installs, isAuto(c, 'installs') ? 'readonly' : ''))}
        ${field('CPI 手入力（¥・実績が無いとき）', numInput('cpiManual', m.cpiManual))}
        ${field('Pro Screen Views', numInput('proScreenViews', m.proScreenViews))}
        ${field('Purchase Starts', numInput('purchaseStarts', m.purchaseStarts))}
        ${field('Purchase Success', numInput('purchaseSuccess', m.purchaseSuccess))}
        ${field('Gross Revenue（¥・空欄なら Success × 価格）', numInput('grossRevenueJPY', m.grossRevenueJPY))}
      </div>
      <div class="row"><button class="primary">保存</button><span class="muted small">空欄 = 不明。0 とは区別します。
        「自動」の欄は毎朝 Google 広告の値で上書きされるため、ここでは変えられません。</span></div>
      ${errorsFor('updateMetrics')}
    </form>

    <h2>基本情報・優先度</h2>
    <form class="panel" data-op="updateCountry" data-id="${c.id}" data-multi="languages,tags">
      <div class="form-grid">
        ${field('Country', `<input name="name" value="${esc(c.name)}">`)}
        ${field('Country Code', `<input name="code" maxlength="2" value="${esc(c.code)}">`)}
        ${field('Currency', `<input name="currency" maxlength="3" value="${esc(c.currency)}">`)}
        ${field('Priority', `<select name="priority">${options(PRIORITIES, c.priority)}</select>`)}
      </div>
      <div class="muted small" style="margin-top:6px">Languages（複数可）</div>
      <div class="checks">${LANGUAGES.map(([code, name]) => `<label><input type="checkbox" name="languages" value="${code}" ${c.languages.includes(code) ? 'checked' : ''}>${esc(name)}</label>`).join('')}</div>
      <div class="muted small" style="margin-top:6px">Tags</div>
      <div class="checks">${TAGS.map((t) => `<label><input type="checkbox" name="tags" value="${esc(t)}" ${c.tags.includes(t) ? 'checked' : ''}>${esc(t)}</label>`).join('')}</div>
      <div class="muted small" style="margin-top:6px">Notes</div>
      <textarea name="notes">${esc(c.notes)}</textarea>
      <div class="row"><button class="primary">保存</button></div>
      ${errorsFor('updateCountry')}
    </form>

    <h2>ローカライズ</h2>
    <div class="panel">${localizationButtons(c)}</div>

    <h2>価格テスト（${tests.length}）</h2>
    ${testsTable(tests, { showCountry: false })}
    ${testForm(c.id)}

    <h2>広告キャンペーン（${camps.length}）</h2>
    ${campaignsTable(camps, { showCountry: false })}

    <h2>価格変更履歴（${hist.length}）</h2>
    ${historyTable(hist, { showCountry: false })}`;
}

// --- ローカライズ ----------------------------------------------------------------------

function triButton(c, key) {
  const v = c.localization[key];
  const [label, cls] = v === true ? ['○', 'yes'] : v === false ? ['×', 'no'] : ['?', ''];
  return `<button class="tri ${cls}" data-action="loc" data-id="${c.id}" data-key="${key}" title="クリックで ○ → × → ? と切り替え">${label}</button>`;
}

function localizationButtons(c) {
  return `<div class="checks">${LOCALIZATION_ITEMS.map(([k, label]) => `<span>${esc(label)} ${triButton(c, k)}</span>`).join('')}</div>`;
}

function renderLocalization() {
  return `
    <h1>Localization</h1>
    <p class="muted">○ 対応済み ／ × 未対応 ／ ? 未確認。クリックで切り替え。</p>
    <div class="table-wrap" data-testid="loc-table"><table><thead><tr><th class="l sticky-col">Country</th><th class="l">Languages</th>
      ${LOCALIZATION_ITEMS.map(([, label]) => `<th>${esc(label)}</th>`).join('')}</tr></thead><tbody>
      ${doc().countries.map((c) => `<tr><td class="l sticky-col"><a href="#/country/${c.id}">${esc(c.name)}</a></td><td class="l">${esc(langs(c))}</td>
        ${LOCALIZATION_ITEMS.map(([k]) => `<td style="text-align:center">${triButton(c, k)}</td>`).join('')}</tr>`).join('')}
    </tbody></table></div>`;
}

// --- 価格テスト ----------------------------------------------------------------------

function testsTable(tests, { showCountry = true } = {}) {
  if (!tests.length) return '<p class="muted">まだありません。</p>';
  let prevByCountry = {};
  return `<div class="table-wrap"><table data-testid="tests-table"><thead><tr>${showCountry ? '<th class="l">Country</th>' : ''}<th class="l">Label</th><th>Price</th><th>Test Start</th><th>Test End</th>
    <th>Installs</th><th>Purchase Starts</th><th>Purchase Success</th><th>Start Rate</th><th>Success Rate</th><th>Start→Success</th>
    <th>Δ Success Rate</th><th>Net Revenue</th><th>Ad Spend</th><th>Profit / Loss</th><th></th></tr></thead><tbody>
    ${tests.map((t) => {
      const ts = testStats(t, doc().settings, doc().currencies);
      const prev = prevByCountry[t.countryId];
      prevByCountry = { ...prevByCountry, [t.countryId]: ts };
      const delta = prev && finite(ts.successRate) !== null && finite(prev.successRate) !== null ? ts.successRate - prev.successRate : null;
      if (ui.editTest === t.id) return `<tr><td colspan="16" class="l">${testForm(t.countryId, t)}</td></tr>`;
      return `<tr>${showCountry ? `<td class="l"><a href="#/country/${t.countryId}">${esc(countryById(t.countryId)?.name)}</a></td>` : ''}
        <td class="l">${esc(t.label) || DASH} ${isActiveTest(t) ? '<span class="badge info">running</span>' : ''}</td><td>${money(t.price, t.currency)}</td>
        <td>${esc(t.start) || DASH}</td><td>${esc(t.end) || DASH}</td><td>${int(t.installs)}</td><td>${int(t.purchaseStarts)}</td>
        <td class="${finite(t.purchaseSuccess) === 0 ? 'warning' : ''}">${int(t.purchaseSuccess)}</td><td>${pct(ts.startRate)}</td><td>${pct(ts.successRate, 3)}</td>
        <td>${pct(ts.startToSuccess)}</td><td>${delta === null ? DASH : `${delta >= 0 ? '+' : '−'}${pct(Math.abs(delta), 3)}`}</td>
        <td>${yen(ts.net)}</td><td>${yen(t.adSpend)}</td><td class="${sign(ts.profit)}">${yen(ts.profit)}</td>
        <td><button data-action="edit-test" data-id="${t.id}">編集</button></td></tr>`;
    }).join('')}
    </tbody></table></div>
    <p class="muted small">Δ Success Rate は同じ国の1つ前のテスト（開始日順）との差。</p>`;
}

function testForm(countryId, t = null) {
  const op = t ? 'updatePriceTest' : 'addPriceTest';
  return `<form class="panel" data-op="${op}" data-id="${t ? t.id : countryId}">
    <div class="form-grid">
      ${field('Label（例 Test 2）', `<input name="label" value="${esc(t?.label)}">`)}
      ${field(`Price（${esc(countryById(countryId)?.currency || '現地通貨')}）`, numInput('price', t?.price))}
      ${field('Test Start', `<input type="date" name="start" value="${esc(t?.start)}">`)}
      ${field('Test End', `<input type="date" name="end" value="${esc(t?.end)}">`)}
      ${field('Installs', numInput('installs', t?.installs))}
      ${field('Purchase Starts', numInput('purchaseStarts', t?.purchaseStarts))}
      ${field('Purchase Success', numInput('purchaseSuccess', t?.purchaseSuccess))}
      ${field('Ad Spend（¥）', numInput('adSpend', t?.adSpend))}
      ${field('Gross Revenue（¥・任意）', numInput('grossRevenueJPY', t?.grossRevenueJPY))}
      ${field('Notes', `<input name="notes" value="${esc(t?.notes)}">`)}
    </div>
    <div class="row"><button class="primary">${t ? '保存' : '価格テストを追加'}</button>${t ? '<button type="button" data-action="cancel-edit">キャンセル</button>' : ''}</div>
    ${errorsFor(op)}
  </form>`;
}

function renderTests() {
  const tests = doc().priceTests
    .filter((t) => !ui.testsCountry || t.countryId === ui.testsCountry)
    .slice()
    .sort((a, b) => (countryById(a.countryId)?.name ?? '').localeCompare(countryById(b.countryId)?.name ?? '') || String(a.start).localeCompare(String(b.start)));
  return `<h1>Price Tests</h1>
    <div class="row"><select id="tests-country"><option value="">すべての国</option>${doc().countries.map((c) => `<option value="${c.id}" ${ui.testsCountry === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div>
    ${testsTable(tests)}
    ${ui.testsCountry ? `<h2>${esc(countryById(ui.testsCountry)?.name)} にテストを追加</h2>${testForm(ui.testsCountry)}` : '<p class="muted small">国を選ぶと追加フォームが出ます。</p>'}`;
}

// --- 広告 -----------------------------------------------------------------------------

function campaignsTable(list, { showCountry = true } = {}) {
  if (!list.length) return '<p class="muted">まだありません。</p>';
  return `<div class="table-wrap"><table data-testid="campaigns-table"><thead><tr>${showCountry ? '<th class="l">Country</th>' : ''}<th class="l">Platform</th><th class="l">Campaign</th>
    <th>Daily Budget</th><th>Spend</th><th>Impressions</th><th>Clicks</th><th>CPC</th><th>Installs</th><th>CPI</th><th>Start</th><th>End</th><th class="l">Status</th><th></th></tr></thead><tbody>
    ${list.map((a) => {
      if (ui.editCampaign === a.id) return `<tr><td colspan="14" class="l">${campaignForm(a.countryId, a)}</td></tr>`;
      const cs = campaignStats(a);
      return `<tr>${showCountry ? `<td class="l"><a href="#/country/${a.countryId}">${esc(countryById(a.countryId)?.name)}</a></td>` : ''}
        <td class="l">${esc(a.platform) || DASH}</td><td class="l">${esc(a.name)} ${a.source === 'google-ads' ? '<span class="badge info">API</span>' : ''}</td><td>${yen(a.dailyBudget)}</td><td>${yen(a.spend)}</td>
        <td>${int(a.impressions)}</td><td>${int(a.clicks)}</td><td>${yen(cs.cpc)}</td><td>${int(a.installs)}</td><td>${yen(cs.cpi)}</td>
        <td>${esc(a.start) || DASH}</td><td>${esc(a.end) || DASH}</td><td class="l">${esc(a.status) || DASH}</td>
        <td>${a.source === 'google-ads' ? '' : `<button data-action="edit-campaign" data-id="${a.id}">編集</button>`}</td></tr>`;
    }).join('')}
  </tbody></table></div>`;
}

function campaignForm(countryId, a = null) {
  const op = a ? 'updateCampaign' : 'addCampaign';
  return `<form class="panel" data-op="${op}" data-id="${a ? a.id : countryId}">
    <div class="form-grid">
      ${field('Platform', `<select name="platform">${options(PLATFORMS, a?.platform)}</select>`)}
      ${field('Campaign Name', `<input name="name" value="${esc(a?.name)}">`)}
      ${field('Daily Budget（¥）', numInput('dailyBudget', a?.dailyBudget))}
      ${field('Spend（¥）', numInput('spend', a?.spend))}
      ${field('Impressions', numInput('impressions', a?.impressions))}
      ${field('Clicks', numInput('clicks', a?.clicks))}
      ${field('Installs', numInput('installs', a?.installs))}
      ${field('Start Date', `<input type="date" name="start" value="${esc(a?.start)}">`)}
      ${field('End Date', `<input type="date" name="end" value="${esc(a?.end)}">`)}
      ${field('Status', `<select name="status">${options(CAMPAIGN_STATUSES, a?.status ?? 'Active', { blank: false })}</select>`)}
    </div>
    <div class="row"><button class="primary">${a ? '保存' : 'キャンペーンを追加'}</button>${a ? '<button type="button" data-action="cancel-edit">キャンセル</button>' : ''}</div>
    ${errorsFor(op)}
  </form>`;
}

function renderAds() {
  const list = doc().campaigns.filter((a) => !ui.adsCountry || a.countryId === ui.adsCountry);
  const sumBy = (key) => list.reduce((s, a) => (finite(a[key]) === null ? s : (s ?? 0) + a[key]), null);
  return `<h1>Ads</h1>
    ${adsSyncLine()}
    <div class="row"><select id="ads-country"><option value="">すべての国</option>${doc().countries.map((c) => `<option value="${c.id}" ${ui.adsCountry === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select>
      <span class="muted">合計: Spend ${yen(sumBy('spend'))} ／ Installs ${int(sumBy('installs'))} ／ CPI ${yen(campaignStats({ spend: sumBy('spend'), installs: sumBy('installs') }).cpi)}</span></div>
    ${campaignsTable(list)}
    ${ui.adsCountry ? `<h2>${esc(countryById(ui.adsCountry)?.name)} にキャンペーンを追加</h2>${campaignForm(ui.adsCountry)}` : '<p class="muted small">国を選ぶと追加フォームが出ます。</p>'}
    <p class="muted small">「API」の行は Google 広告から毎朝自動で取り込みます（国の Ad Spend / Impressions / Clicks / Installs も自動で入ります）。
      手入力のキャンペーンは国の実績に足し込みません。</p>`;
}

// --- 履歴 ------------------------------------------------------------------------------

function historyTable(list, { showCountry = true } = {}) {
  if (!list.length) return '<p class="muted">まだありません。</p>';
  return `<div class="table-wrap"><table data-testid="history-table"><thead><tr><th class="l">Date</th>${showCountry ? '<th class="l">Country</th>' : ''}<th>Old Price</th><th>New Price</th><th class="l">Reason</th><th class="l">Notes</th></tr></thead><tbody>
    ${list.map((h) => `<tr><td class="l">${esc(h.date)}</td>${showCountry ? `<td class="l">${esc(h.countryName)}</td>` : ''}
      <td>${money(h.oldPrice, h.currency)}</td><td>${money(h.newPrice, h.currency)}</td><td class="l">${esc(h.reason) || DASH}</td>
      <td class="l"><input value="${esc(h.notes)}" data-action="annotate" data-id="${h.id}" style="min-width:220px"></td></tr>`).join('')}
  </tbody></table></div>
  <p class="muted small">履歴は削除できません。メモだけあとから書き足せます（入力欄から離れると保存）。</p>`;
}

function renderHistory() {
  const list = doc().priceHistory.filter((h) => !ui.historyCountry || h.countryId === ui.historyCountry).slice()
    .sort((a, b) => String(b.date).localeCompare(String(a.date)) || String(b.recordedAt).localeCompare(String(a.recordedAt)));
  return `<h1>Price Change Log</h1>
    <div class="row"><select id="history-country"><option value="">すべての国</option>${doc().countries.map((c) => `<option value="${c.id}" ${ui.historyCountry === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div>
    ${historyTable(list)}`;
}

// --- Version Performance（バージョン別の入口・離脱の確認） ----------------------------------
// 計算は domain/versions.js。ここは表示だけ。

/** Users の表示。日別の行を 2 日以上足した値には Σ を付ける（同じ人を重ねて数えうる）。 */
function vpUsers(cell) {
  if (!cell) return DASH;
  const mark = cell.basis === 'daily-sum' ? '<sup class="vp-mark" title="日別 Users の合計（同じ人を重ねて数えうる）">Σ</sup>' : '';
  return `${int(cell.users)}${mark}`;
}

const vpLabel = (s) => `${s.appVersion}${s.platform ? ` (${s.platform})` : ''}`;

function vpLimits() {
  return `<div class="notice" data-testid="vp-limits"><strong>データの出典と限界</strong>
    <ul class="vp-list">
      <li>出典は GA4 / Firebase Analytics の集計。<strong>毎朝 6:00 に GA4 Data API から自動取得</strong>します（入力元 <code>ga4</code>・毎回すべて入れ替え。CSV・JSON・手入力の行は残ります）。<strong>Firebase は Android 版だけ</strong>に入っていて、iOS 版の数字はありません。</li>
      <li>App Version は Android の versionName（例 1.19）。<strong>ビルド番号（versionCode）は GA4 の標準ディメンションに無い</strong>ため、Build Version は任意入力です。</li>
      <li>「バージョン別」「旧版 vs 新版」「ファネル」「Country × Version」の数字は「その期間にそのイベントを起こした人数」で、同じ利用者を追ったものではありません。</li>
      <li><strong>同じ利用者を追ったコホート（D1 / D3 / D7 Retention・7 日以内の削除率など）は「バージョン別コホート（BigQuery）」の表だけ</strong>です。BigQuery の毎日の書き出しは <strong>2026-10-09 のデータから</strong>なので、それより前に初めて開いた人は入りません。</li>
      <li><code>app_remove</code> は Android だけ。「app_remove ÷ first_open」は同じ期間のイベントの単純な比（参考値）で、<strong>アンインストール率・コホート削除率ではありません</strong>（削除した人が同じ期間に入れた人とは限らない）。本物のコホート削除率はコホートの表の「7 日以内の削除率」です。</li>
      <li>Users は GA4 では期間の中で一意です。日別の行を 2 日以上足した値（<sup>Σ</sup>）は同じ人を重ねて数えうるので、期間の合計を 1 行で書き出した行（end_date あり）があればそちらを優先します。</li>
    </ul></div>`;
}

function vpFilters(f, filters) {
  const sel = (key, list, label) => `<label class="small">${label} <select data-vp="${key}"><option value="">すべて</option>${list.map((v) => `<option value="${esc(v)}" ${ui.vp[key] === v ? 'selected' : ''}>${esc(v || '（空）')}</option>`).join('')}</select></label>`;
  return `<div class="row" data-testid="vp-filters">
    <label class="small">Start Date <input type="date" data-vp="start" value="${esc(filters.start)}"></label>
    <label class="small">End Date <input type="date" data-vp="end" value="${esc(filters.end)}"></label>
    ${sel('platform', f.platforms, 'Platform')}
    ${sel('country', f.countries, 'Country')}
    ${sel('version', f.versions.slice().reverse(), 'App Version')}
    <button type="button" data-action="vp-reset">フィルターを戻す</button>
    <span class="muted small">データの範囲 ${esc(f.minDate) || DASH} 〜 ${esc(f.maxDate) || DASH}</span></div>`;
}

function vpTable(list) {
  if (!list.length) return '<p class="muted" data-testid="vp-empty">この条件のデータはありません。</p>';
  return `<div class="table-wrap"><table data-testid="vp-table"><thead>
    <tr><th class="group l" colspan="5">バージョン</th><th class="group" colspan="${versions.VERSION_EVENTS.length}">Users（イベントを起こした人数）</th><th class="group" colspan="4">率（同じ期間の人数の比）</th></tr>
    <tr><th class="l">App Version</th><th class="l">Build Version</th><th class="l">First Seen Date</th><th class="l">Platform</th><th class="l">Country</th>
      ${versions.VERSION_EVENTS.map((e) => `<th>${esc(e)}</th>`).join('')}
      <th>first_open→channel_open</th><th>first_open→video_open</th><th>channel_open→video_open</th>
      <th title="同日イベント単純比率・参考値・コホート削除率ではない">app_remove ÷ first_open<br><span class="muted">同じ期間の単純比・参考値</span></th></tr></thead><tbody>
    ${list.map((s) => `<tr data-version="${esc(s.key)}"><td class="l"><strong>${esc(s.appVersion)}</strong></td><td class="l">${esc(s.buildVersions.join(', ')) || DASH}</td>
      <td class="l">${esc(s.firstSeen) || DASH}</td><td class="l">${esc(s.platform) || DASH}</td>
      <td class="l">${ui.vp.country ? esc(ui.vp.country) : s.hasWorldTotal ? '全世界（合計の行）' : `${int(s.countries.length)} か国の合計`}</td>
      ${versions.VERSION_EVENTS.map((e) => `<td>${vpUsers(s.events[e])}</td>`).join('')}
      <td>${pct(s.rates.firstOpenToChannelOpen, 1)}</td><td>${pct(s.rates.firstOpenToVideoOpen, 1)}</td><td>${pct(s.rates.channelOpenToVideoOpen, 1)}</td>
      <td>${pct(s.rates.removePerFirstOpen, 1)}</td></tr>`).join('')}
  </tbody></table></div>
  <p class="muted small">First Seen Date = そのバージョンのデータの最初の日（期間のフィルターは無視・Platform / Country は反映）。
    「—」は分母が 0 か、データが無い。<sup>Σ</sup> は日別 Users の合計（重複を含みうる）。</p>`;
}

function vpCompare(all, cohortList = []) {
  if (all.length < 2) return '<p class="muted">比べるには 2 つ以上のバージョンのデータが要ります。</p>';
  const pick = (key, fallback) => all.find((s) => s.key === key) ?? fallback;
  const b = pick(ui.vp.b, all[0]);
  const a = pick(ui.vp.a, all.find((s) => s.key !== b.key));
  const sel = (key, current) => `<select data-vp="${key}">${all.map((s) => `<option value="${esc(s.key)}" ${s.key === current.key ? 'selected' : ''}>${esc(vpLabel(s))}</option>`).join('')}</select>`;
  const rows = versions.compareVersionSummaries(a, b);
  return `<div class="row">旧版 ${sel('a', a)} → 新版 ${sel('b', b)}</div>
    <div class="table-wrap"><table data-testid="vp-compare"><thead><tr><th class="l">項目</th><th>${esc(vpLabel(a))}</th><th>${esc(vpLabel(b))}</th><th>差</th></tr></thead><tbody>
    ${rows.map((r) => `<tr><td class="l">${esc(r.label)}</td>
      <td>${r.kind === 'rate' ? pct(r.a, 1) : vpUsers(a.events[r.key])}</td><td>${r.kind === 'rate' ? pct(r.b, 1) : vpUsers(b.events[r.key])}</td>
      <td class="${r.key === 'removePerFirstOpen' ? '' : sign(r.kind === 'rate' ? r.diffPt : r.diff)}">${r.kind === 'rate' ? versions.formatPt(r.diffPt) : `${versions.formatDiff(r.diff)}${finite(r.relative) !== null ? `<span class="muted small">（${r.relative >= 0 ? '+' : '−'}${pct(Math.abs(r.relative), 1)}）</span>` : ''}`}</td></tr>`).join('')}
    </tbody></table></div>
    <p class="muted small">率の差は percentage point（例 22.0% → 27.5% は +5.5pt）。人数の差は絶対差（かっこ内は旧版に対する増減率）。
      期間・Platform・Country のフィルターは両方に同じく掛かります。リリース日が違うので、同じ長さの期間で比べるときは Start / End Date を合わせてください。</p>
    ${vpCohortCompare(cohortList, a, b)}`;
}

function vpFunnels(list) {
  if (!list.length) return '';
  return list.map((s) => {
    const steps = versions.versionFunnel(s);
    const base = finite(steps[0].users);
    const width = (v) => (base && finite(v) !== null ? Math.min(100, (v / base) * 100) : 0);
    return `<div class="panel" data-testid="vp-funnel"><strong>${esc(vpLabel(s))}</strong>
      <div class="funnel">
        <div class="muted small">イベント</div><div></div><div class="num muted small">Users</div><div class="num muted small hide-sm">÷ first_open</div><div class="num muted small hide-sm">÷ 前の段階</div>
        ${steps.map((st) => `<div>${esc(st.eventName)}</div><div class="bar"><span style="width:${width(st.users)}%"></span></div>
          <div class="num">${vpUsers(s.events[st.eventName])}</div><div class="num hide-sm">${pct(st.fromFirstOpen, 1)}</div><div class="num hide-sm">${pct(st.fromPrevious, 1)}</div>`).join('')}
      </div></div>`;
  }).join('');
}

function vpMatrix(rows, filters) {
  const m = versions.countryVersionMatrix(rows, filters);
  if (!m.rows.length) return '<p class="muted">国別の行（Country 列に国が入った行）があると表示されます。</p>';
  return `<div class="table-wrap"><table data-testid="vp-matrix"><thead><tr><th class="l sticky-col">Country</th>
    ${m.columns.map((k) => `<th>${esc(k.replace('|', ' / '))}<br><span class="muted">first_open · ch rate</span></th>`).join('')}</tr></thead><tbody>
    ${m.rows.map((r) => `<tr><td class="l sticky-col">${esc(r.country)}</td>${m.columns.map((k) => {
      const c = r.cells[k];
      return `<td>${c ? `${int(c.firstOpen)}${c.usersMayDuplicate ? '<sup class="vp-mark">Σ</sup>' : ''} · ${pct(c.channelRate, 1)}` : DASH}</td>`;
    }).join('')}</tr>`).join('')}
  </tbody></table></div>`;
}

function vpRawRows(rows, filters) {
  const list = rows.filter((r) => (!filters.platform || r.platform === filters.platform)
    && (!filters.country || r.country === filters.country) && (!filters.version || r.appVersion === filters.version)
    && (!filters.start || r.date >= filters.start) && (!filters.end || (r.endDate ?? r.date) <= filters.end))
    .slice().sort((x, y) => y.date.localeCompare(x.date) || versions.compareVersions(y.appVersion, x.appVersion) || x.eventName.localeCompare(y.eventName));
  const shown = list.slice(0, 300);
  if (!list.length) return '<p class="muted">まだありません。</p>';
  return `<div class="table-wrap" style="max-height:420px"><table data-testid="vp-rows"><thead><tr><th class="l">Date</th><th class="l">End Date</th><th class="l">Platform</th><th class="l">App Version</th><th class="l">Build</th>
    <th class="l">Country</th><th class="l">Event Name</th><th>Event Count</th><th>Users</th><th class="l">入力元</th><th></th></tr></thead><tbody>
    ${shown.map((r) => `<tr><td class="l">${esc(r.date)}</td><td class="l">${esc(r.endDate) || DASH}</td><td class="l">${esc(r.platform) || DASH}</td><td class="l">${esc(r.appVersion)}</td>
      <td class="l">${esc(r.buildVersion) || DASH}</td><td class="l">${esc(r.country) || '全世界'}</td><td class="l">${esc(r.eventName)}</td>
      <td>${int(r.eventCount)}</td><td>${int(r.users)}</td><td class="l">${esc(r.source)}</td>
      <td><button type="button" data-action="vm-delete" data-key="${esc(versions.versionMetricKey(r))}">削除</button></td></tr>`).join('')}
  </tbody></table></div>
  <p class="muted small">${list.length > shown.length ? `新しい順に ${shown.length} 行だけ表示（全 ${int(list.length)} 行）。` : `${int(list.length)} 行。`}フィルターが掛かります。</p>`;
}

/** コホートの率の表示。分母が 0 / 不明なら「—」、Retention で N 日経っていなければ「測定前」。 */
function cohortRate(cell, { retention = false } = {}) {
  if (retention && !cell?.measured) return `${DASH}<br><span class="muted small">測定前</span>`;
  return `${pct(cell?.rate, 1)}<br><span class="muted small">${int(retention ? cell?.returned : cell?.count)} / ${int(cell?.base)}</span>`;
}

function vpCohorts(cohorts, list) {
  if (!cohorts.length) {
    return '<p class="muted" data-testid="vp-cohort-empty">BigQuery の書き出しは 2026-10-09 から。データがたまると表示されます（毎朝 6:00 に取得）。</p>';
  }
  if (!list.length) return '<p class="muted" data-testid="vp-cohort-empty">この条件のコホートはありません。</p>';
  const mark = (s) => (s.partial7 ? '<sup class="vp-mark" title="7 日経っていないコホートを含む（途中の値）">途中</sup>' : '');
  return `<div class="table-wrap"><table data-testid="vp-cohorts"><thead>
    <tr><th class="l">App Version</th><th class="l">Platform</th><th class="l">コホート日</th><th>コホート人数</th>
      <th>D1 Retention</th><th>D3 Retention</th><th>D7 Retention</th>
      <th>7 日以内の削除率<br><span class="muted">コホート（本物）</span></th><th>7 日以内の channel_open 率</th><th>7 日以内の video_open 率</th></tr></thead><tbody>
    ${list.map((s) => `<tr data-cohort="${esc(s.key)}"><td class="l"><strong>${esc(s.appVersion)}</strong></td><td class="l">${esc(s.platform) || DASH}</td>
      <td class="l">${esc(s.firstCohort) || DASH}〜${esc(s.lastCohort) || DASH}<br><span class="muted small">${int(s.cohorts)} 日分</span></td><td>${int(s.users)}</td>
      <td>${cohortRate(s.d1, { retention: true })}</td><td>${cohortRate(s.d3, { retention: true })}</td><td>${cohortRate(s.d7, { retention: true })}</td>
      <td>${cohortRate(s.removed7)}${mark(s)}</td><td>${cohortRate(s.channelOpen7)}${mark(s)}</td><td>${cohortRate(s.videoOpen7)}${mark(s)}</td></tr>`).join('')}
  </tbody></table></div>
  <p class="muted small">コホート = その日に初めてアプリを開いた（first_open）人。バージョン・国はそのときの値。
    D1 / D3 / D7 = ちょうど 1 / 3 / 7 日目に開いた（user_engagement か session_start）人の割合で、N 日経ったコホートだけで計算します（まだなら「測定前」）。
    7 日以内 = コホート日〜7 日目。<sup>途中</sup> は 7 日経っていないコホートを含む途中の値。
    期間のフィルターは「コホート日」に掛かります（空 = すべて）。Platform / Country / App Version も反映。</p>`;
}

function vpCohortCompare(cohortList, a, b) {
  if (!cohortList.length || !a || !b) return '';
  const ca = cohortList.find((s) => s.key === a.key) ?? null;
  const cb = cohortList.find((s) => s.key === b.key) ?? null;
  if (!ca && !cb) return '<p class="muted small" data-testid="vp-cohort-compare">この 2 つのバージョンのコホートはまだありません（BigQuery の書き出しは 2026-10-09 から）。</p>';
  const rows = versions.compareCohortSummaries(ca, cb);
  // 削除率は下がるほど良いので、差の色を逆にする
  const color = (r) => (r.kind === 'count' ? sign(r.diff) : sign(r.key === 'removed7' && r.diffPt !== null ? -r.diffPt : r.diffPt));
  return `<h3>コホート（BigQuery・同じ利用者を追跡）</h3>
    <div class="table-wrap"><table data-testid="vp-cohort-compare"><thead><tr><th class="l">項目</th><th>${esc(vpLabel(a))}</th><th>${esc(vpLabel(b))}</th><th>差</th></tr></thead><tbody>
    ${rows.map((r) => `<tr><td class="l">${esc(r.label)}</td>
      <td>${r.kind === 'rate' ? pct(r.a, 1) : int(r.a)}</td><td>${r.kind === 'rate' ? pct(r.b, 1) : int(r.b)}</td>
      <td class="${color(r)}">${r.kind === 'rate' ? versions.formatPt(r.diffPt) : versions.formatDiff(r.diff)}</td></tr>`).join('')}
    </tbody></table></div>
    <p class="muted small">「—」はそのバージョンのコホートが無いか、まだ測れない（N 日経っていない）。削除率は下がるほど良いので、差の色を逆にしています。</p>`;
}

function renderVersions() {
  const rows = doc().versionMetrics ?? [];
  const cohorts = doc().versionCohorts ?? [];
  const f = versions.versionMetricFacets(rows);
  // フィルターの選択肢はコホートの値も合わせる（コホートにしか無い国・バージョンも選べるように）
  const cf = versions.cohortFacets(cohorts);
  f.platforms = [...new Set([...f.platforms, ...cf.platforms])].sort();
  f.countries = [...new Set([...f.countries, ...cf.countries])].sort();
  f.versions = [...new Set([...f.versions, ...cf.versions])].sort(versions.compareVersions);
  const filters = {
    start: ui.vp.start || f.minDate || '', end: ui.vp.end || f.maxDate || '',
    platform: ui.vp.platform, country: ui.vp.country, version: ui.vp.version,
  };
  const list = versions.summarizeVersions(rows, filters);
  const forCompare = ui.vp.version ? versions.summarizeVersions(rows, { ...filters, version: '' }) : list;
  // コホートの期間は「コホート日」に掛ける。指定が無ければすべて（イベントのデータの範囲には合わせない）
  const cohortFilters = { start: ui.vp.start, end: ui.vp.end, platform: ui.vp.platform, country: ui.vp.country };
  const cohortList = versions.summarizeCohorts(cohorts, { ...cohortFilters, version: ui.vp.version });
  const cohortAll = ui.vp.version ? versions.summarizeCohorts(cohorts, cohortFilters) : cohortList;
  return `<h1>Version Performance</h1>
    <div class="panel" data-testid="vp-sync">
      ${ga4SyncLine()}
      ${cohortSyncLine()}
      ${syncNowButton()}
    </div>
    ${vpLimits()}
    ${rows.length || cohorts.length ? vpFilters(f, filters) : ''}
    <h2>バージョン別</h2>
    ${rows.length ? vpTable(list) : '<p class="muted" data-testid="vp-empty">まだデータがありません。下の「取り込み」から GA4 の CSV / JSON を入れるか、1 行ずつ追加してください。</p>'}

    <h2>バージョン別コホート（BigQuery・同じ利用者を追跡）</h2>
    ${vpCohorts(cohorts, cohortList)}

    <h2>旧版 vs 新版</h2>
    ${rows.length ? vpCompare(forCompare, cohortAll) : '<p class="muted">データが入ると表示されます。</p>'}

    <h2>ファネル（first_open → channel_tutorial_view → channel_open → video_open）</h2>
    ${vpFunnels(list) || '<p class="muted">データが入ると表示されます。</p>'}
    <p class="muted small">各段の人数は同じ期間にそのイベントを起こした人数です。同じ人が順に進んだとは限りません（前段より多くなることもあります）。</p>

    <h2>Country × Version</h2>
    ${vpMatrix(rows, { ...filters, version: ui.vp.version })}

    <h2>取り込み・書き出し</h2>
    <div class="panel">
      <div class="row"><strong>CSV 取り込み</strong><input type="file" accept=".csv,text/csv" data-action="vm-import" data-kind="csv">
        <strong>JSON 取り込み</strong><input type="file" accept=".json,application/json" data-action="vm-import" data-kind="json">
        <button type="button" data-action="vm-export">CSV 書き出し</button></div>
      ${ui.vpImport ? `<div class="small" data-testid="vp-import-result">${esc(ui.vpImport)}</div>` : ''}
      ${errorsFor('vmImport')}${errorsFor('vmDelete')}
      <p class="muted small">CSV の列: <code>${versions.VERSION_COLUMNS.join(',')}</code>（<code>end_date</code> は期間の合計の行だけ・<code>buildVersion</code> は任意）。
        GA4 の書き出しの列名（Date / App version / Country ID / Event name / Event count / Total users）と日付 20261007、先頭の # の行もそのまま読めます。
        同じ日付・Platform・App Version・Build・Country・Event Name の行は上書き。Country が空の行は「全世界の合計」。
        JSON は行の配列、<code>{ "versionMetrics": [...] }</code>、GA4 Data API の runReport の応答のどれでも可。</p>
    </div>

    <h2>1 行追加（手入力）</h2>
    <form class="panel" data-op="addVersionMetric">
      <div class="form-grid">
        ${field('Date', `<input type="date" name="date" value="${today()}">`)}
        ${field('End Date（期間の合計の行だけ）', '<input type="date" name="endDate">')}
        ${field('Platform', `<select name="platform">${options(versions.VERSION_PLATFORMS, 'Android', { blank: false })}</select>`)}
        ${field('App Version（例 1.19）', '<input name="appVersion">')}
        ${field('Build Version（任意）', '<input name="buildVersion">')}
        ${field('Country（2 文字・空 = 全世界）', '<input name="country" maxlength="40">')}
        ${field('Event Name', `<input name="eventName" list="vp-events"><datalist id="vp-events">${versions.VERSION_EVENTS.map((e) => `<option value="${e}">`).join('')}</datalist>`)}
        ${field('Event Count', numInput('eventCount', null))}
        ${field('Users', numInput('users', null))}
      </div>
      <div class="row"><button class="primary">追加（同じキーは上書き）</button></div>
      ${errorsFor('addVersionMetric')}
    </form>

    <h2>取り込んだ行</h2>
    ${vpRawRows(rows, filters)}`;
}

// --- Settings -------------------------------------------------------------------------

function renderSettings() {
  const { settings, currencies } = doc();
  const g = settings.global;
  const codes = [...new Set([...Object.keys(currencies), ...doc().countries.map((c) => c.currency).filter(Boolean)])].filter((c) => c !== 'JPY').sort();
  return `<h1>Settings</h1>
    <h2>手数料</h2>
    <form class="panel" data-op="setFees">
      <div class="form-grid">
        ${field('Google Play Fee（%）', numInput('googleFeePercent', +(settings.googleFeeRate * 100).toFixed(4)))}
        ${field('その他の控除（%・税／為替差など）', numInput('otherFeePercent', +(settings.otherFeeRate * 100).toFixed(4)))}
      </div>
      <div class="row"><button class="primary">保存</button><span class="muted small">Net = Gross − Google Fee − その他控除。既定は Google 15%、その他 0%。</span></div>
      ${errorsFor('setFees')}
    </form>

    <h2>全体の値（ダッシュボード用）</h2>
    <form class="panel" data-op="setGlobal">
      <div class="form-grid">
        ${field('Total Installs', numInput('installs', g.installs))}
        ${field('Purchase Starts', numInput('purchaseStarts', g.purchaseStarts))}
        ${field('Purchase Success', numInput('purchaseSuccess', g.purchaseSuccess))}
      </div>
      <div class="checks"><label><input type="checkbox" name="installsApprox" ${g.installsApprox ? 'checked' : ''}>Installs は概数</label></div>
      <div class="row"><button class="primary">保存</button><span class="muted small">空欄にすると国別の合計を使います。</span></div>
      ${errorsFor('setGlobal')}
    </form>

    <h2>Google 広告の自動取得</h2>
    <form class="panel" data-op="setAdsSettings">
      ${adsSyncLine()}
      <div class="form-grid" style="margin-top:6px">
        ${field('お客様 ID（Google 広告の右上・123-456-7890）', `<input name="customerId" value="${esc(settings.adsSync?.customerId ?? '')}">`)}
        ${field('MCC 経由ならその ID（任意）', `<input name="loginCustomerId" value="${esc(settings.adsSync?.loginCustomerId ?? '')}">`)}
        ${field('集計の開始日', `<input type="date" name="startDate" value="${esc(settings.adsSync?.startDate ?? '2025-01-01')}">`)}
      </div>
      <div class="row"><button class="primary">保存</button>
        <button type="button" data-action="ads-sync">今すぐ取得（為替・Play 価格・Google 広告・AdMob・GA4・BigQuery）</button>
        <span class="muted small">毎朝 6:00（日本時間）に為替 → 広告の順で自動取得します。広告は開始日〜当日の合計を取り込みます。</span></div>
      ${errorsFor('setAdsSettings')}
    </form>

    <h2>AdMob（アプリ内広告の収入）の自動取得</h2>
    <form class="panel" data-op="setAdmobSettings">
      ${admobSyncLine()}
      <div class="form-grid" style="margin-top:6px">
        ${field('パブリッシャー ID（任意・pub-…）', `<input name="publisherId" value="${esc(settings.admobSync?.publisherId ?? '')}" placeholder="空なら見られる最初のアカウント">`)}
        ${field('集計の開始日', `<input type="date" name="startDate" value="${esc(settings.admobSync?.startDate ?? '2026-10-01')}">`)}
      </div>
      <div class="row"><button class="primary">保存</button>
        <button type="button" data-action="ads-sync">今すぐ取得（為替・Play 価格・Google 広告・AdMob・GA4・BigQuery）</button>
        <span class="muted small">毎朝 6:00（日本時間）に、開始日〜当日の国別の見積もり収益（円）と表示回数を取り込みます。</span></div>
      ${errorsFor('setAdmobSettings')}
    </form>

    <h2>Version Performance の自動取得（GA4 / BigQuery）</h2>
    <form class="panel" data-op="setGa4Settings">
      ${ga4SyncLine()}
      ${cohortSyncLine()}
      <div class="form-grid" style="margin-top:6px">
        ${field('集計の開始日', `<input type="date" name="startDate" value="${esc(settings.ga4Sync?.startDate ?? '2026-09-01')}">`)}
      </div>
      <div class="row"><button class="primary">保存</button>
        <button type="button" data-action="ads-sync">今すぐ取得（為替・Play 価格・Google 広告・AdMob・GA4・BigQuery）</button>
        <span class="muted small">毎朝 6:00（日本時間）に、GA4 プロパティ 553416503（Android）の開始日〜当日のバージョン別イベントと、
          BigQuery の書き出し（2026-10-09 以降）のバージョン別コホートを取り込みます。開始日を早くすると行が増え、画面が重くなります。</span></div>
      ${errorsFor('setGa4Settings')}
    </form>

    <h2>為替</h2>
    <div class="panel">
      ${fxSyncLine()}
      <table data-testid="fx-table"><thead><tr><th class="l">Currency</th><th>1 単位 = 円</th><th class="l">Updated At</th><th></th></tr></thead><tbody>
        ${codes.map((code) => `<tr><td class="l">${esc(code)}</td><td colspan="3"><form data-op="setRate" data-id="${esc(code)}" class="row" style="justify-content:flex-end;margin:0">
          ${numInput('rate', currencies[code]?.rateToJPY)}<input type="date" name="updatedAt" value="${esc(currencies[code]?.updatedAt ?? today())}"><button>保存</button></form></td></tr>`).join('')}
      </tbody></table>
      <form data-op="setRate" class="row"><input name="currency" placeholder="通貨（例 THB）" maxlength="3" style="width:110px">${numInput('rate', null, 'placeholder="円"')}<input type="date" name="updatedAt" value="${today()}"><button>通貨を追加</button></form>
      ${errorsFor('setRate')}
      <p class="muted small">毎朝 6:00 に自動で入れ直します（手で入れた値も上書きされます）。取得元に無い通貨だけは手入力のまま残ります。
        通貨は各国の Currency に入れた分と、ここで追加した分が対象です。</p>
    </div>

    <h2>損益分岐の試算</h2>
    <form class="panel" id="calc-form">
      <div class="form-grid">
        ${field('CPI（¥）', '<input class="num" name="cpi" inputmode="decimal">')}
        ${field('価格（現地通貨）', '<input class="num" name="price" inputmode="decimal">')}
        ${field('1 単位 = 円', '<input class="num" name="rate" inputmode="decimal" value="1">')}
      </div>
      <div id="calc-out" class="formula" data-testid="calc-out"></div>
    </form>

    <h2>データ</h2>
    <div class="panel">
      <div class="row"><strong>CSV 書き出し</strong>
        <button data-action="export" data-kind="countries">Countries</button><button data-action="export" data-kind="campaigns">Ads</button>
        <button data-action="export" data-kind="tests">Price Tests</button><button data-action="export" data-kind="history">History</button></div>
      <div class="row"><strong>CSV 取り込み</strong>
        <label>Countries <input type="file" accept=".csv,text/csv" data-action="import" data-kind="countries"></label>
        <label>Ads <input type="file" accept=".csv,text/csv" data-action="import" data-kind="campaigns"></label></div>
      ${ui.lastImport ? `<div class="small" data-testid="import-result">${esc(ui.lastImport)}</div>` : ''}
      <div class="row"><strong>JSON</strong><button data-action="backup">バックアップを保存</button>
        <label>復元 <input type="file" accept=".json,application/json" data-action="restore"></label></div>
      <p class="muted small">CSV の形式は README を参照（空のセルは「変更しない」）。復元すると今のデータは置き換わります（直前の版はサーバー側の data/backups に残ります）。</p>
    </div>`;
}

function updateCalc(form) {
  const out = form.querySelector('#calc-out');
  const read = (n) => parseAmount(form.elements[n].value).value;
  const netPer = finite(read('price')) !== null && finite(read('rate')) !== null
    ? read('price') * read('rate') * (1 - doc().settings.googleFeeRate - doc().settings.otherFeeRate) : null;
  const be = finite(read('cpi')) !== null && finite(netPer) && netPer > 0 ? read('cpi') / netPer : null;
  out.textContent = `手取り/購入 ${yen(netPer)} → 損益分岐課金率 ${pct(be)}`;
}

// --- イベント --------------------------------------------------------------------------

function formObject(form) {
  const data = {};
  const multi = (form.dataset.multi ?? '').split(',').filter(Boolean);
  for (const el of form.elements) {
    if (!el.name || el.disabled) continue;
    if (multi.includes(el.name)) continue;
    if (el.type === 'checkbox') data[el.name] = el.checked;
    else data[el.name] = el.value;
  }
  for (const name of multi) {
    data[name] = [...form.querySelectorAll(`input[type=checkbox][name="${name}"]:checked`)].map((el) => el.value);
  }
  return data;
}

const OPS = {
  addCountry: (d) => (doc_) => model.addCountry(doc_, d).doc,
  updateCountry: (d, id) => (doc_) => model.updateCountry(doc_, id, d),
  updateMetrics: (d, id) => (doc_) => model.updateMetrics(doc_, id, d),
  changePrice: (d, id) => (doc_) => model.changePrice(doc_, id, d),
  addPriceTest: (d, id) => (doc_) => model.addPriceTest(doc_, id, d).doc,
  updatePriceTest: (d, id) => (doc_) => model.updatePriceTest(doc_, id, d),
  addCampaign: (d, id) => (doc_) => model.addCampaign(doc_, id, d).doc,
  updateCampaign: (d, id) => (doc_) => model.updateCampaign(doc_, id, d),
  setFees: (d) => (doc_) => model.setFees(doc_, d),
  setGlobal: (d) => (doc_) => model.setGlobal(doc_, d),
  setRate: (d, id) => (doc_) => model.setRate(doc_, id ?? d.currency, d.rate, d.updatedAt),
  setAdsSettings: (d) => (doc_) => model.setAdsSettings(doc_, d),
  setAdmobSettings: (d) => (doc_) => model.setAdmobSettings(doc_, d),
  setGa4Settings: (d) => (doc_) => model.setGa4Settings(doc_, d),
  addVersionMetric: (d) => (doc_) => versions.addVersionMetric(doc_, d),
};

async function run(name, operation, message = '保存しました') {
  try {
    await store.apply(operation);
    delete ui.errors[name];
    toast(message);
    return true;
  } catch (e) {
    ui.errors[name] = e instanceof ValidationError ? e.errors : { 保存: e.message };
    if (e instanceof ConflictError) toast(`${e.message}。ページを再読み込みしてください`);
    render();
    return false;
  }
}

view.addEventListener('submit', async (event) => {
  const form = event.target;
  if (!form.dataset.op) return;
  event.preventDefault();
  const name = form.dataset.op;
  const ok = await run(name, OPS[name](formObject(form), form.dataset.id));
  if (ok && (name === 'updatePriceTest' || name === 'updateCampaign')) { ui.editTest = null; ui.editCampaign = null; render(); }
});

view.addEventListener('input', (event) => {
  if (event.target.id === 'country-search') {
    ui.search = event.target.value;
    const pos = event.target.selectionStart;
    render();
    const el = document.getElementById('country-search');
    el.focus();
    el.setSelectionRange(pos, pos);
  }
  if (event.target.closest('#calc-form')) updateCalc(event.target.closest('#calc-form'));
});

view.addEventListener('change', async (event) => {
  const el = event.target;
  if (el.id === 'country-sort') { ui.sort = el.value; render(); }
  if (el.id === 'history-country') { ui.historyCountry = el.value; render(); }
  if (el.id === 'ads-country') { ui.adsCountry = el.value; render(); }
  if (el.id === 'tests-country') { ui.testsCountry = el.value; render(); }
  if (el.dataset.vp) { ui.vp[el.dataset.vp] = el.value; render(); }
  if (el.dataset.action === 'vm-import' && el.files[0]) {
    const text = await el.files[0].text();
    const fn = el.dataset.kind === 'json' ? versions.importVersionMetricsJson : versions.importVersionMetricsCsv;
    const result = fn(doc(), text);
    ui.vpImport = `追加 ${result.added} ／ 上書き ${result.updated}${result.errors.length ? ` ／ エラー ${result.errors.length} 行: ${result.errors.slice(0, 10).map((e) => `${e.line}行目 ${e.message}`).join('; ')}${result.errors.length > 10 ? ' …' : ''}` : ''}`;
    if (result.added || result.updated) await run('vmImport', () => result.doc, '取り込みました');
    render();
  }
  if (el.dataset.action === 'annotate') await run('annotate', (d) => model.annotateHistory(d, el.dataset.id, el.value), 'メモを保存しました');
  if (el.dataset.action === 'import' && el.files[0]) {
    const text = await el.files[0].text();
    const fn = el.dataset.kind === 'countries' ? importCountriesCsv : importCampaignsCsv;
    const result = fn(doc(), text, { date: today() });
    ui.lastImport = `追加 ${result.added} ／ 更新 ${result.updated}${result.errors.length ? ` ／ エラー ${result.errors.length} 行: ${result.errors.map((e) => `${e.line}行目 ${e.message}`).join('; ')}` : ''}`;
    await run('import', () => result.doc, '取り込みました');
    render();
  }
  if (el.dataset.action === 'restore' && el.files[0]) {
    try {
      const parsed = JSON.parse(await el.files[0].text());
      if (!window.confirm('今のデータをこのバックアップで置き換えます。よろしいですか？')) return;
      await store.replace(parsed);
      toast('復元しました');
    } catch (e) {
      ui.errors.restore = { 復元: e.message };
      toast(`復元できませんでした: ${e.message}`);
    }
  }
});

view.addEventListener('click', async (event) => {
  const el = event.target.closest('[data-action], tr[data-href]');
  if (!el) return;
  if (el.matches('tr[data-href]')) {
    if (event.target.closest('a, button, input')) return;
    location.hash = el.dataset.href;
    return;
  }
  const action = el.dataset.action;
  if (action === 'loc') {
    const c = countryById(el.dataset.id);
    const cur = c.localization[el.dataset.key];
    const nextValue = cur === true ? false : cur === false ? null : true;
    await run('loc', (d) => model.setLocalization(d, c.id, el.dataset.key, nextValue));
  }
  if (action === 'edit-test') { ui.editTest = el.dataset.id; render(); }
  if (action === 'edit-campaign') { ui.editCampaign = el.dataset.id; render(); }
  if (action === 'cancel-edit') { ui.editTest = null; ui.editCampaign = null; render(); }
  if (action === 'export') {
    const fns = { countries: exportCountriesCsv, campaigns: exportCampaignsCsv, tests: exportPriceTestsCsv, history: exportHistoryCsv };
    download(`ctv-${el.dataset.kind}-${today()}.csv`, fns[el.dataset.kind](doc()));
  }
  if (action === 'ads-sync') {
    el.disabled = true;
    el.textContent = '取得中…';
    try {
      const res = await fetch('api/ads-sync', { method: 'POST', credentials: 'same-origin' });
      const body = await res.json().catch(() => ({}));
      await store.init();
      const ok = res.ok && body.status !== 'error';
      toast(ok ? '為替・Play 価格・Google 広告・AdMob・GA4・BigQuery を取り込みました' : `一部取得できませんでした: ${body.message || body.error || res.status}`);
    } catch (e) {
      toast(`取得できませんでした: ${e.message}`);
    }
    return;
  }
  if (action === 'vm-export') download(`ctv-version-metrics-${today()}.csv`, versions.exportVersionMetricsCsv(doc()));
  if (action === 'vm-delete') await run('vmDelete', (d) => versions.deleteVersionMetric(d, el.dataset.key), '削除しました');
  if (action === 'vp-reset') { ui.vp = { start: '', end: '', platform: '', country: '', version: '', a: '', b: '' }; render(); }
  if (action === 'backup') {
    download(`ctv-marketing-ops-backup-${today()}.json`, `${JSON.stringify(doc(), null, 2)}\n`, 'application/json');
  }
});

window.addEventListener('hashchange', () => { ui.editTest = null; ui.editCampaign = null; render(); view.focus(); });
// 公式サイト版（/marketing/）のときだけログアウトを出す（ローカル版にはログインが無い）
if (location.pathname.startsWith('/marketing')) {
  const foot = document.getElementById('save-state');
  foot.insertAdjacentHTML('afterend', '<a class="nav-logout" href="api/logout">ログアウト</a>');
}
store.subscribe(render);
store.init().catch((e) => {
  view.innerHTML = `<h1>読み込めませんでした</h1><p class="error">${esc(e.message)}</p><p>サーバー（npm start）が動いているか確認してください。</p>`;
});
