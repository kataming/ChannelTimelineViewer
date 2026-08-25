# -*- coding: utf-8 -*-
"""操作マニュアルに載せる画面写真を作る（iPhone / Android・言語ごと）。

マニュアルは章ごとに「その章で使う画面」を1枚だけ添える。イラストは描かず、
実機・シミュレーターで撮った本物の画面を使う（説明と食い違わないため）。

入力:
  iPhone  build/screenshots-site/<撮影言語>/NN-*.png   （iOS Screenshots の artifact）
          docs/AppStore/screenshots/<撮影言語>/04-player-device.png（実機で撮った再生画面）
  Android docs/PlayStore/screenshots/<Playのロケール>/NN-*.png（リポジトリ内）

出力:
  site/public/manual/<ios|android>/<サイトの言語>/<章のid>.webp （幅400px）
  site/src/i18n/manual/images.js                                （どれが用意できたかの一覧）

使い方:
    python scripts/prepare_manual_images.py

撮り直しの手順は docs/screenshot-production-guide.md を参照。
"""
import io
import json
import os
import re
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, 'site', 'public', 'manual')
MANIFEST = os.path.join(ROOT, 'site', 'src', 'i18n', 'manual', 'images.js')

WIDTH = 400          # 表示は200〜260pxなので、その倍を用意する
QUALITY = 72

# サイトの言語 → 撮影時の言語コード / Play のロケール
IOS_LANG = {'en': 'en', 'ja': 'ja', 'zh': 'zh-Hans', 'es': 'es', 'de': 'de', 'fr': 'fr', 'ko': 'ko'}
PLAY_LANG = {'en': 'en-US', 'ja': 'ja-JP', 'zh': 'zh-CN', 'es': 'es-ES', 'de': 'de-DE',
             'fr': 'fr-FR', 'ko': 'ko-KR'}

# iPhone の撮影ぶんの置き場（前の方から探す）。artifact をそのまま展開した場所も見る。
IOS_SRC_DIRS = [os.path.join(ROOT, 'build', 'screenshots-site'),
                os.path.join(ROOT, 'build', 'shots-dl')]
IOS_PLAYER = os.path.join(ROOT, 'docs', 'AppStore', 'screenshots')
PLAY_SRC = os.path.join(ROOT, 'docs', 'PlayStore', 'screenshots')

# 章のid → その章に添える画面。
#   ('num', '02')        撮影ファイルの先頭2桁で選ぶ（iPhone）
#   ('player', None)     実機で撮った再生画面（iPhone）
#   ('name', '02-list')  ファイル名で選ぶ（Android）
#   crop=(上, 下)        画像の一部だけを使う（割合）。同じ画面を別の章で使い分けるため。
CHAPTERS = {
    'ios': [
        ('add', ('num', '01'), None),
        ('list', ('num', '02'), None),
        ('play', ('player', None), (0.0, 0.62)),      # プレイヤーと自動再生トグルのあたり
        ('tools', ('player', None), (0.45, 1.0)),     # 移動ボタン・YouTubeで開く・メモ
        ('pro', ('name', 'iap-review-pro'), None),
        ('limits', ('num', '06'), None),
    ],
    'android': [
        ('add', ('name', '01-home'), None),
        ('list', ('name', '02-list'), None),
        ('play', ('name', '03-player'), None),
        ('tools', ('name', '04-player-controls'), None),
    ],
}


def find(folder, kind, key):
    """撮影ファイルを探す。見つからなければ None。"""
    if not os.path.isdir(folder):
        return None
    for name in sorted(os.listdir(folder)):
        if not name.lower().endswith('.png'):
            continue
        if kind == 'num' and re.match(r'^%s\D' % key, name):
            return os.path.join(folder, name)
        if kind == 'name' and name.startswith(key):
            return os.path.join(folder, name)
    return None


def source_for(platform, site_lang, spec):
    kind, key = spec
    if platform == 'android':
        return find(os.path.join(PLAY_SRC, PLAY_LANG[site_lang]), kind, key)
    shoot = IOS_LANG[site_lang]
    if kind == 'player':
        path = os.path.join(IOS_PLAYER, shoot, '04-player-device.png')
        return path if os.path.isfile(path) else None
    for base in IOS_SRC_DIRS:
        hit = find(os.path.join(base, shoot), kind, key)
        if hit:
            return hit
    return None


def convert(src, dst, crop):
    im = Image.open(src).convert('RGB')
    if crop:
        top, bottom = crop
        im = im.crop((0, int(im.height * top), im.width, int(im.height * bottom)))
    height = round(im.height * WIDTH / im.width)
    im = im.resize((WIDTH, height), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, 'WEBP', quality=QUALITY, method=6)
    return os.path.getsize(dst)


def main():
    available = {'ios': {}, 'android': {}}
    total = 0
    missing = []
    for platform, chapters in CHAPTERS.items():
        for site_lang in sorted(IOS_LANG):
            got = []
            for chapter_id, spec, crop in chapters:
                src = source_for(platform, site_lang, spec)
                if not src:
                    missing.append('%s/%s/%s' % (platform, site_lang, chapter_id))
                    continue
                dst = os.path.join(OUT_ROOT, platform, site_lang, '%s.webp' % chapter_id)
                total += convert(src, dst, crop)
                got.append(chapter_id)
            if got:
                available[platform][site_lang] = got
            print('  %-8s %-3s %s' % (platform, site_lang, ', '.join(got) or '（なし）'))

    if not available['ios'].get('en'):
        sys.stderr.write('英語（iPhone）が作れませんでした。フォールバック先が無くなるので中止します。\n')
        return 1

    body = (
        '// マニュアルに載せる画面写真の一覧。\n'
        '// scripts/prepare_manual_images.py が生成する。手で書き換えない。\n'
        '// 値は「その言語・その機種で用意できた章のid」。\n'
        'export const MANUAL_IMAGES = %s;\n'
        '\n'
        "/** その章の画面写真のパス。その言語で用意が無ければ null。 */\n"
        "// 別の言語の画面は出さない（説明と画面の文字が食い違って混乱するため）。\n"
        'export function manualImage(platform, lang, chapterId) {\n'
        '  const byLang = MANUAL_IMAGES[platform] || {};\n'
        '  const has = (byLang[lang] || []).includes(chapterId);\n'
        '  return has ? `/manual/${platform}/${lang}/${chapterId}.webp` : null;\n'
        '}\n'
    ) % json.dumps(available, indent=2, sort_keys=True)
    io.open(MANIFEST, 'w', encoding='utf-8', newline='\n').write(body)

    if missing:
        print('\n用意できなかったもの（その章は画像なしで出る）:')
        for item in missing:
            print('  -', item)
    print('\n合計 %.1f MB / 一覧: %s' % (total / 1024 / 1024, os.path.relpath(MANIFEST, ROOT)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
