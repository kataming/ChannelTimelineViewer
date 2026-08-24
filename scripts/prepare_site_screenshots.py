# -*- coding: utf-8 -*-
"""App Store 提出用に撮ったスクリーンショットを、公式サイト用に縮小して配置する。

使い方:
    python scripts/prepare_site_screenshots.py --src build/screenshots-site

`--src` の下は「言語ごとのフォルダ」を想定する（iOS Screenshots ワークフローの
artifact `app-store-screenshots-<言語>` を展開したもの）。ファイル名は
`04-player-with-memo_0_XXXX.png` のように接尾辞が付いていてもよい（先頭2桁で判別する）。

    build/screenshots-site/
      en/01-home-favorites....png 02-....png ...
      ja/...
      zh-Hans/...

再生画面（4枚目）だけは、CI のシミュレーターだと YouTube 側に
「Sign in to confirm you're not a bot」を出されることがあるので、
リポジトリに入っている `docs/AppStore/screenshots/<言語>/04-player-device.png`
を優先して使う。

出力:
    site/public/screens/<サイトの言語コード>/NN.webp   （幅 440px・WebP、NN は 01〜06）
    site/src/i18n/screens.js                          （言語ごとに「揃った番号」の一覧）

撮影が一部失敗した言語は、その番号だけ載せない。枚数が少なすぎる言語は
サイト側で英語版にフォールバックする。
"""
import argparse
import io
import json
import os
import re
import sys

from PIL import Image

# サイトに載せるカット（番号は撮影ファイルの先頭2桁）。00（URL入力）は使わない。
SHOT_NUMBERS = ['01', '02', '03', '04', '05', '06']

# 撮影時の言語コード → サイトの言語コード
LANG_MAP = {
    'en': 'en',
    'ja': 'ja',
    'zh-Hans': 'zh',
    'zh': 'zh',
    'es': 'es',
    'de': 'de',
    'fr': 'fr',
    'ko': 'ko',
}

# 再生画面はここにある差し替え用を優先する（撮影時の言語コードのフォルダ名）。
PLAYER_OVERRIDE = os.path.join('docs', 'AppStore', 'screenshots', '{lang}', '04-player-device.png')

# これ未満しか揃わなかった言語は、サイト側で英語版に置き換える。
MIN_SHOTS = 4

WIDTH = 440          # 表示は 220px 前後なので、その2倍を用意する
QUALITY = 72

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, 'site', 'public', 'screens')
MANIFEST = os.path.join(ROOT, 'site', 'src', 'i18n', 'screens.js')


def shots_in(folder):
    """フォルダ内の PNG を「先頭2桁 → パス」で返す。ERROR- で始まるものは無視する。"""
    found = {}
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith('.png'):
            continue
        m = re.match(r'^(\d{2})', name)
        if not m:
            continue
        found.setdefault(m.group(1), os.path.join(folder, name))
    return found


def convert(src_path, dst_path):
    im = Image.open(src_path).convert('RGB')
    height = round(im.height * WIDTH / im.width)
    im = im.resize((WIDTH, height), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst_path), exist_ok=True)
    im.save(dst_path, 'WEBP', quality=QUALITY, method=6)
    return os.path.getsize(dst_path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', required=True, help='撮影した PNG の置き場（言語フォルダの親）')
    args = ap.parse_args()

    src_root = args.src if os.path.isabs(args.src) else os.path.join(ROOT, args.src)
    if not os.path.isdir(src_root):
        sys.stderr.write('見つかりません: %s\n' % src_root)
        return 1

    folders = {}
    for name in sorted(os.listdir(src_root)):
        path = os.path.join(src_root, name)
        if os.path.isdir(path) and name in LANG_MAP:
            folders[name] = path
    if not folders:
        sys.stderr.write('言語フォルダが見つかりません: %s\n' % src_root)
        return 1

    available = {}
    total = 0
    for orig_lang in sorted(folders):
        code = LANG_MAP[orig_lang]
        found = shots_in(folders[orig_lang])

        # 再生画面は差し替え用があればそちらを使う（bot チェック画面を載せないため）
        override = os.path.join(ROOT, PLAYER_OVERRIDE.format(lang=orig_lang))
        if os.path.isfile(override):
            found['04'] = override
        elif '04' in found:
            # 差し替えが無い言語で撮影ぶんしか無い場合は、載せない方が安全
            del found['04']

        got = []
        for i, num in enumerate(SHOT_NUMBERS, start=1):
            if num not in found:
                continue
            dst = os.path.join(OUT_ROOT, code, '%02d.webp' % i)
            total += convert(found[num], dst)
            got.append(i)

        if len(got) < MIN_SHOTS:
            print('  %s: %d 枚しか揃わないので使いません' % (code, len(got)))
            continue
        available[code] = got
        print('  %s: %s' % (code, ', '.join('%02d' % n for n in got)))

    if 'en' not in available:
        sys.stderr.write('英語版が揃っていません（フォールバック先が作れません）\n')
        return 1

    body = (
        '// どの言語のスクリーンショットが site/public/screens/ にあるか。\n'
        '// scripts/prepare_site_screenshots.py が生成する。手で書き換えない。\n'
        '// 値は「載せられるカットの番号」（1〜6・shots[] の並びに対応）。\n'
        'export const SCREEN_SHOTS = %s;\n'
        '\n'
        "/** その言語のスクリーンショット。撮れていない言語は英語版を使う。 */\n"
        'export function screensFor(code) {\n'
        "  const use = SCREEN_SHOTS[code] ? code : 'en';\n"
        '  return SCREEN_SHOTS[use].map((n) => ({\n'
        '    index: n - 1,\n'
        "    src: `/screens/${use}/${String(n).padStart(2, '0')}.webp`,\n"
        '  }));\n'
        '}\n'
    ) % json.dumps(available, indent=2, sort_keys=True)
    io.open(MANIFEST, 'w', encoding='utf-8', newline='\n').write(body)

    print('合計 %.1f MB / マニフェスト: %s' % (total / 1024 / 1024, os.path.relpath(MANIFEST, ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
