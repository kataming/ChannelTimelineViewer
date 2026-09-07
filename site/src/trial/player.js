// YouTube 公式 IFrame Player の薄いラッパー。
//
// 【やっていないこと】
// 独自プレイヤーは作らない。ダウンロード・広告回避・再生の改変も行わない。
// ここでしているのは、公式プレイヤーを埋め込んで、公式APIが通知する
// 「状態・再生位置」を受け取ることだけ。
//
// nearEnd（終わりぎわの先回り通知）は iOS / Android アプリの docs/player.html と同じ考え方。
// 全画面で見ているときに動画が終わるとブラウザが全画面を閉じてしまうため、
// 終わる直前に次の動画へ差し替えて、全画面のまま続けられるようにする。

const NEAR_END_LEAD = 0.5; // 何秒前に知らせるか
const NEAR_END_MIN_DURATION = 5; // これより短い動画では使わない（生配信・長さ不明も対象外）
const TICK_MS = 250;
const TIME_EVERY_TICKS = 20; // 250ms × 20 = 5秒ごとに位置を通知

let apiPromise = null;

/** IFrame Player API を一度だけ読み込む。 */
function loadIframeAPI() {
  if (window.YT && window.YT.Player) return Promise.resolve(window.YT);
  if (apiPromise) return apiPromise;

  apiPromise = new Promise((resolve, reject) => {
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = function () {
      if (typeof previous === 'function') previous();
      resolve(window.YT);
    };
    const tag = document.createElement('script');
    tag.src = 'https://www.youtube.com/iframe_api';
    tag.onerror = () => {
      apiPromise = null;
      reject(new Error('iframe_api'));
    };
    document.head.appendChild(tag);
  });
  return apiPromise;
}

export class TrialPlayer {
  /**
   * @param {HTMLElement} mount プレイヤーを差し込む要素（中身は置き換えられる）
   * @param {{onState:Function, onTime:Function, onNearEnd:Function, onError:Function}} handlers
   */
  constructor(mount, handlers = {}) {
    this.mount = mount;
    this.handlers = handlers;
    this.player = null;
    this.currentId = null;
    this.ticks = 0;
    this.nearEndPostedFor = null;
    this.timer = null;
  }

  /** 動画を読み込む（初回はプレイヤーを作る）。 */
  async load(videoId, startSeconds = 0, autoplay = true) {
    const start = Math.max(0, Math.floor(startSeconds || 0));

    if (this.player && typeof this.player.loadVideoById === 'function') {
      this.postTime(); // 切り替える前に「いまの動画」の位置を残す
      this.currentId = videoId;
      this.nearEndPostedFor = null;
      if (autoplay) this.player.loadVideoById({ videoId, startSeconds: start });
      else this.player.cueVideoById({ videoId, startSeconds: start });
      return;
    }

    const YT = await loadIframeAPI();
    this.currentId = videoId;
    this.nearEndPostedFor = null;

    const host = document.createElement('div');
    this.mount.replaceChildren(host);

    this.player = new YT.Player(host, {
      width: '100%',
      height: '100%',
      videoId,
      playerVars: {
        playsinline: 1,
        // 関連動画・おすすめへ流れないようにする（このチャンネルの一覧の中だけで完結させる）。
        rel: 0,
        autoplay: autoplay ? 1 : 0,
        start,
        cc_load_policy: 0,
        origin: location.origin,
      },
      events: {
        onReady: () => {
          this.applyIframeAttributes();
          if (this.handlers.onReady) this.handlers.onReady();
        },
        onStateChange: (e) => {
          if (e.data === 2 || e.data === 0) this.postTime();
          if (this.handlers.onState) this.handlers.onState(e.data, this.currentId);
        },
        onError: (e) => {
          if (this.handlers.onError) this.handlers.onError(e.data, this.currentId);
        },
      },
    });

    this.startTicking();
  }

  applyIframeAttributes() {
    const frame = this.mount.querySelector('iframe');
    if (!frame) return;
    frame.setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');
    frame.setAttribute('allow', 'autoplay; encrypted-media; picture-in-picture; fullscreen');
    frame.setAttribute('allowfullscreen', 'true');
    frame.setAttribute('title', 'YouTube');
  }

  startTicking() {
    if (this.timer) return;
    this.timer = setInterval(() => {
      this.checkNearEnd();
      this.ticks += 1;
      if (this.ticks % TIME_EVERY_TICKS === 0 && this.state() === 1) this.postTime();
    }, TICK_MS);
    window.addEventListener('pagehide', this.onPageHide);
  }

  onPageHide = () => this.postTime();

  state() {
    try {
      return this.player && this.player.getPlayerState ? this.player.getPlayerState() : -1;
    } catch {
      return -1;
    }
  }

  time() {
    try {
      return (this.player && this.player.getCurrentTime && this.player.getCurrentTime()) || 0;
    } catch {
      return 0;
    }
  }

  duration() {
    try {
      return (this.player && this.player.getDuration && this.player.getDuration()) || 0;
    } catch {
      return 0;
    }
  }

  postTime() {
    if (!this.currentId || !this.handlers.onTime) return;
    const t = this.time();
    const d = this.duration();
    if (t > 0) this.handlers.onTime(this.currentId, t, d);
  }

  /** 終わりぎわに一度だけ知らせる。 */
  checkNearEnd() {
    if (!this.handlers.onNearEnd || this.state() !== 1) return;
    const d = this.duration();
    const t = this.time();
    if (!Number.isFinite(d) || d < NEAR_END_MIN_DURATION) return;
    const remaining = d - t;
    // 巻き戻したら、また知らせられるようにする。
    if (remaining > NEAR_END_LEAD + 1.5) {
      this.nearEndPostedFor = null;
      return;
    }
    if (remaining > NEAR_END_LEAD) return;
    if (this.nearEndPostedFor === this.currentId) return;
    this.nearEndPostedFor = this.currentId;
    this.handlers.onNearEnd(this.currentId);
  }

  /** 1本リピート用。先頭に戻してそのまま再生し直す。 */
  replay() {
    if (!this.player) return;
    this.nearEndPostedFor = null;
    try {
      this.player.seekTo(0, true);
      this.player.playVideo();
    } catch {
      /* プレイヤーがまだ準備中なら何もしない */
    }
  }

  seek(seconds) {
    if (!this.player) return;
    try {
      this.player.seekTo(Math.max(0, seconds || 0), true);
      this.player.playVideo();
    } catch {
      /* 同上 */
    }
  }

  destroy() {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = null;
    }
    window.removeEventListener('pagehide', this.onPageHide);
    try {
      if (this.player && this.player.destroy) this.player.destroy();
    } catch {
      /* 破棄に失敗しても続行する */
    }
    this.player = null;
    this.currentId = null;
  }
}
