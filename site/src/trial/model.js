// 体験版の「考えるところ」。DOM にも localStorage にも触らない純粋関数だけを置く。
// アプリ側（VideoListViewModel / PlayerViewModel / PlaybackPositionStore）と同じ規則にしてある。

/** 再開位置として意味を持つ最小秒数（これ未満は「実質最初から」）。 */
export const MIN_RESUME_SECONDS = 10;
/** 終端からこの秒数以内まで見ていたら「見終わった」とみなす。 */
export const FINISHED_THRESHOLD_SECONDS = 15;

/** 公開日で並べ替える（元の配列は変えない）。 */
export function sortVideos(videos, ascending = true) {
  const copy = videos.slice();
  copy.sort((a, b) => (ascending ? a.published - b.published : b.published - a.published));
  return copy;
}

/** 並び替え＋視聴フィルターを適用した表示用リスト。 */
export function visibleVideos(videos, { sort = 'oldest', filter = 'all', isWatched = () => false } = {}) {
  const sorted = sortVideos(videos, sort !== 'newest');
  if (filter === 'unwatched') return sorted.filter((v) => !isWatched(v.id));
  if (filter === 'watched') return sorted.filter((v) => isWatched(v.id));
  return sorted;
}

/** 視聴済み本数・進捗率。 */
export function progressOf(videos, isWatched) {
  const total = videos.length;
  let done = 0;
  for (const v of videos) if (isWatched(v.id)) done += 1;
  return { done, total, percent: total ? Math.round((done / total) * 100) : 0 };
}

/**
 * 「次に見る」動画の位置（古い順での 0 始まり index）。無ければ -1。
 * スキップ指定は「見るつもりがない」ものなので候補から外す。
 */
export function nextUnwatchedIndex(ascVideos, isWatched, isSkipped = () => false) {
  return ascVideos.findIndex((v) => !isWatched(v.id) && !isSkipped(v.id));
}

/**
 * 自動再生で次に進む先（古い順での index）。無ければ -1。
 * - スキップ指定は常に飛ばす
 * - 「未視聴のみ再生」がオンなら視聴済みも飛ばす
 * - 全体リピートなら末尾まで行ったら先頭から探し直す
 */
export function nextIndexForAutoAdvance(
  ascVideos,
  currentIndex,
  { isWatched = () => false, isSkipped = () => false, unwatchedOnly = false, repeatAll = false } = {}
) {
  if (!ascVideos.length) return -1;
  const playable = (v) => {
    if (isSkipped(v.id)) return false;
    if (unwatchedOnly && isWatched(v.id)) return false;
    return true;
  };

  for (let i = currentIndex + 1; i < ascVideos.length; i += 1) {
    if (playable(ascVideos[i])) return i;
  }
  if (!repeatAll) return -1;
  for (let i = 0; i < currentIndex; i += 1) {
    if (playable(ascVideos[i])) return i;
  }
  return -1;
}

/**
 * 保存してよい再生位置かを判定して、保存する値を返す（保存しないなら null）。
 * 冒頭すぎる場合・ほぼ見終わっている場合は「続きから」の意味がないので捨てる。
 */
export function positionToStore(seconds, duration) {
  if (!Number.isFinite(seconds) || seconds < 0) return null;
  const nearEnd = duration > 0 && seconds >= duration - FINISHED_THRESHOLD_SECONDS;
  if (seconds < MIN_RESUME_SECONDS || nearEnd) return null;
  return { t: Math.floor(seconds), d: Math.max(0, Math.floor(duration || 0)) };
}

/** 保存済み位置から実際に使う再開秒数（設定がオフなら常に 0）。 */
export function resumeSeconds(saved, resumeEnabled) {
  if (!resumeEnabled || !saved) return 0;
  const t = Number(saved.t) || 0;
  return t >= MIN_RESUME_SECONDS ? t : 0;
}

/** 秒 → 1:23 / 1:02:03。 */
export function formatSeconds(total) {
  const s = Math.max(0, Math.floor(Number(total) || 0));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

/** "{1} / {2}" のような差し込み。 */
export function fmt(template, ...values) {
  return String(template).replace(/\{(\d+)\}/g, (whole, n) => {
    const v = values[Number(n) - 1];
    return v === undefined || v === null ? whole : String(v);
  });
}
