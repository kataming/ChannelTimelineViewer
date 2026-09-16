// Watch Queue モード（/{lang}/watch-queue/#v=1&ids=…）。
//
// Queue Launch Contract V1 のリンクで外から来たときだけ動く、Web版スマホVIEWERの第2の再生モード。
// 画面（TrialApp.astro variant="phone"）・公式プレイヤー（player.js）・移動ボタン・自動再生スイッチは
// 体験版とまったく同じものを使い、ここでは「キューの順番に再生する」ことだけを担う。
//
// 守ること（体験版と同じ）:
// - 公式の埋め込みプレイヤーだけで再生する。ダウンロード・広告回避・バックグラウンド再生はしない
// - 自動で次へ進むのは、自動再生スイッチがオンのときだけ（既定オン。オフにすれば停止する）。
//   オフなら終わったところで「次の動画を再生」を出す
// - 進む先はこのキューの次の動画だけ（関連動画・おすすめへは行かない。rel=0）
// - 体験版の保存（チャンネル・視聴記録・メモ）には触らない。キュー自体も保存しない
//   （自動再生スイッチの設定だけは体験版と共通）

import { fetchVideoInfo, TrialApiError } from './api.js';
import * as store from './storage.js';
import { fmt } from './model.js';
import { countText, nextPlayableIndex, parseQueueHash, upNextIndex } from './queue-model.js';
import { TrialPlayer } from './player.js';

/** スマホ枠の中でプレイヤーを描かせる幅（体験版と同じ）。 */
const PHONE_PLAYER_WIDTH = 390;
/** 再生できない動画で止まったとき、自動再生オンなら次へ進むまでの待ち時間。 */
const UNPLAYABLE_AUTO_SKIP_MS = 2500;

const $ = (id) => document.getElementById(id);

export function startQueue() {
  const root = $('ctv');
  if (!root || root.dataset.mode !== 'queue') return;
  new QueueViewer(root).init();
}

class QueueViewer {
  constructor(root) {
    this.root = root;
    this.lang = root.dataset.lang || 'en';
    const copy = JSON.parse($('ctv-i18n').textContent);
    this.ui = copy.ui;
    this.q = copy.queue;
    this.prefs = store.loadPrefs();

    this.items = []; // { id, title, channel, published, unplayable }（キューの順番のまま）
    this.current = -1;
    this.played = new Set();
    this.hasStarted = false;
    this.endedHandledFor = null;
    this.skipTimer = null;
    this.player = null;
    this.infoLoaded = false;
    this.truncated = false;
    this.rows = [];

    this.dateFormat = new Intl.DateTimeFormat(this.lang, { dateStyle: 'medium' });
    this.scroller = root.dataset.variant === 'phone' ? root.querySelector('.ctv-scroll') : null;
  }

  // ---------------------------------------------------------------- 起動

  init() {
    this.keepQueueOnLanguageLinks();
    // 同じページのままキューだけ変わったときは、最初から読み直す。
    window.addEventListener('hashchange', () => location.reload());

    const parsed = parseQueueHash(location.hash);
    if (!parsed.ok) {
      this.showInvalid();
      return;
    }

    this.items = parsed.ids.map((id) => ({ id, title: '', channel: '', published: 0, unplayable: false }));
    this.truncated = parsed.truncated;
    this.bind();
    this.prepareChrome();
    this.renderList();
    this.select(0, { autoplay: true });
    this.loadInfo();
  }

  /** 言語を切り替えてもキューを持ったまま移れるよう、言語リンクに今の # を付ける。 */
  keepQueueOnLanguageLinks() {
    document.querySelectorAll('a[data-lang]').forEach((a) => {
      const base = (a.getAttribute('href') || '').split('#')[0];
      a.setAttribute('href', base + location.hash);
    });
  }

  showInvalid() {
    show($('ctv-setup'), false);
    show($('ctv-workspace'), false);
    show($('ctv-queue-invalid'), true);
  }

  prepareChrome() {
    show($('ctv-setup'), false);
    show($('ctv-workspace'), true);
    show($('ctv-ch-thumb'), false);
    $('ctv-ch-title').textContent = this.q.title;

    // チャンネル単位の操作と、記録を使う設定は Watch Queue では使わない。
    for (const id of ['ctv-repeat', 'ctv-list-menu', 'ctv-toggle-watched', 'ctv-toggle-skip']) show($(id), false);
    for (const id of ['ctv-unwatched-only', 'ctv-resume-pref']) {
      const row = $(id) && $(id).closest('.ctv-toggle');
      if (row) row.hidden = true;
    }
    this.applyAutoplayUI();
  }

  bind() {
    $('ctv-back').addEventListener('click', () => this.setScreen('list'));
    $('ctv-next-btn').addEventListener('click', () => {
      const index = this.upNext();
      if (index >= 0) this.select(index, { autoplay: true });
    });

    $('ctv-first').addEventListener('click', () => this.select(0, { autoplay: true }));
    $('ctv-prev').addEventListener('click', () => this.select(this.current - 1, { autoplay: true }));
    $('ctv-next-video').addEventListener('click', () => this.select(this.current + 1, { autoplay: true }));
    $('ctv-last').addEventListener('click', () => this.select(this.items.length - 1, { autoplay: true }));
    $('ctv-play-next').addEventListener('click', () => this.goToNext());
    $('ctv-queue-skip').addEventListener('click', () => this.goToNext());
    $('ctv-queue-restart').addEventListener('click', () => this.restartQueue());
    $('ctv-restart').addEventListener('click', () => {
      if (this.player) this.player.seek(0);
    });

    $('ctv-autoplay').addEventListener('change', (e) => {
      this.prefs.autoplay = e.target.checked;
      store.savePrefs(this.prefs);
      this.applyAutoplayUI();
    });

    // メニューは項目を押したら閉じる。外を押しても閉じる（体験版と同じ）。
    this.root.addEventListener('click', (e) => {
      const inside = e.target.closest ? e.target.closest('.ctv-menu') : null;
      this.root.querySelectorAll('details.ctv-menu[open]').forEach((d) => {
        if (d !== inside || e.target.closest('.ctv-menu-body')) d.open = false;
      });
    });

    window.addEventListener('resize', () => {
      clearTimeout(this.resizeTimer);
      this.resizeTimer = setTimeout(() => this.updatePlayerScale(), 120);
    });
    document.addEventListener('fullscreenchange', () => {
      if (document.fullscreenElement) this.root.dataset.fullscreen = 'true';
      else delete this.root.dataset.fullscreen;
      this.updatePlayerScale();
    });
  }

  // ---------------------------------------------------------------- 動画の情報（タイトルなど）

  async loadInfo() {
    this.setStatus('loading', this.ui.loading);
    let info = null;
    let failure = null;
    try {
      info = await fetchVideoInfo(this.items.map((item) => item.id));
    } catch (err) {
      failure = err;
    }

    if (info) {
      for (const item of this.items) {
        const found = info.get(item.id);
        // Data API が返さない＝非公開・削除済み。埋め込み不可も再生できない。
        if (!found || found.embeddable === false) {
          item.unplayable = true;
          if (!found) continue;
        }
        item.title = found.title || '';
        item.channel = found.channelTitle || '';
        item.published = Date.parse(found.published) || 0;
      }
    }
    this.infoLoaded = true;

    const code = failure ? (failure instanceof TrialApiError ? failure.code : 'unknown') : null;
    if (code === 'quota') this.setStatus('warn', this.ui.errQuota);
    else if (code === 'network') this.setStatus('warn', this.ui.errNetwork);
    else if (this.truncated) this.setStatus('info', fmt(this.q.truncatedFormat, String(this.items.length)));
    // 中継が使えないとき（notConfigured など）はタイトルが出ないだけで、再生はそのまま続けられる。
    else this.setStatus('none', '');

    this.items.forEach((_, index) => this.refreshRow(index));
    this.updateChrome();
    this.updateHeader();
    const current = this.items[this.current];
    if (current && current.unplayable && !this.hasStarted) {
      this.pausePlayer();
      this.showUnplayable();
    }
  }

  // ---------------------------------------------------------------- 一覧

  isUnplayable = (index) => Boolean(this.items[index] && this.items[index].unplayable);
  isPlayed = (index) => this.played.has(index);

  upNext() {
    return upNextIndex(this.items.length, this.isPlayed, this.isUnplayable);
  }

  titleOf(item) {
    return item.title || (this.infoLoaded ? this.ui.untitled : '');
  }

  renderList() {
    const list = $('ctv-list');
    list.replaceChildren();
    this.rows = this.items.map((item, index) => this.makeRow(item, index));
    const frag = document.createDocumentFragment();
    for (const row of this.rows) frag.appendChild(row);
    list.appendChild(frag);
    show($('ctv-list-empty'), false);
    show($('ctv-show-more'), false);
    this.updateHeader();
  }

  makeRow(item, index) {
    const li = document.createElement('li');
    li.className = 'ctv-row';
    li.dataset.id = item.id;

    const play = document.createElement('button');
    play.type = 'button';
    play.className = 'ctv-row-main';
    play.addEventListener('click', () => this.select(index, { autoplay: true }));

    const num = document.createElement('span');
    num.className = 'ctv-num';
    num.textContent = String(index + 1);

    const thumb = document.createElement('img');
    thumb.className = 'ctv-thumb';
    thumb.loading = 'lazy';
    thumb.decoding = 'async';
    thumb.width = 320;
    thumb.height = 180;
    thumb.alt = '';
    thumb.src = thumbURL(item.id);

    const text = document.createElement('span');
    text.className = 'ctv-row-text';
    const title = document.createElement('span');
    title.className = 'ctv-row-title';
    const meta = document.createElement('span');
    meta.className = 'ctv-row-meta';
    text.append(title, meta);

    play.append(num, thumb, text);
    li.append(play);
    this.paintRow(li, index);
    return li;
  }

  paintRow(li, index) {
    const item = this.items[index];
    li.classList.toggle('is-current', index === this.current);
    li.classList.toggle('is-watched', this.isPlayed(index));
    li.classList.toggle('is-skipped', item.unplayable);
    li.querySelector('.ctv-row-title').textContent = this.titleOf(item);

    const meta = li.querySelector('.ctv-row-meta');
    meta.replaceChildren();
    const add = (value, className) => {
      const span = document.createElement('span');
      if (className) span.className = className;
      span.textContent = value;
      meta.appendChild(span);
    };
    if (item.channel) add(item.channel, 'ctv-badge-date');
    if (this.isPlayed(index)) add(this.ui.watched, 'ctv-badge ctv-badge-watched');
    if (item.unplayable) add(this.q.unplayable, 'ctv-badge ctv-badge-unplayable');
  }

  refreshRow(index) {
    const li = this.rows[index];
    if (li) this.paintRow(li, index);
  }

  updateHeader() {
    $('ctv-count').textContent = countText(this.q, this.items.length, this.lang);

    const index = this.upNext();
    const nextBtn = $('ctv-next-btn');
    if (index < 0) {
      show(nextBtn, false);
      $('ctv-allwatched').textContent = this.q.completed;
      show($('ctv-allwatched'), this.played.size > 0);
      return;
    }
    const item = this.items[index];
    $('ctv-next-label').textContent = fmt(this.ui.upNextFormat, String(index + 1));
    $('ctv-next-title').textContent = this.titleOf(item);
    $('ctv-next-thumb').src = thumbURL(item.id);
    show(nextBtn, true);
    show($('ctv-allwatched'), false);
  }

  // ---------------------------------------------------------------- 再生

  select(index, { autoplay = true, autoAdvanced = false } = {}) {
    const item = this.items[index];
    if (!item) return;

    const previous = this.current;
    this.current = index;
    this.hasStarted = false;
    this.endedHandledFor = null;
    clearTimeout(this.skipTimer);

    show($('ctv-player-empty'), false);
    show($('ctv-player-wrap'), true);
    show($('ctv-ended'), false);
    show($('ctv-resume-notice'), false);
    show($('ctv-queue-completed'), false);
    show($('ctv-queue-unplayable'), false);
    show($('ctv-auto-advanced'), autoAdvanced);
    this.setScreen('player');

    if (item.unplayable) {
      this.pausePlayer();
      this.showUnplayable();
    } else {
      this.ensurePlayer();
      this.updatePlayerScale();
      this.player.load(item.id, 0, autoplay).catch(() => this.setStatus('error', this.ui.errNetwork));
    }

    this.updateChrome();
    if (previous >= 0 && previous !== index) this.refreshRow(previous);
    this.refreshRow(index);
    this.updateHeader();
  }

  ensurePlayer() {
    if (this.player) return;
    this.player = new TrialPlayer($('ctv-player-mount'), {
      onState: (playerState, videoId) => this.onPlayerState(playerState, videoId),
      onNearEnd: (videoId) => this.onNearEnd(videoId),
      onError: (code, videoId) => this.onPlayerError(videoId),
    });
  }

  pausePlayer() {
    try {
      if (this.player && this.player.player && this.player.player.pauseVideo) this.player.player.pauseVideo();
    } catch {
      /* まだ準備中なら何もしない */
    }
  }

  updateChrome() {
    const item = this.items[this.current];
    if (!item) return;
    $('ctv-now-title').textContent = this.titleOf(item);
    $('ctv-now-channel').textContent = item.channel || '';
    const position = fmt(
      this.ui.positionFormat,
      String(this.current + 1),
      this.items.length.toLocaleString(this.lang)
    );
    $('ctv-now-meta').textContent = item.published
      ? `${position} · ${this.dateFormat.format(new Date(item.published))}`
      : position;
    $('ctv-open-yt').href = `https://www.youtube.com/watch?v=${encodeURIComponent(item.id)}`;

    const last = this.items.length - 1;
    $('ctv-first').disabled = this.current <= 0;
    $('ctv-prev').disabled = this.current <= 0;
    $('ctv-next-video').disabled = this.current >= last;
    $('ctv-last').disabled = this.current >= last;
  }

  onPlayerState(playerState, videoId) {
    const item = this.items[this.current];
    if (!item || (videoId && videoId !== item.id)) return;
    if (playerState === 1) {
      this.hasStarted = true;
      show($('ctv-queue-unplayable'), false);
    }
    if (playerState !== 0) return; // 0 = ended
    if (!this.hasStarted || this.endedHandledFor === item.id) return;
    this.finish(false);
  }

  onNearEnd(videoId) {
    const item = this.items[this.current];
    if (!item || item.id !== videoId) return;
    if (!this.hasStarted || this.endedHandledFor === videoId) return;
    this.finish(true);
  }

  onPlayerError(videoId) {
    const index = this.items.findIndex((item) => item.id === videoId);
    if (index < 0) return;
    this.items[index].unplayable = true;
    this.refreshRow(index);
    if (index === this.current) this.showUnplayable();
    else this.updateHeader();
  }

  /**
   * 1本見終わったとき。early = 終了直前の先回り（全画面のまま次へ進むため。体験版と同じ）。
   * 自動再生オフ、または次が無いときは先回りせず、最後まで再生してから案内を出す。
   */
  finish(early) {
    const item = this.items[this.current];
    if (!item) return;
    const next = nextPlayableIndex(this.items.length, this.current, this.isUnplayable);

    if (this.prefs.autoplay && next >= 0) {
      this.markPlayed(this.current);
      this.endedHandledFor = item.id;
      this.select(next, { autoplay: true, autoAdvanced: true });
      return;
    }
    if (early) return;

    this.markPlayed(this.current);
    this.endedHandledFor = item.id;
    if (next >= 0) {
      $('ctv-ended-next').textContent = this.titleOf(this.items[next]);
      show($('ctv-ended'), true);
    } else {
      this.showCompleted();
    }
  }

  goToNext() {
    const next = nextPlayableIndex(this.items.length, this.current, this.isUnplayable);
    if (next >= 0) this.select(next, { autoplay: true });
    else this.showCompleted();
  }

  markPlayed(index) {
    this.played.add(index);
    this.refreshRow(index);
    this.updateHeader();
  }

  showUnplayable() {
    show($('ctv-ended'), false);
    show($('ctv-queue-unplayable'), true);
    this.updateHeader();
    clearTimeout(this.skipTimer);
    if (!this.prefs.autoplay) return;
    const at = this.current;
    this.skipTimer = setTimeout(() => {
      if (this.current === at) this.goToNext();
    }, UNPLAYABLE_AUTO_SKIP_MS);
  }

  showCompleted() {
    clearTimeout(this.skipTimer);
    show($('ctv-ended'), false);
    show($('ctv-queue-unplayable'), false);
    show($('ctv-auto-advanced'), false);
    show($('ctv-queue-completed'), true);
    this.setScreen('player');
    this.updateHeader();
  }

  restartQueue() {
    this.played.clear();
    this.items.forEach((_, index) => this.refreshRow(index));
    const first = nextPlayableIndex(this.items.length, -1, this.isUnplayable);
    if (first >= 0) this.select(first, { autoplay: true });
    else this.updateHeader();
  }

  // ---------------------------------------------------------------- 画面（体験版と同じ）

  setScreen(name) {
    if (this.root.dataset.variant !== 'phone') return;
    const changed = this.root.dataset.screen !== name;
    this.root.dataset.screen = name;
    show($('ctv-back'), name === 'player');
    this.updatePlayerScale();
    if (changed && this.scroller) this.scroller.scrollTo({ top: 0 });
  }

  updatePlayerScale() {
    if (this.root.dataset.variant !== 'phone') return;
    const box = this.root.querySelector('.ctv-video');
    const width = box ? box.clientWidth : 0;
    if (!width) return;
    this.root.style.setProperty('--ctv-player-scale', String(width / PHONE_PLAYER_WIDTH));
  }

  applyAutoplayUI() {
    const ui = this.ui;
    $('ctv-autoplay').checked = this.prefs.autoplay;
    $('ctv-autoplay-title').textContent = ui.autoplayTitle;
    $('ctv-autoplay-detail').textContent = this.prefs.autoplay ? ui.autoplayOnDetail : ui.autoplayOffDetail;
  }

  setStatus(kind, text) {
    const box = $('ctv-status');
    $('ctv-status-text').textContent = text || '';
    show($('ctv-status-retry'), false);
    box.dataset.kind = kind;
    show(box, kind !== 'none');
  }
}

function thumbURL(videoId) {
  return `https://i.ytimg.com/vi/${videoId}/mqdefault.jpg`;
}

function show(el, visible) {
  if (el) el.hidden = !visible;
}
