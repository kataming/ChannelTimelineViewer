// docs/player.html の「もうすぐ終わる」判定（checkNearEnd）を、偽のプレイヤーで確かめる。
//
//     node tools/player_nearend_test.js
//
// このページは公開済みのアプリからも読み込まれるため、壊すと全端末の再生に影響する。
// DOM も通信も使わない部分だけを抜き出して動かすので、Mac もブラウザも要らない。
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(ROOT, 'docs', 'player.html'), 'utf8');

const script = html.match(/<script>([\s\S]*?)<\/script>/);
if (!script) {
  console.error('player.html に <script> が見つかりません');
  process.exit(1);
}
const js = script[1];

const START = 'var NEAR_END_LEAD';
const END = '// 再生中は定期的に位置を通知';
if (js.indexOf(START) < 0 || js.indexOf(END) < 0) {
  console.error('checkNearEnd の範囲を見つけられません（player.html の作りが変わった可能性）');
  process.exit(1);
}
const source = js.slice(js.indexOf(START), js.indexOf(END));

// 抜き出したコードが参照する外側の値。
let posted = [];
let currentId = 'A';
let player = null;
// eslint-disable-next-line no-unused-vars
const post = (message) => posted.push(message);

// eslint-disable-next-line no-eval
const { checkNearEnd } = eval(`(function () { ${source}\n return { checkNearEnd }; })()`);

function fakePlayer({ state = 1, time = 0, duration = 100 } = {}) {
  return {
    getPlayerState: () => state,
    getCurrentTime: () => time,
    getDuration: () => duration,
  };
}

let failures = 0;
function check(name, ok) {
  console.log((ok ? '  OK   ' : '  NG   ') + name);
  if (!ok) failures++;
}

// 残りわずかになったら1回だけ知らせる
posted = [];
currentId = 'A';
player = fakePlayer({ time: 99.7 });
checkNearEnd();
checkNearEnd();
check('残り0.3秒で1回だけ通知する',
  posted.length === 1 && posted[0].event === 'nearEnd' && posted[0].v === 'A');

// 途中では知らせない
posted = [];
currentId = 'B';
player = fakePlayer({ time: 50 });
checkNearEnd();
check('途中では通知しない', posted.length === 0);

// 再生中だけ（一時停止・停止では知らせない）
posted = [];
currentId = 'C';
player = fakePlayer({ state: 2, time: 99.9 });
checkNearEnd();
check('一時停止中は通知しない', posted.length === 0);

// 短い動画・長さ不明（生配信）は対象外
posted = [];
currentId = 'D';
player = fakePlayer({ time: 0.1, duration: 3 });
checkNearEnd();
check('5秒未満の動画では通知しない', posted.length === 0);

posted = [];
currentId = 'E';
player = fakePlayer({ time: 10, duration: 0 });
checkNearEnd();
check('長さ不明（生配信）では通知しない', posted.length === 0);

// 巻き戻したら、また知らせられる
posted = [];
currentId = 'F';
player = fakePlayer({ time: 99.8 });
checkNearEnd();
const afterFirst = posted.length;
player = fakePlayer({ time: 10 });
checkNearEnd();
player = fakePlayer({ time: 99.8 });
checkNearEnd();
check('巻き戻して戻ってきたらもう一度通知する', afterFirst === 1 && posted.length === 2);

// 動画が切り替わったら新しい動画でも知らせる
posted = [];
currentId = 'G';
player = fakePlayer({ time: 99.8 });
checkNearEnd();
currentId = 'H';
player = fakePlayer({ time: 199.8, duration: 200 });
checkNearEnd();
check('次の動画でも通知する', posted.length === 2 && posted[1].v === 'H');

// 読み込み前・エラー時でも落ちない
posted = [];
player = null;
checkNearEnd();
check('プレイヤーが無くても落ちない', posted.length === 0);

console.log(failures === 0 ? '\nすべて通りました' : `\n${failures} 件failed`);
process.exit(failures === 0 ? 0 : 1);
