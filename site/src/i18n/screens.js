// どの言語のスクリーンショットが site/public/screens/ にあるか。
// scripts/prepare_site_screenshots.py が生成する。手で書き換えない。
// 値は「載せられるカットの番号」（1〜6・shots[] の並びに対応）。
export const SCREEN_SHOTS = {
  "de": [
    1,
    2,
    3,
    4,
    5,
    6
  ],
  "en": [
    1,
    2,
    3,
    4,
    6
  ],
  "es": [
    1,
    2,
    3,
    4,
    5,
    6
  ],
  "fr": [
    1,
    2,
    3,
    4,
    5,
    6
  ],
  "ja": [
    1,
    2,
    3,
    4,
    5,
    6
  ],
  "ko": [
    1,
    2,
    3,
    5,
    6
  ],
  "zh": [
    1,
    2,
    3,
    4,
    5,
    6
  ]
};

/** その言語のスクリーンショット。撮れていない言語は英語版を使う。 */
export function screensFor(code) {
  const use = SCREEN_SHOTS[code] ? code : 'en';
  return SCREEN_SHOTS[use].map((n) => ({
    index: n - 1,
    src: `/screens/${use}/${String(n).padStart(2, '0')}.webp`,
  }));
}
