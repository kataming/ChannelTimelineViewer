// Watch Queue モード（/{lang}/watch-queue/）だけで使う文言（7言語）。
//
// Watch Queue モードは、Queue Launch Contract V1 のリンク（/watch-queue#v=1&ids=…）で
// 外から来たときだけ動く第2の再生モード。通常ページ（トップ・体験版・マニュアルなど）では
// **この文言を一切使わない**（通常サイトで Watch Queue を案内・宣伝しないため）。
//
// 体験版（trial.js の ui）にすでに同じ意味の文言があるもの（前へ・次へ・最初から再生・
// 現在位置・視聴済み・次の動画を再生・読み込み中・通信エラーなど）は、ここに持たずに
// そちらをそのまま使う（queue.js が ui.* を参照する）。ここに置くのは新しく必要になった文言だけ。
// 新しいキーを足すときは7言語すべてに入れること（npm test が点検する）。
//
// 差し込みは {1} の形。「Watch Queue」は機能名として訳さない（Pro と同じ扱い）。

const en = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: 'Plays the videos in the link one after another, in YouTube’s official embedded player.',
  },
  title: 'Watch Queue',
  countOne: '{1} video',
  countOther: '{1} videos',
  completed: 'Queue completed',
  completedDetail: 'All videos in this queue have been played.',
  unplayable: 'This video can’t be played',
  unplayableDetail: 'It may be private or deleted, or its owner doesn’t allow playback on other sites.',
  invalidTitle: 'This queue is empty or invalid',
  invalidDetail: 'Check the link and open it again.',
  truncatedFormat: 'Only the first {1} videos are shown.',
  noscript: 'Turn on JavaScript to play this queue.',
};

const ja = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: 'リンクで渡された動画を、YouTube公式の埋め込みプレイヤーで順番に再生します。',
  },
  title: 'Watch Queue',
  countOne: '{1}本',
  countOther: '{1}本',
  completed: 'キューの再生が完了しました',
  completedDetail: 'このキューの動画をすべて再生しました。',
  unplayable: 'この動画は再生できません',
  unplayableDetail: '非公開・削除済み、または投稿者がほかのサイトでの再生を許可していない可能性があります。',
  invalidTitle: 'キューが空か、リンクが正しくありません',
  invalidDetail: 'リンクを確認して、もう一度開いてください。',
  truncatedFormat: '最初の{1}本だけを表示しています。',
  noscript: 'このキューを再生するには JavaScript を有効にしてください。',
};

const zh = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: '在 YouTube 官方嵌入式播放器中按顺序播放链接中的视频。',
  },
  title: 'Watch Queue',
  countOne: '{1} 个视频',
  countOther: '{1} 个视频',
  completed: '队列已播放完毕',
  completedDetail: '此队列中的视频已全部播放。',
  unplayable: '此视频无法播放',
  unplayableDetail: '该视频可能已设为私享或被删除，或者上传者不允许在其他网站上播放。',
  invalidTitle: '队列为空或链接无效',
  invalidDetail: '请检查链接后重新打开。',
  truncatedFormat: '仅显示前 {1} 个视频。',
  noscript: '请启用 JavaScript 以播放此队列。',
};

const es = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: 'Reproduce en orden los vídeos del enlace en el reproductor integrado oficial de YouTube.',
  },
  title: 'Watch Queue',
  countOne: '{1} vídeo',
  countOther: '{1} vídeos',
  completed: 'Cola completada',
  completedDetail: 'Se han reproducido todos los vídeos de esta cola.',
  unplayable: 'Este vídeo no se puede reproducir',
  unplayableDetail: 'Puede ser privado o haberse eliminado, o su propietario no permite reproducirlo en otros sitios.',
  invalidTitle: 'La cola está vacía o no es válida',
  invalidDetail: 'Comprueba el enlace y vuelve a abrirlo.',
  truncatedFormat: 'Solo se muestran los primeros {1} vídeos.',
  noscript: 'Activa JavaScript para reproducir esta cola.',
};

const de = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: 'Spielt die Videos aus dem Link der Reihe nach im offiziellen eingebetteten YouTube-Player ab.',
  },
  title: 'Watch Queue',
  countOne: '{1} Video',
  countOther: '{1} Videos',
  completed: 'Warteschlange abgeschlossen',
  completedDetail: 'Alle Videos dieser Warteschlange wurden abgespielt.',
  unplayable: 'Dieses Video kann nicht abgespielt werden',
  unplayableDetail: 'Es ist womöglich privat oder gelöscht, oder die Wiedergabe auf anderen Websites ist nicht erlaubt.',
  invalidTitle: 'Die Warteschlange ist leer oder ungültig',
  invalidDetail: 'Prüfe den Link und öffne ihn erneut.',
  truncatedFormat: 'Es werden nur die ersten {1} Videos angezeigt.',
  noscript: 'Aktiviere JavaScript, um diese Warteschlange abzuspielen.',
};

const fr = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: 'Lit dans l’ordre les vidéos du lien dans le lecteur intégré officiel de YouTube.',
  },
  title: 'Watch Queue',
  countOne: '{1} vidéo',
  countOther: '{1} vidéos',
  completed: 'File d’attente terminée',
  completedDetail: 'Toutes les vidéos de cette file d’attente ont été lues.',
  unplayable: 'Cette vidéo ne peut pas être lue',
  unplayableDetail: 'Elle est peut-être privée ou supprimée, ou son propriétaire n’autorise pas la lecture sur d’autres sites.',
  invalidTitle: 'La file d’attente est vide ou non valide',
  invalidDetail: 'Vérifiez le lien et ouvrez-le à nouveau.',
  truncatedFormat: 'Seules les {1} premières vidéos sont affichées.',
  noscript: 'Activez JavaScript pour lire cette file d’attente.',
};

const ko = {
  meta: {
    title: 'Watch Queue — Channel Timeline Viewer',
    description: '링크로 전달된 동영상을 YouTube 공식 삽입 플레이어에서 순서대로 재생합니다.',
  },
  title: 'Watch Queue',
  countOne: '동영상 {1}개',
  countOther: '동영상 {1}개',
  completed: '대기열 재생을 마쳤습니다',
  completedDetail: '이 대기열의 동영상을 모두 재생했습니다.',
  unplayable: '이 동영상은 재생할 수 없습니다',
  unplayableDetail: '비공개 또는 삭제된 동영상이거나, 업로더가 다른 사이트에서의 재생을 허용하지 않았을 수 있습니다.',
  invalidTitle: '대기열이 비어 있거나 올바르지 않습니다',
  invalidDetail: '링크를 확인한 뒤 다시 열어 주세요.',
  truncatedFormat: '처음 {1}개만 표시합니다.',
  noscript: '이 대기열을 재생하려면 JavaScript를 켜 주세요.',
};

export const watchQueue = { en, ja, zh, es, de, fr, ko };

/** Watch Queue モードの文言（未翻訳キーは英語で埋める）。 */
export function watchQueueCopy(code) {
  const base = watchQueue.en;
  const own = watchQueue[code] || {};
  return { ...base, ...own, meta: { ...base.meta, ...(own.meta || {}) } };
}
