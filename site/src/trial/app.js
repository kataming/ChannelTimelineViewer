// Web体験版の本体（1チャンネルぶんの視聴補助）。
//
// できること: 古い順/新しい順、視聴済み・スキップ、進捗、メモ、続きから再生、
//             自動再生（既定オフ）、繰り返し、公式プレイヤーでの再生。
// しないこと: 複数チャンネルの保存、ダウンロード、広告回避、バックグラウンド再生、
//             アカウント・課金・同期。
//
// 保存先はこのブラウザの localStorage だけ（storage.js）。

import { parseInput } from './resolve.js';
import { resolveChannel, fetchVideosPage, TrialApiError } from './api.js';
import * as store from './storage.js';
import {
  sortVideos,
  visibleVideos,
  progressOf,
  nextUnwatchedIndex,
  nextIndexForAutoAdvance,
  positionToStore,
  resumeSeconds,
  formatSeconds,
  fmt,
} from './model.js';
import { TrialPlayer } from './player.js';

/** 一覧の最大取得ページ数（50件×100＝5000本）。アプリ側と同じ上限。 */
const MAX_PAGES = 100;
/** 新着確認で見るページ数。ここまでに既知の動画が出てこなければ全件取り直す。 */
const NEW_CHECK_PAGES = 5;
/** 一覧を一度に描く行数（残りはスクロールで足す）。 */
const CHUNK = 60;
/** スマホ枠の中でプレイヤーを描かせる幅（実機の画面幅に合わせる）。
    公式プレイヤーは狭いほど操作ボタンを大きく描くので、ここで描かせて縮小する。 */
const PHONE_PLAYER_WIDTH = 390;

const $ = (id) => document.getElementById(id);

/** 一覧の印に使う記号（中身は固定。ここに外から来た文字列は入れない）。 */
const ICON_CHECK =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
const ICON_SKIP =
  '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6v12l8-6zM16 6h2v12h-2z" fill="currentColor"/></svg>';

export function startTrial() {
  const root = $('ctv');
  if (!root) return;
  new Trial(root).init();
}

class Trial {
  constructor(root) {
    this.root = root;
    this.lang = root.dataset.lang || 'en';
    this.t = JSON.parse($('ctv-i18n').textContent);

    this.channel = null;
    this.videos = []; // 常に古い順
    this.state = null;
    this.prefs = store.loadPrefs();

    // phone のときだけ、一覧画面と再生画面を行き来する（アプリと同じ）。
    this.screen = 'list';
    this.current = null; // { id, index }（index は古い順での位置）
    this.hasStarted = false;
    this.endedHandledFor = null;
    this.pendingChannel = null; // Pro案内で「入れ替える」を待っているチャンネル

    this.rendered = 0;
    this.visible = [];
    this.rowsById = new Map();
    this.memoTimer = null;
    this.saveTimer = null;

    this.dateFormat = new Intl.DateTimeFormat(this.lang, { dateStyle: 'medium' });

    // スマホの枠の中で動かすとき（トップページ）は、ページではなく枠の中がスクロールする。
    // 「続きを描く」の判定はそのスクロール領域を基準にする。
    this.scroller = root.dataset.variant === 'phone' ? root.querySelector('.ctv-scroll') : null;
  }

  // ---------------------------------------------------------------- 起動

  init() {
    this.bind();
    this.applyPrefsToUI();

    if (!store.storageAvailable()) {
      show($('ctv-unsupported'), true);
    }

    const saved = store.loadChannel();
    if (saved) {
      this.channel = saved;
      this.state = store.loadState(saved.id);
      const cached = store.loadVideos(saved.id);
      this.enterWorkspace();
      if (cached && cached.videos.length) {
        this.videos = sortVideos(cached.videos, true);
        this.setUpdated(cached.updatedAt);
        this.renderAll();
        this.restoreLastVideo();
        this.checkForNew();
      } else {
        this.fetchAll();
      }
    } else {
      show($('ctv-setup'), true);
    }
  }

  bind() {
    $('ctv-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.submit();
    });
    $('ctv-setup-cancel').addEventListener('click', () => {
      show($('ctv-setup'), false);
      this.setFormError('');
    });

    $('ctv-check-new').addEventListener('click', () => this.checkForNew(true));
    $('ctv-reload').addEventListener('click', () => this.fetchAll());
    $('ctv-change').addEventListener('click', () => {
      show($('ctv-setup'), true);
      $('ctv-input').focus();
    });
    $('ctv-remove').addEventListener('click', () => this.removeChannel());
    $('ctv-status-retry').addEventListener('click', () => this.fetchAll());

    // 一覧に戻る（再生画面から）
    $('ctv-back').addEventListener('click', () => this.setScreen('list'));

    // 並び替えは1つのボタンで「古い順 ⇄ 新しい順」を切り替える（アプリのメニューと同じ2択）
    $('ctv-sort-toggle').addEventListener('click', () => {
      if (!this.state) return;
      this.state.sort = this.state.sort === 'newest' ? 'oldest' : 'newest';
      this.persistState();
      this.renderAll();
    });
    this.root.querySelectorAll('[data-filter]').forEach((btn) => {
      btn.addEventListener('click', () => {
        if (!this.state) return;
        this.state.filter = btn.dataset.filter;
        this.persistState();
        this.renderAll();
      });
    });

    $('ctv-next-btn').addEventListener('click', () => this.playUpNext());

    // プレイヤーの操作
    $('ctv-first').addEventListener('click', () => this.moveTo(0));
    $('ctv-prev').addEventListener('click', () => this.moveTo(this.current ? this.current.index - 1 : 0));
    $('ctv-next-video').addEventListener('click', () => this.moveTo(this.current ? this.current.index + 1 : 0));
    $('ctv-last').addEventListener('click', () => this.moveTo(this.videos.length - 1));
    $('ctv-play-next').addEventListener('click', () => this.moveTo(this.current ? this.current.index + 1 : 0));
    $('ctv-restart').addEventListener('click', () => this.restartCurrent());
    $('ctv-resume-restart').addEventListener('click', () => this.restartCurrent());
    $('ctv-toggle-watched').addEventListener('click', () => this.toggleWatched(this.current && this.current.id));
    $('ctv-toggle-skip').addEventListener('click', () => this.toggleSkipped(this.current && this.current.id));

    // 再生設定
    $('ctv-autoplay').addEventListener('change', (e) => {
      this.prefs.autoplay = e.target.checked;
      store.savePrefs(this.prefs);
      this.applyPrefsToUI();
    });
    $('ctv-unwatched-only').addEventListener('change', (e) => {
      this.prefs.unwatchedOnly = e.target.checked;
      store.savePrefs(this.prefs);
    });
    $('ctv-resume-pref').addEventListener('change', (e) => {
      this.prefs.resume = e.target.checked;
      store.savePrefs(this.prefs);
    });
    $('ctv-repeat').addEventListener('click', () => {
      const order = { off: 'one', one: 'all', all: 'off' };
      this.prefs.repeat = order[this.prefs.repeat] || 'off';
      store.savePrefs(this.prefs);
      this.applyPrefsToUI();
    });

    // メモ（入力のたびに自動保存）
    $('ctv-memo').addEventListener('input', (e) => {
      const id = this.current && this.current.id;
      if (!id) return;
      const text = e.target.value;
      clearTimeout(this.memoTimer);
      this.memoTimer = setTimeout(() => {
        if (text.trim()) this.state.m[id] = text;
        else delete this.state.m[id];
        this.persistState();
        this.refreshRow(id);
      }, 400);
    });

    // Pro 案内
    $('ctv-pro-cancel').addEventListener('click', () => this.closePro());
    $('ctv-pro-replace').addEventListener('click', () => {
      const next = this.pendingChannel;
      this.closePro();
      if (next) this.adopt(next, { replacing: true });
    });

    // メニューは項目を押したら閉じる。外を押しても閉じる。
    this.root.addEventListener('click', (e) => {
      const inside = e.target.closest ? e.target.closest('.ctv-menu') : null;
      this.root.querySelectorAll('details.ctv-menu[open]').forEach((d) => {
        if (d !== inside || e.target.closest('.ctv-menu-body')) d.open = false;
      });
    });

    // 一覧のスクロールで続きを描く
    const sentinel = $('ctv-sentinel');
    if ('IntersectionObserver' in window) {
      this.observer = new IntersectionObserver(
        (entries) => {
          if (entries.some((e) => e.isIntersecting)) this.appendChunk();
        },
        { root: this.scroller || null, rootMargin: '200px' }
      );
      this.observer.observe(sentinel);
    }
    $('ctv-show-more').addEventListener('click', () => this.appendChunk());

    // 窓の大きさが変わるとスマホ枠の幅も変わるので、縮小率を取り直す。
    window.addEventListener('resize', () => {
      clearTimeout(this.resizeTimer);
      this.resizeTimer = setTimeout(() => this.updatePlayerScale(), 120);
    });

    // 全画面のあいだは縮小しない。
    document.addEventListener('fullscreenchange', () => {
      const full = Boolean(document.fullscreenElement);
      if (full) this.root.dataset.fullscreen = 'true';
      else delete this.root.dataset.fullscreen;
      this.updatePlayerScale();
    });
  }

  // ---------------------------------------------------------------- 入力

  async submit() {
    const raw = $('ctv-input').value;
    const identifier = parseInput(raw);
    if (!identifier) {
      this.setFormError(this.t.ui.errInvalid);
      return;
    }

    this.setFormError('');
    this.setSubmitting(true);
    try {
      const channel = await resolveChannel(identifier);
      if (this.channel && this.channel.id !== channel.id) {
        // 2チャンネル目。ここで止めて、アプリ版Proを案内する。
        this.pendingChannel = channel;
        this.openPro(channel);
        return;
      }
      this.adopt(channel, { replacing: false });
    } catch (err) {
      this.setFormError(this.messageFor(err));
    } finally {
      this.setSubmitting(false);
    }
  }

  setSubmitting(busy) {
    const btn = $('ctv-submit');
    btn.disabled = busy;
    $('ctv-submit-label').textContent = busy ? this.t.ui.fetching : this.t.ui.fetch;
  }

  setFormError(message) {
    const el = $('ctv-form-error');
    el.textContent = message || '';
    show(el, Boolean(message));
  }

  messageFor(err) {
    const code = err instanceof TrialApiError ? err.code : 'unknown';
    const ui = this.t.ui;
    switch (code) {
      case 'invalid':
        return ui.errInvalid;
      case 'notFound':
        return ui.errNotFound;
      case 'quota':
        return ui.errQuota;
      case 'network':
        return ui.errNetwork;
      case 'notConfigured':
        return ui.errNotConfigured;
      default:
        return ui.errUnknown;
    }
  }

  /** チャンネルを保存して読み込む。replacing なら前のチャンネルの記録を消す。 */
  adopt(channel, { replacing }) {
    if (replacing && this.channel) store.clearChannel(this.channel.id);
    if (!replacing && this.channel && this.channel.id === channel.id) {
      // 同じチャンネルを入れ直しただけ。記録はそのままにして再取得する。
      this.channel = { ...this.channel, ...channel };
      store.saveChannel(this.channel);
      show($('ctv-setup'), false);
      this.enterWorkspace();
      this.fetchAll();
      return;
    }

    this.channel = channel;
    store.saveChannel(channel);
    this.state = store.loadState(channel.id);
    this.videos = [];
    this.current = null;
    this.pendingChannel = null;
    show($('ctv-setup'), false);
    $('ctv-input').value = '';
    this.enterWorkspace();
    this.fetchAll();
  }

  removeChannel() {
    if (!this.channel) return;
    const message = fmt(this.t.ui.removeConfirm, this.channel.title || this.t.ui.untitledChannel);
    if (!window.confirm(message)) return;

    store.clearChannel(this.channel.id);
    if (this.player) this.player.destroy();
    this.player = null;
    this.channel = null;
    this.videos = [];
    this.state = null;
    this.current = null;
    show($('ctv-workspace'), false);
    show($('ctv-setup'), true);
    show($('ctv-setup-cancel'), false);
    this.setScreen('list');
    $('ctv-input').focus();
  }

  /** phone のときだけ、一覧画面と再生画面を切り替える。 */
  setScreen(name) {
    this.screen = name;
    if (this.root.dataset.variant !== 'phone') return;
    this.root.dataset.screen = name;
    show($('ctv-back'), name === 'player');
    this.updatePlayerScale();
    // 画面が変わったら枠の中は先頭から見せる（アプリの画面遷移と同じ感覚にする）。
    if (this.scroller) this.scroller.scrollTo({ top: 0 });
  }

  /**
   * スマホ枠のプレイヤーの縮小率を決める。
   * 枠の幅 ÷ 390 を CSS 変数に入れるだけ（見た目の計算は CSS 側）。
   */
  updatePlayerScale() {
    if (this.root.dataset.variant !== 'phone') return;
    const box = this.root.querySelector('.ctv-video');
    const width = box ? box.clientWidth : 0;
    if (!width) return;
    this.root.style.setProperty('--ctv-player-scale', String(width / PHONE_PLAYER_WIDTH));
  }

  enterWorkspace() {
    show($('ctv-workspace'), true);
    show($('ctv-setup-cancel'), true);
    const thumb = $('ctv-ch-thumb');
    if (this.channel.thumb) {
      thumb.src = this.channel.thumb;
      thumb.alt = '';
      show(thumb, true);
    } else {
      show(thumb, false);
    }
    $('ctv-ch-title').textContent = this.channel.title || this.t.ui.untitledChannel;
    $('ctv-ch-link').href = `https://www.youtube.com/channel/${encodeURIComponent(this.channel.id)}`;
  }

  // ---------------------------------------------------------------- 取得

  async fetchAll() {
    if (!this.channel) return;
    const playlist = this.channel.uploads || uploadsFromChannelId(this.channel.id);
    if (!playlist) {
      this.setStatus('error', this.t.ui.errUnknown);
      return;
    }

    this.setStatus('loading', this.t.ui.loading);
    const collected = [];
    let token = null;
    let page = 0;
    let failure = null;

    try {
      do {
        const { items, next } = await fetchVideosPage(playlist, token);
        collected.push(...items);
        token = next;
        page += 1;
        this.setStatus('loading', fmt(this.t.ui.loadingCount, collected.length.toLocaleString(this.lang)));
      } while (token && page < MAX_PAGES);
    } catch (err) {
      // 途中まで取れていれば、それだけでも使えるようにする。
      if (!collected.length) {
        this.setStatus('error', this.messageFor(err));
        return;
      }
      failure = err;
    }

    // 上限に達して打ち切った（＝本数が多すぎる）のか、途中で失敗したのかを区別する。
    const truncated = Boolean(token) && !failure;
    this.videos = sortVideos(collected, true);
    store.saveVideos(this.channel.id, this.videos, { truncated });
    this.setUpdated(Date.now());

    if (!this.videos.length) {
      this.setStatus('error', this.t.ui.empty);
      return;
    }
    if (failure) this.setStatus('warn', this.messageFor(failure));
    else if (truncated) {
      this.setStatus('warn', fmt(this.t.ui.errTooMany, this.videos.length.toLocaleString(this.lang)));
    } else this.setStatus('none', '');
    this.renderAll();
    // すでに何か開いているなら、取り直しで巻き戻さない。
    if (!this.current) this.restoreLastVideo();
  }

  /** 新着だけを確認する（既知の動画に当たった時点で止める）。 */
  async checkForNew(explicit = false) {
    if (!this.channel || !this.videos.length) return;
    const playlist = this.channel.uploads || uploadsFromChannelId(this.channel.id);
    if (!playlist) return;

    const known = new Set(this.videos.map((v) => v.id));
    this.setStatus('loading', this.t.ui.checkingNew);

    const fresh = [];
    let token = null;
    let page = 0;
    let reachedKnown = false;

    try {
      do {
        const { items, next } = await fetchVideosPage(playlist, token);
        for (const item of items) {
          if (known.has(item.id)) {
            reachedKnown = true;
            break;
          }
          fresh.push(item);
        }
        if (reachedKnown) break;
        token = next;
        page += 1;
      } while (token && page < NEW_CHECK_PAGES);
    } catch (err) {
      this.setStatus(explicit ? 'error' : 'none', explicit ? this.messageFor(err) : '');
      return;
    }

    // 既知に当たらないまま見終わった＝差分が大きい。全件取り直す。
    if (!reachedKnown && token) {
      await this.fetchAll();
      return;
    }

    if (fresh.length) {
      this.videos = sortVideos(this.videos.concat(fresh), true);
      store.saveVideos(this.channel.id, this.videos);
      this.renderAll();
    }
    this.setUpdated(Date.now());
    this.setStatus(
      explicit ? 'info' : 'none',
      explicit
        ? fresh.length
          ? fmt(this.t.ui.newFound, fresh.length.toLocaleString(this.lang))
          : this.t.ui.noNew
        : ''
    );
  }

  setStatus(kind, text) {
    const box = $('ctv-status');
    $('ctv-status-text').textContent = text || '';
    show($('ctv-status-retry'), kind === 'error');
    box.dataset.kind = kind;
    show(box, kind !== 'none');
  }

  setUpdated(ms) {
    const el = $('ctv-updated');
    if (!ms) {
      el.textContent = '';
      return;
    }
    el.textContent = fmt(this.t.ui.lastUpdated, this.dateFormat.format(new Date(ms)));
  }

  // ---------------------------------------------------------------- 一覧

  isWatched = (id) => Boolean(this.state && this.state.w[id]);
  isSkipped = (id) => Boolean(this.state && this.state.s[id]);
  hasMemo = (id) => Boolean(this.state && this.state.m[id]);

  renderAll() {
    this.indexById = new Map(this.videos.map((v, i) => [v.id, i]));
    this.visible = visibleVideos(this.videos, {
      sort: this.state.sort,
      filter: this.state.filter,
      isWatched: this.isWatched,
    });

    $('ctv-sort-label').textContent =
      this.state.sort === 'newest' ? this.t.ui.sortNewest : this.t.ui.sortOldest;
    this.root.querySelectorAll('[data-filter]').forEach((b) => {
      b.setAttribute('aria-pressed', String(b.dataset.filter === this.state.filter));
    });

    $('ctv-list').replaceChildren();
    this.rowsById.clear();
    this.rendered = 0;
    this.appendChunk();

    this.updateHeader();
    show($('ctv-list-empty'), this.visible.length === 0);
    $('ctv-list-empty').textContent = this.videos.length
      ? this.t.ui.emptyFiltered
      : this.t.ui.empty;
  }

  appendChunk() {
    if (this.rendered >= this.visible.length) {
      show($('ctv-show-more'), false);
      return;
    }
    const list = $('ctv-list');
    const end = Math.min(this.rendered + CHUNK, this.visible.length);
    const frag = document.createDocumentFragment();
    for (let i = this.rendered; i < end; i += 1) {
      const row = this.makeRow(this.visible[i]);
      frag.appendChild(row);
    }
    list.appendChild(frag);
    this.rendered = end;
    show($('ctv-show-more'), this.rendered < this.visible.length);
  }

  makeRow(video) {
    const li = document.createElement('li');
    li.className = 'ctv-row';
    li.dataset.id = video.id;

    const play = document.createElement('button');
    play.type = 'button';
    play.className = 'ctv-row-main';

    const num = document.createElement('span');
    num.className = 'ctv-num';
    num.textContent = String((this.indexById.get(video.id) ?? 0) + 1);

    const thumb = document.createElement('img');
    thumb.className = 'ctv-thumb';
    thumb.loading = 'lazy';
    thumb.decoding = 'async';
    // mqdefault は 320x180。実寸は CSS で決めるが、比率を先に伝えて読み込み時のガタつきを防ぐ。
    thumb.width = 320;
    thumb.height = 180;
    thumb.alt = '';
    thumb.src = thumbURL(video.id);

    const text = document.createElement('span');
    text.className = 'ctv-row-text';

    const title = document.createElement('span');
    title.className = 'ctv-row-title';
    title.textContent = video.title || this.t.ui.untitled;

    const meta = document.createElement('span');
    meta.className = 'ctv-row-meta';

    text.append(title, meta);
    play.append(num, thumb, text);
    play.addEventListener('click', () => this.openVideo(video.id));

    const actions = document.createElement('div');
    actions.className = 'ctv-row-actions';

    // 印はアプリと同じ丸い記号ボタン。意味は読み上げ（aria-label）と
    // ツールチップ（title）と行の説明文に持たせる。
    const watched = document.createElement('button');
    watched.type = 'button';
    watched.className = 'ctv-mark';
    watched.dataset.act = 'watched';
    watched.innerHTML = ICON_CHECK;
    watched.addEventListener('click', () => this.toggleWatched(video.id));

    const skip = document.createElement('button');
    skip.type = 'button';
    skip.className = 'ctv-mark';
    skip.dataset.act = 'skip';
    skip.innerHTML = ICON_SKIP;
    skip.addEventListener('click', () => this.toggleSkipped(video.id));

    actions.append(watched, skip);
    li.append(play, actions);

    this.rowsById.set(video.id, li);
    this.paintRow(li, video);
    return li;
  }

  paintRow(li, video) {
    const id = video.id;
    const watched = this.isWatched(id);
    const skipped = this.isSkipped(id);

    li.classList.toggle('is-watched', watched);
    li.classList.toggle('is-skipped', skipped);
    li.classList.toggle('is-current', Boolean(this.current && this.current.id === id));

    // 日付と印は分けて入れる（狭い枠では「視聴済み」の文字を消して、緑の丸だけで示す）。
    const meta = li.querySelector('.ctv-row-meta');
    meta.replaceChildren();
    const add = (text, className) => {
      const span = document.createElement('span');
      if (className) span.className = className;
      span.textContent = text;
      meta.appendChild(span);
    };
    add(this.dateFormat.format(new Date(video.published)), 'ctv-badge-date');
    if (watched) add(this.t.ui.watched, 'ctv-badge ctv-badge-watched');
    if (skipped) add(this.t.ui.skippedBadge, 'ctv-badge');
    if (this.hasMemo(id)) add(this.t.ui.hasMemo, 'ctv-badge');

    const watchedBtn = li.querySelector('[data-act="watched"]');
    const watchedLabel = watched ? this.t.ui.markUnwatched : this.t.ui.markWatched;
    watchedBtn.setAttribute('aria-label', watchedLabel);
    watchedBtn.title = watchedLabel;
    watchedBtn.setAttribute('aria-pressed', String(watched));

    const skipBtn = li.querySelector('[data-act="skip"]');
    const skipLabel = skipped ? this.t.ui.unskip : this.t.ui.skip;
    skipBtn.setAttribute('aria-label', skipLabel);
    skipBtn.title = skipLabel;
    skipBtn.setAttribute('aria-pressed', String(skipped));
  }

  refreshRow(id) {
    const li = this.rowsById.get(id);
    const index = this.indexById ? this.indexById.get(id) : undefined;
    if (!li || index === undefined) return;
    this.paintRow(li, this.videos[index]);
  }

  updateHeader() {
    const { done, total, percent } = progressOf(this.videos, this.isWatched);
    $('ctv-progress-text').textContent = fmt(
      this.t.ui.progressFormat,
      done.toLocaleString(this.lang),
      total.toLocaleString(this.lang),
      String(percent)
    );
    const bar = $('ctv-bar-fill');
    bar.style.width = `${percent}%`;
    const bar2 = $('ctv-bar');
    bar2.setAttribute('aria-valuenow', String(percent));

    $('ctv-count').textContent = fmt(
      this.t.ui.countFormat,
      this.visible.length.toLocaleString(this.lang),
      total.toLocaleString(this.lang)
    );

    const nextIndex = nextUnwatchedIndex(this.videos, this.isWatched, this.isSkipped);
    const nextBtn = $('ctv-next-btn');
    if (nextIndex < 0) {
      show(nextBtn, false);
      show($('ctv-allwatched'), this.videos.length > 0);
    } else {
      const video = this.videos[nextIndex];
      const saved = this.state.p[video.id];
      const label = saved ? this.t.ui.resumeFormat : this.t.ui.upNextFormat;
      $('ctv-next-label').textContent = fmt(label, String(nextIndex + 1));
      $('ctv-next-title').textContent = video.title || this.t.ui.untitled;
      $('ctv-next-thumb').src = thumbURL(video.id);
      show(nextBtn, true);
      show($('ctv-allwatched'), false);
    }
  }

  playUpNext() {
    const index = nextUnwatchedIndex(this.videos, this.isWatched, this.isSkipped);
    if (index < 0) return;
    this.moveTo(index);
    this.scrollToVideo(this.videos[index].id);
  }

  scrollToVideo(id) {
    // 再生画面を出しているあいだ（phone）は一覧が隠れているので何もしない。
    if (this.screen === 'player' && this.root.dataset.variant === 'phone') return;
    const position = this.visible.findIndex((v) => v.id === id);
    if (position < 0) return;
    while (this.rendered <= position && this.rendered < this.visible.length) this.appendChunk();
    const li = this.rowsById.get(id);
    if (li) li.scrollIntoView({ block: 'nearest' });
  }

  // ---------------------------------------------------------------- 状態の切り替え

  toggleWatched(id) {
    if (!id || !this.state) return;
    if (this.state.w[id]) delete this.state.w[id];
    else this.state.w[id] = Date.now();
    this.persistState();
    this.afterStateChange(id);
  }

  toggleSkipped(id) {
    if (!id || !this.state) return;
    if (this.state.s[id]) delete this.state.s[id];
    else this.state.s[id] = Date.now();
    this.persistState();
    this.afterStateChange(id);
  }

  markWatched(id) {
    if (!id || !this.state || this.state.w[id]) return;
    this.state.w[id] = Date.now();
    delete this.state.p[id]; // 見終わったので再開位置は捨てる
    this.persistState();
    this.afterStateChange(id);
  }

  afterStateChange(id) {
    // 絞り込み中は、状態が変わると一覧から外れることがあるので描き直す。
    if (this.state.filter !== 'all') this.renderAll();
    else {
      this.refreshRow(id);
      this.updateHeader();
    }
    this.updatePlayerChrome();
  }

  persistState() {
    if (!this.channel || !this.state) return;
    clearTimeout(this.saveTimer);
    this.saveTimer = setTimeout(() => store.saveState(this.channel.id, this.state), 150);
  }

  // ---------------------------------------------------------------- 再生

  restoreLastVideo() {
    if (!this.state || !this.state.last) return;
    const index = this.videos.findIndex((v) => v.id === this.state.last);
    if (index < 0) return;
    // 前回開いていた動画を「選んだ状態」にしておく（自動では再生しない）。
    // 画面はアプリと同じく一覧から始める。
    this.select(index, { autoplay: false });
    this.setScreen('list');
  }

  openVideo(id) {
    const index = this.videos.findIndex((v) => v.id === id);
    if (index >= 0) this.select(index, { autoplay: true });
  }

  moveTo(index) {
    if (index < 0 || index >= this.videos.length) return;
    this.select(index, { autoplay: true });
    this.scrollToVideo(this.videos[index].id);
  }

  select(index, { autoplay = true, autoAdvanced = false } = {}) {
    const video = this.videos[index];
    if (!video) return;

    const previousId = this.current && this.current.id;
    this.current = { id: video.id, index };
    this.hasStarted = false;
    this.endedHandledFor = null;
    this.state.last = video.id;
    this.persistState();

    show($('ctv-player-empty'), false);
    show($('ctv-player-wrap'), true);
    show($('ctv-ended'), false);
    show($('ctv-auto-advanced'), autoAdvanced);
    this.setScreen('player');

    const start = resumeSeconds(this.state.p[video.id], this.prefs.resume);
    if (!this.player) {
      this.player = new TrialPlayer($('ctv-player-mount'), {
        onState: (playerState) => this.onPlayerState(playerState),
        onTime: (id, t, d) => this.onPlayerTime(id, t, d),
        onNearEnd: (id) => this.onNearEnd(id),
        onError: () => this.setStatus('warn', this.t.ui.errUnknown),
      });
    }
    this.updatePlayerScale();
    this.player.load(video.id, start, autoplay).catch(() => {
      this.setStatus('error', this.t.ui.errNetwork);
    });

    this.updatePlayerChrome(start);
    if (previousId) this.refreshRow(previousId);
    this.refreshRow(video.id);
  }

  updatePlayerChrome(startSeconds) {
    const video = this.current ? this.videos[this.current.index] : null;
    if (!video) return;
    const ui = this.t.ui;

    $('ctv-now-title').textContent = video.title || ui.untitled;
    $('ctv-now-channel').textContent = (this.channel && this.channel.title) || '';
    $('ctv-now-meta').textContent = `${fmt(
      ui.positionFormat,
      String(this.current.index + 1),
      this.videos.length.toLocaleString(this.lang)
    )} · ${this.dateFormat.format(new Date(video.published))}`;

    $('ctv-open-yt').href = `https://www.youtube.com/watch?v=${encodeURIComponent(video.id)}`;

    const watched = this.isWatched(video.id);
    $('ctv-toggle-watched').textContent = watched ? ui.markUnwatched : ui.markWatched;
    $('ctv-toggle-watched').setAttribute('aria-pressed', String(watched));
    const skipped = this.isSkipped(video.id);
    $('ctv-toggle-skip').textContent = skipped ? ui.unskip : ui.skip;
    $('ctv-toggle-skip').setAttribute('aria-pressed', String(skipped));

    $('ctv-first').disabled = this.current.index === 0;
    $('ctv-prev').disabled = this.current.index === 0;
    $('ctv-next-video').disabled = this.current.index >= this.videos.length - 1;
    $('ctv-last').disabled = this.current.index >= this.videos.length - 1;

    const resumeNotice = $('ctv-resume-notice');
    if (startSeconds && startSeconds > 0) {
      $('ctv-resume-text').textContent = fmt(this.t.ui.resumeNotice, formatSeconds(startSeconds));
      show(resumeNotice, true);
    } else if (startSeconds !== undefined) {
      show(resumeNotice, false);
    }

    const memo = $('ctv-memo');
    if (memo.dataset.for !== video.id) {
      memo.dataset.for = video.id;
      memo.value = this.state.m[video.id] || '';
    }
  }

  restartCurrent() {
    if (!this.current || !this.player) return;
    delete this.state.p[this.current.id];
    this.persistState();
    show($('ctv-resume-notice'), false);
    this.player.seek(0);
  }

  onPlayerState(playerState) {
    if (playerState === 1) this.hasStarted = true;
    if (playerState !== 0) return; // 0 = ended
    if (!this.current || !this.hasStarted) return;
    if (this.endedHandledFor === this.current.id) return;
    this.finish(false);
  }

  onNearEnd(videoId) {
    if (!this.current || this.current.id !== videoId) return;
    if (!this.hasStarted || this.endedHandledFor === videoId) return;
    this.finish(true);
  }

  onPlayerTime(videoId, seconds, duration) {
    if (!this.state) return;
    const value = positionToStore(seconds, duration);
    if (value) this.state.p[videoId] = value;
    else delete this.state.p[videoId];
    this.persistState();
  }

  /**
   * 動画を見終わったときの処理。
   * early = 終了する直前の先回り（全画面のまま次へ進むため）。
   * 進む先が無いときは先回りしない＝最後まで再生してから案内を出す。
   */
  finish(early) {
    const video = this.videos[this.current.index];
    if (!video) return;

    if (this.prefs.repeat === 'one') {
      this.markWatched(video.id);
      this.endedHandledFor = null;
      this.hasStarted = false;
      show($('ctv-ended'), false);
      this.player.replay();
      return;
    }

    if (this.prefs.autoplay) {
      const next = nextIndexForAutoAdvance(this.videos, this.current.index, {
        isWatched: this.isWatched,
        isSkipped: this.isSkipped,
        unwatchedOnly: this.prefs.unwatchedOnly,
        repeatAll: this.prefs.repeat === 'all',
      });
      if (next >= 0) {
        this.markWatched(video.id);
        this.endedHandledFor = video.id;
        this.select(next, { autoplay: true, autoAdvanced: true });
        this.scrollToVideo(this.videos[next].id);
        return;
      }
    }

    // 次が無いなら先回りする意味はない。最後まで再生させる。
    if (early) return;

    this.markWatched(video.id);
    this.endedHandledFor = video.id;
    const hasNext = this.current.index < this.videos.length - 1;
    if (hasNext) {
      const next = this.videos[this.current.index + 1];
      $('ctv-ended-next').textContent = next.title || this.t.ui.untitled;
    }
    show($('ctv-ended'), hasNext);
  }

  // ---------------------------------------------------------------- 設定の見た目

  applyPrefsToUI() {
    const ui = this.t.ui;
    $('ctv-autoplay').checked = this.prefs.autoplay;
    $('ctv-autoplay-title').textContent = this.prefs.autoplay ? ui.autoplayOn : ui.autoplayOff;
    $('ctv-autoplay-detail').textContent = this.prefs.autoplay ? ui.autoplayOnDetail : ui.autoplayOffDetail;

    $('ctv-unwatched-only').checked = this.prefs.unwatchedOnly;
    $('ctv-resume-pref').checked = this.prefs.resume;

    const labels = { off: ui.repeatOff, one: ui.repeatOne, all: ui.repeatAll };
    $('ctv-repeat-value').textContent = labels[this.prefs.repeat];
    $('ctv-repeat').setAttribute('aria-pressed', String(this.prefs.repeat !== 'off'));
    const detail =
      this.prefs.repeat === 'one' ? ui.repeatOneDetail : this.prefs.repeat === 'all' ? ui.repeatAllDetail : '';
    $('ctv-repeat-detail').textContent = detail ? ` ${detail}` : '';
  }

  // ---------------------------------------------------------------- Pro 案内

  openPro(channel) {
    $('ctv-pro-warning').textContent = fmt(
      this.t.ui.proWarningFormat,
      (this.channel && this.channel.title) || this.t.ui.untitledChannel
    );
    $('ctv-pro-target').textContent = channel.title || this.t.ui.untitledChannel;
    const dialog = $('ctv-pro');
    if (typeof dialog.showModal === 'function') dialog.showModal();
    else dialog.setAttribute('open', '');
  }

  closePro() {
    this.pendingChannel = null;
    const dialog = $('ctv-pro');
    if (typeof dialog.close === 'function') dialog.close();
    else dialog.removeAttribute('open');
  }
}

/** 動画IDからサムネイルURLを作る（保存はしないので毎回組み立てる）。 */
function thumbURL(videoId) {
  return `https://i.ytimg.com/vi/${videoId}/mqdefault.jpg`;
}

/** UC… のチャンネルIDから uploads プレイリストID（UU…）を作る（保険）。 */
function uploadsFromChannelId(channelId) {
  return channelId && channelId.startsWith('UC') ? `UU${channelId.slice(2)}` : null;
}

function show(el, visible) {
  if (el) el.hidden = !visible;
}
