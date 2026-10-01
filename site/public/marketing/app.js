// CTV Marketing Ops の画面。データの変更は必ず domain/model.js の操作を Store 経由で当てる。
// ⚠️ 価格を自動で決めたり、ストアの価格を変えたりする処理は持たない（判断は人が行う）。
import { ConflictError, Store, HttpRepository } from './store.js';
import * as model from './domain/model.js';
import { ValidationError } from './domain/model.js';
import { campaignStats, countryStats, testStats, totals } from './domain/calc.js';
import { hasRate } from './domain/fx.js';
import { finite, parseAmount } from './domain/num.js';
import { DASH, esc, inputValue, int, money, pct, ratio, sign, yen } from './domain/format.js';
import {
  CAMPAIGN_STATUSES, LANGUAGES, LANGUAGE_NAMES, LOCALIZATION_ITEMS, PLATFORMS, PRICE_STATUSES, PRIORITIES, TAGS,
} from './domain/schema.js';
import {
  exportCampaignsCsv, exportCountriesCsv, exportHistoryCsv, exportPriceTestsCsv, importCampaignsCsv,
  importCountriesCsv,
} from './domain/csv.js';

const store = new Store(new HttpRepository());
const view = document.getElementById('view');
const ui = {
  search: '', sort: 'cpi_asc', historyCountry: '', adsCountry: '', testsCountry: '',
  editTest: null, editCampaign: null, errors: {}, lastImport: null,
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
    a.classList.toggle('active', a.dataset.route === (r.name === 'country' ? 'countries' : r.name));
  });
  const views = {
    dashboard: renderDashboard, countries: renderCountries, country: () => renderCountry(r.id),
    tests: renderTests, ads: renderAds, localization: renderLocalization, history: renderHistory,
    settings: renderSettings,
  };
  view.innerHTML = (views[r.name] ?? renderDashboard)();
  document.getElementById('save-state').textContent = `保存: ${new Date(doc().updatedAt).toLocaleString()}`;
}

// --- Dashboard ---------------------------------------------------------------------

function kpi(label, value, { key = false, cls = '' } = {}) {
  return `<div class="kpi ${key ? 'key' : ''}"><div class="label">${esc(label)}</div><div class="value ${cls}">${value}</div></div>`;
}

function renderDashboard() {
  const t = totals(doc());
  const rows = doc().countries.map((c) => ({ c, s: stats(c) }));
  const review = rows.filter(({ s }) => s.flowNeedsReview);
  return `
    <h1>Dashboard</h1>
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
      ${kpi('Net Revenue', yen(t.net))}
      ${kpi('Ad Profit / Loss', yen(t.profit), { cls: sign(t.profit) })}
      ${kpi('ROAS (net)', ratio(t.roas))}
    </div>
    <p class="muted small">Installs / Purchase Starts / Purchase Success は Settings の「全体の値」が入っていればそれを、無ければ国別の合計を使います。
      広告費・売上は国別の合計です。${t.installsApprox ? 'Installs は概数（≈）です。' : ''}</p>

    <h2>Purchase Start 後の離脱がある国</h2>
    ${review.length ? `<div class="table-wrap"><table><thead><tr><th class="l">Country</th><th>Installs</th><th>Purchase Starts</th><th>Purchase Success</th><th>Start→Success</th><th class="l">Status</th></tr></thead><tbody>
      ${review.map(({ c, s }) => `<tr class="clickable" data-href="#/country/${c.id}"><td class="l">${esc(c.name)}</td><td>${int(c.metrics.installs)}</td><td>${int(c.metrics.purchaseStarts)}</td>
        <td class="warning">${int(c.metrics.purchaseSuccess)}</td><td>${pct(s.startToSuccess)}</td><td class="l"><span class="badge warning">Purchase flow needs review</span></td></tr>`).join('')}
    </tbody></table></div>` : '<p class="muted">国別の Purchase Start が入力されると、ここに表示されます。</p>'}

    <h2>損益分岐（国別）</h2>
    <div class="table-wrap"><table><thead><tr><th class="l">Country</th><th>Price</th><th>Price ¥</th><th>Net / Purchase</th><th>CPI</th><th>Break-even Purchase Rate</th><th>Install→Success</th><th class="l">Price status</th></tr></thead><tbody>
      ${rows.map(({ c, s }) => `<tr class="clickable" data-href="#/country/${c.id}"><td class="l">${esc(c.name)}</td><td>${money(c.price, c.currency)}</td>
        <td>${yen(s.priceJPY)}</td><td>${yen(s.netPerPurchase)}</td><td>${yen(s.cpi)}${s.cpiIsManual ? '<span class="muted small"> 手入力</span>' : ''}</td>
        <td>${pct(s.breakEvenRate)}</td><td class="${finite(c.metrics.purchaseSuccess) === 0 ? 'warning' : ''}">${pct(s.installToSuccess, 3)}</td>
        <td class="l">${priceStatusBadge(c)}</td></tr>`).join('')}
    </tbody></table></div>
    ${rows.some(({ c }) => !hasRate(c.currency, doc().currencies)) ? '<p class="muted small">為替レートが未入力の通貨があると、円換算・損益分岐は「—」になります（Settings で入力）。</p>' : ''}`;
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
          ${th('Gross Revenue')}${th('Google Fee')}${th('Net Revenue')}${th('Profit / Loss')}${th('ROAS')}</tr>
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
          <td>${yen(s.gross)}</td><td>${yen(s.googleFee)}</td><td>${yen(s.net)}</td><td class="${sign(s.profit)}">${yen(s.profit)}</td><td>${ratio(s.roas)}</td>
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
          <tr><td class="l">Price（現地）</td><td>${money(c.price, c.currency)}</td></tr>
          <tr><td class="l">Price in JPY</td><td>${yen(s.priceJPY)}</td></tr>
          <tr><td class="l">Net Revenue / Purchase</td><td data-testid="net-per">${yen(s.netPerPurchase)}</td></tr>
          <tr><td class="l">CPI${s.cpiIsManual ? '（手入力）' : ''}</td><td>${yen(s.cpi)}</td></tr>
          <tr><td class="l">Break-even Purchase Rate</td><td data-testid="break-even">${pct(s.breakEvenRate)}</td></tr>
          <tr><td class="l">Install → Purchase Success（実績）</td><td>${pct(s.installToSuccess, 3)}</td></tr>
          <tr><td class="l">Gross / Google Fee / Net</td><td>${yen(s.gross)} / ${yen(s.googleFee)} / ${yen(s.net)}</td></tr>
          <tr><td class="l">Profit / Loss · ROAS</td><td><span class="${sign(s.profit)}">${yen(s.profit)}</span> · ${ratio(s.roas)}</td></tr>
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
        ${field('Ad Spend（¥）', numInput('adSpend', m.adSpend))}
        ${field('Impressions', numInput('impressions', m.impressions))}
        ${field('Clicks', numInput('clicks', m.clicks))}
        ${field('Installs', numInput('installs', m.installs))}
        ${field('CPI 手入力（¥・実績が無いとき）', numInput('cpiManual', m.cpiManual))}
        ${field('Pro Screen Views', numInput('proScreenViews', m.proScreenViews))}
        ${field('Purchase Starts', numInput('purchaseStarts', m.purchaseStarts))}
        ${field('Purchase Success', numInput('purchaseSuccess', m.purchaseSuccess))}
        ${field('Gross Revenue（¥・空欄なら Success × 価格）', numInput('grossRevenueJPY', m.grossRevenueJPY))}
      </div>
      <div class="row"><button class="primary">保存</button><span class="muted small">空欄 = 不明。0 とは区別します。</span></div>
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
        <td class="l">${esc(a.platform) || DASH}</td><td class="l">${esc(a.name)}</td><td>${yen(a.dailyBudget)}</td><td>${yen(a.spend)}</td>
        <td>${int(a.impressions)}</td><td>${int(a.clicks)}</td><td>${yen(cs.cpc)}</td><td>${int(a.installs)}</td><td>${yen(cs.cpi)}</td>
        <td>${esc(a.start) || DASH}</td><td>${esc(a.end) || DASH}</td><td class="l">${esc(a.status) || DASH}</td>
        <td><button data-action="edit-campaign" data-id="${a.id}">編集</button></td></tr>`;
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
    <div class="row"><select id="ads-country"><option value="">すべての国</option>${doc().countries.map((c) => `<option value="${c.id}" ${ui.adsCountry === c.id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select>
      <span class="muted">合計: Spend ${yen(sumBy('spend'))} ／ Installs ${int(sumBy('installs'))} ／ CPI ${yen(campaignStats({ spend: sumBy('spend'), installs: sumBy('installs') }).cpi)}</span></div>
    ${campaignsTable(list)}
    ${ui.adsCountry ? `<h2>${esc(countryById(ui.adsCountry)?.name)} にキャンペーンを追加</h2>${campaignForm(ui.adsCountry)}` : '<p class="muted small">国を選ぶと追加フォームが出ます。</p>'}
    <p class="muted small">キャンペーンの数字は国の実績（Countries の Ad Spend / Installs）には自動で足し込みません。国の実績は国の画面で入力します。</p>`;
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

    <h2>為替（手入力）</h2>
    <div class="panel">
      <table data-testid="fx-table"><thead><tr><th class="l">Currency</th><th>1 単位 = 円</th><th class="l">Updated At</th><th></th></tr></thead><tbody>
        ${codes.map((code) => `<tr><td class="l">${esc(code)}</td><td colspan="3"><form data-op="setRate" data-id="${esc(code)}" class="row" style="justify-content:flex-end;margin:0">
          ${numInput('rate', currencies[code]?.rateToJPY)}<input type="date" name="updatedAt" value="${esc(currencies[code]?.updatedAt ?? today())}"><button>保存</button></form></td></tr>`).join('')}
      </tbody></table>
      <form data-op="setRate" class="row"><input name="currency" placeholder="通貨（例 THB）" maxlength="3" style="width:110px">${numInput('rate', null, 'placeholder="円"')}<input type="date" name="updatedAt" value="${today()}"><button>通貨を追加</button></form>
      ${errorsFor('setRate')}
      <p class="muted small">為替 API は使いません。レートは自分で入れてください（空欄 = 未入力。円換算は「—」になります）。</p>
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
