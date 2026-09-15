# -*- coding: utf-8 -*-
"""チュートリアル用のスクリーンショットを、素材から加工して両OSのアセットへ書き出す。

手順は**4つ**。iOS と Android で受け取り方が違うので、素材も画面も別に持つ。

  1. YouTube で動画（またはチャンネル）を開く … 共有ボタンが見える画面
  2. 共有をタップ                             … YouTube 自身の共有シート
  3. 共有先から Channel Timeline Viewer を選ぶ … OS の共有シート
  4. 受け取る                                  … iOS は通知をタップ／Android はそのまま一覧

**7言語ぶん**を言語ごとに用意する（画面の中の文字がその言語で出ている必要があるため）。
説明文は画像に焼き込まない。文言はアプリ側のローカライズで出す。

素材の置き場所:
  docs/tutorial/ss/<言語名><番号>.jpg   … iOS（実機で撮影。7言語 × 4枚）
  docs/tutorial/raw/android-<lang>-<n>.png … Android（エミュレータで撮影）

書き出し先:
  Android … res/drawable-nodpi/tutorial_step<n>.png（英語＝既定）
            res/drawable-<lang>-nodpi/tutorial_step<n>.png（各言語）
            ※ Android が端末の言語で自動的に選ぶ。コード側は R.drawable.tutorial_step1 だけ見る
  iOS     … Resources/Assets.xcassets/tutorial_step<n>_<lang>.imageset/
            ※ asset catalog は言語で切り替わらないので、コード側で名前を組み立てる

⚠️ やらないこと（規約・表示上の理由）:
  - YouTube / NASA の画面そのものの改変（文字やロゴの描き替え・合成）
  - 公式提携を思わせる装飾
  - 作り物の共有シートを描くこと

使い方:
    python scripts/build_tutorial_images.py            # 全部
    python scripts/build_tutorial_images.py --ios      # iOS だけ
    python scripts/build_tutorial_images.py --android  # Android だけ
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
IOS_RAW = ROOT / "docs" / "tutorial" / "ss"
ANDROID_RAW = ROOT / "docs" / "tutorial" / "raw"
ANDROID_RES = ROOT / "android" / "app" / "src" / "main" / "res"
IOS_ASSETS = ROOT / "Resources" / "Assets.xcassets"

# 言語。キーは strings.json と同じ綴り、値は（素材の日本語名, Android のリソース修飾子）。
# 既定（修飾子なし）は英語。端末が未対応の言語なら英語の画像が出る＝アプリの文言と揃う。
LANGUAGES = {
    "en": ("英語", None),
    "ja": ("日本語", "ja"),
    "zh-Hans": ("中国語", "zh-rCN"),
    "es": ("スペイン語", "es"),
    "de": ("ドイツ語", "de"),
    "fr": ("フランス語", "fr"),
    "ko": ("韓国語", "ko"),
}

OUT_WIDTH = 640
# ハイライトの色。YouTube の赤や NASA の色と紛れないよう、アプリの緑を使う。
HIGHLIGHT = (46, 125, 50, 255)

# --- iOS の素材（実機 739x1600）で、どこを切り出してどこを囲むか -------------
# すべて素材のピクセル座標。7言語とも同じ機種・同じ流れで撮ってあるので位置は共通。
# 撮り直したらここだけ直す。
IOS_STEPS = {
    1: dict(crop=(628, 890), box=(505, 780, 585, 850), arrow=None),
    2: dict(crop=(900, 1240), box=(575, 1045, 692, 1190), arrow=None),
    3: dict(crop=(600, 890), box=(556, 618, 692, 872), arrow=None),
    4: dict(crop=(60, 240), box=(14, 78, 726, 222), arrow=None),
}


def load(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"素材がありません: {path}\n"
                         f"取り直しの手順は docs/onboarding/CHANNEL_ADD_TUTORIAL.md を参照。")
    return Image.open(path).convert("RGB")


def rounded_box(img: Image.Image, box, width: int = 6, radius: int = 18) -> Image.Image:
    """押す場所を角丸の枠で囲む。塗りつぶさないので下の画面は隠れない。"""
    out = img.copy()
    ImageDraw.Draw(out, "RGBA").rounded_rectangle(box, radius=radius,
                                                  outline=HIGHLIGHT, width=width)
    return out


def finish(img: Image.Image) -> Image.Image:
    ratio = OUT_WIDTH / img.width
    return img.resize((OUT_WIDTH, int(img.height * ratio)), Image.LANCZOS)


def save_android(img: Image.Image, step: int, qualifier: str | None) -> int:
    folder = ANDROID_RES / (f"drawable-{qualifier}-nodpi" if qualifier else "drawable-nodpi")
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"tutorial_step{step}.jpg"
    img.save(path, "JPEG", quality=82, optimize=True, progressive=True)
    return path.stat().st_size


def save_ios(img: Image.Image, step: int, lang: str) -> int:
    name = f"tutorial_step{step}_{lang.replace('-', '_')}"
    imageset = IOS_ASSETS / f"{name}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    path = imageset / f"{name}.jpg"
    img.save(path, "JPEG", quality=82, optimize=True, progressive=True)
    (imageset / "Contents.json").write_text(
        '{\n  "images" : [\n'
        f'    {{ "filename" : "{name}.jpg", "idiom" : "universal" }}\n'
        '  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n',
        encoding="utf-8")
    return path.stat().st_size


def build_ios() -> int:
    print("== iOS（実機の素材から）==")
    total = 0
    for lang, (jp_name, _) in LANGUAGES.items():
        for step, spec in IOS_STEPS.items():
            src = load(IOS_RAW / f"{jp_name}{step}.jpg")
            top, bottom = spec["crop"]
            img = src.crop((0, top, src.width, bottom))
            if spec["box"]:
                x0, y0, x1, y1 = spec["box"]
                img = rounded_box(img, (x0, y0 - top, x1, y1 - top))
            total += save_ios(finish(img), step, lang)
        print(f"  {lang}: 4枚")
    print(f"  iOS 合計 {total // 1024}KB")
    return total


def build_android() -> int:
    print("== Android（エミュレータの素材から）==")
    total = 0
    missing = []
    for lang, (_, qualifier) in LANGUAGES.items():
        for step in (1, 2, 3, 4):
            src_path = ANDROID_RAW / f"android-{lang}-{step}.png"
            if not src_path.exists():
                missing.append(src_path.name)
                continue
            src = load(src_path)
            spec = ANDROID_STEPS[step]
            top, bottom = spec["crop"]
            img = src.crop((0, top, src.width, bottom))
            if spec["box"]:
                x0, y0, x1, y1 = spec["box"]
                img = rounded_box(img, (x0, y0 - top, x1, y1 - top))
            total += save_android(finish(img), step, qualifier)
        print(f"  {lang}: {'4枚' if not missing else '素材待ち'}")
    if missing:
        print(f"  ⚠️ 未取得の素材 {len(missing)} 件（例: {missing[0]}）")
    print(f"  Android 合計 {total // 1024}KB")
    return total


# --- Android の素材（エミュレータ 1080x2400）の切り出し位置 -------------------
# 撮り方は docs/onboarding/CHANNEL_ADD_TUTORIAL.md の「素材を撮り直す」を参照。
ANDROID_STEPS = {
    # 1: チャンネルページの上部（名前・ハンドル・登録者数）。押す場所はまだ無い。
    1: dict(crop=(130, 1250), box=None),
    # 2: ⋮ のメニュー。先頭の「共有」を囲む。
    2: dict(crop=(1800, 2340), box=(40, 1925, 1040, 2045)),
    # 3: 共有シートのアイコン列。本アプリ（左から2番目）を囲む。
    3: dict(crop=(1985, 2375), box=(232, 2040, 440, 2330)),
    # 4: 開いた一覧。上部バー・進捗・最初の数本が入る高さにする
    #    （読み込み中の空白を写さないよう、行が始まるところまで下げる）。
    4: dict(crop=(130, 1750), box=None),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--ios", action="store_true")
    parser.add_argument("--android", action="store_true")
    args = parser.parse_args()
    both = not (args.ios or args.android)

    total = 0
    if both or args.ios:
        total += build_ios()
    if both or args.android:
        total += build_android()
    print(f"合計 {total // 1024}KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
