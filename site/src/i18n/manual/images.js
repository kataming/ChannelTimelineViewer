// マニュアルに載せる画面写真の一覧。
// scripts/prepare_manual_images.py が生成する。手で書き換えない。
// 値は「その言語・その機種で用意できた章のid」。
export const MANUAL_IMAGES = {
  "android": {
    "de": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "en": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "es": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "fr": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "ja": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "ko": [
      "add",
      "list",
      "play",
      "tools"
    ],
    "zh": [
      "add",
      "list",
      "play",
      "tools"
    ]
  },
  "ios": {
    "de": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ],
    "en": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ],
    "es": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ],
    "fr": [
      "add",
      "list",
      "play",
      "tools",
      "limits"
    ],
    "ja": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ],
    "ko": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ],
    "zh": [
      "add",
      "list",
      "play",
      "tools",
      "pro",
      "limits"
    ]
  }
};

/** その章の画面写真のパス。その言語で用意が無ければ null。 */
// 別の言語の画面は出さない（説明と画面の文字が食い違って混乱するため）。
export function manualImage(platform, lang, chapterId) {
  const byLang = MANUAL_IMAGES[platform] || {};
  const has = (byLang[lang] || []).includes(chapterId);
  return has ? `/manual/${platform}/${lang}/${chapterId}.webp` : null;
}
