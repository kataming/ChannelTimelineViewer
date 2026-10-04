// 2026-10-04 に追加した 28 言語（アプリ画面と同じ 35 言語にそろえるため）。
// 1 言語 = 1 ファイル。中身は { site, manual, trial, watchQueue } で、形は英語の原本と同じ:
//   site       … translations.js の en と同じ形
//   manual     … manual/en.js と同じ形
//   trial      … trial.js の en と同じ形
//   watchQueue … watchQueue.js の en と同じ形
// 足りないキーは英語で埋まる（t() / manualFor() / trialCopy() / watchQueueCopy()）。
// 形の点検: node scripts/check-locales.mjs（npm run check からも呼ぶ）
import ar from './ar.js';
import bn from './bn.js';
import cs from './cs.js';
import nl from './nl.js';
import fil from './fil.js';
import el from './el.js';
import hi from './hi.js';
import hu from './hu.js';
import id from './id.js';
import it from './it.js';
import kn from './kn.js';
import mr from './mr.js';
import pl from './pl.js';
import pt from './pt.js';
import pa from './pa.js';
import ro from './ro.js';
import ru from './ru.js';
import sv from './sv.js';
import ta from './ta.js';
import te from './te.js';
import th from './th.js';
import zhHant from './zhHant.js';
import tr from './tr.js';
import uk from './uk.js';
import ur from './ur.js';
import vi from './vi.js';
import ms from './ms.js';
import zu from './zu.js';

export const extraLocales = { ar, bn, cs, nl, fil, el, hi, hu, id, it, kn, mr, pl, pt, pa, ro, ru, sv, ta, te, th, zhHant, tr, uk, ur, vi, ms, zu };
export default extraLocales;
