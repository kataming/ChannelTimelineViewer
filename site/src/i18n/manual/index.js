// 操作マニュアルの文言（7言語）。分量が多いので言語ごとにファイルを分けている。
// 構造はどの言語も同じ:
//   { title, description, lede, platformNote, badges, tocTitle,
//     sections: [{ id, title, body?, steps: [{ title, body, only? }] }] }
// only: 'ios' / 'android' を付けた項目は、その OS だけの説明。
import en from './en.js';
import ja from './ja.js';
import zh from './zh.js';
import es from './es.js';
import de from './de.js';
import fr from './fr.js';
import ko from './ko.js';

export const manuals = { en, ja, zh, es, de, fr, ko };

/** その言語のマニュアル（未翻訳なら英語）。 */
export function manualFor(code) {
  return manuals[code] || manuals.en;
}

export default manuals;
