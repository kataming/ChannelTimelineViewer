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
ANDROID_RAW = ROOT / "docs" / "tutorial" / "ssa"
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

# 手順の番号。iOS は 1〜4（4＝通知）、Android は 1〜3 と 5（一覧が直接開くので4が無い）。
# 画面に出す通し番号は別で振り直す（アプリ側で 1/4・1/3 のように数える）。
IOS_STEP_FILES = (1, 2, 3, 4, 5)
ANDROID_STEP_FILES = (1, 2, 3, 5)

# 本アプリのアイコンの緑。共有シートの中でこの色はほぼ本アプリだけなので、
# **色を手がかりに位置を見つける**（並び順は言語で変わるため、座標では追えない）。
APP_ICON_GREEN = (23, 145, 74)

OUT_WIDTH = 640
# ハイライトの色。YouTube の赤や NASA の色と紛れないよう、アプリの緑を使う。
HIGHLIGHT = (46, 125, 50, 255)

# --- iOS の素材（実機 739x1600）で、どこを切り出してどこを囲むか -------------
# すべて素材のピクセル座標。7言語とも同じ機種・同じ流れで撮ってあるので位置は共通。
# 撮り直したらここだけ直す。
IOS_STEPS = {
    1: dict(crop=(628, 890), box=(505, 780, 585, 850)),
    2: dict(crop=(900, 1240), box=(575, 1045, 692, 1190)),
    3: dict(crop=(600, 890), box=(556, 618, 692, 872)),
    4: dict(crop=(60, 240), box=(14, 78, 726, 222)),
    # 5 だけはシミュレーターで撮ったもので、大きさが違う（1320x2868）。
    # ピクセルではなく割合で指定する。押す場所は無いので囲まない。
    5: dict(crop=None, ratio=(0.03, 0.62), box=None),
}


def load(path: Path) -> Image.Image:
    if not path.exists():
        raise SystemExit(f"素材がありません: {path}\n"
                         f"取り直しの手順は docs/onboarding/CHANNEL_ADD_TUTORIAL.md を参照。")
    return Image.open(path).convert("RGB")


def find_app_icon(img: Image.Image, tolerance: int = 18) -> tuple[int, int, int, int] | None:
    """共有シートの中から本アプリのアイコンを、色を手がかりに探す。

    共有先の並び順は**言語で変わる**（アプリ名の並び替えが言語依存のため）。
    座標で決め打ちにできないので、アイコンの緑を探して位置を決める。

    ⚠️ 似た緑を持つアプリが混ざる（CamScanner の帯は (0,199,162)）。
       そこで許容差を狭くしたうえで、**いちばん大きな塊だけ**を採る。
       見つからなければ None を返し、呼び出し側は枠を描かずに済ませる。
    """
    tr, tg, tb = APP_ICON_GREEN
    pixels = img.load()
    hits = []
    for y in range(0, img.height, 2):
        for x in range(0, img.width, 2):
            r, g, b = pixels[x, y][:3]
            if (abs(r - tr) < tolerance and abs(g - tg) < tolerance
                    and abs(b - tb) < tolerance):
                hits.append((x, y))
    if len(hits) < 60:
        return None

    # 近い点どうしをまとめる（縦横に離れていれば別のアプリのアイコン）。
    gap = max(12, img.width // 40)
    groups: list[list[tuple[int, int]]] = []
    for point in sorted(hits):
        for group in groups:
            gx0 = min(p[0] for p in group)
            gx1 = max(p[0] for p in group)
            gy0 = min(p[1] for p in group)
            gy1 = max(p[1] for p in group)
            if gx0 - gap <= point[0] <= gx1 + gap and gy0 - gap <= point[1] <= gy1 + gap:
                group.append(point)
                break
        else:
            groups.append([point])

    biggest = max(groups, key=len)
    if len(biggest) < 60:
        return None
    xs = [p[0] for p in biggest]
    ys = [p[1] for p in biggest]
    return min(xs), min(ys), max(xs), max(ys)


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
    print("== iOS（実機とシミュレーターの素材から）==")
    total = 0
    for lang, (jp_name, _) in LANGUAGES.items():
        for step in IOS_STEP_FILES:
            spec = IOS_STEPS[step]
            # 実機で撮った 1〜4 は .jpg、5 はシミュレーターから取り込んだ .jpg。
            src = load(IOS_RAW / f"{jp_name}{step}.jpg")
            if spec["crop"]:
                top, bottom = spec["crop"]
            else:
                top, bottom = (int(src.height * v) for v in spec["ratio"])
            img = src.crop((0, top, src.width, bottom))
            if spec["box"]:
                x0, y0, x1, y1 = spec["box"]
                img = rounded_box(img, (x0, y0 - top, x1, y1 - top))
            total += save_ios(finish(img), step, lang)
        print(f"  {lang}: {len(IOS_STEP_FILES)}枚")
    print(f"  iOS 合計 {total // 1024}KB")
    return total


def build_android() -> int:
    """実機で撮ってもらった素材（docs/tutorial/ssa/）から作る。

    手順3だけは、アプリの位置が言語で変わるので**アイコンを探して**枠を描く。
    """
    print("== Android（実機の素材から）==")
    total = 0
    missing = []
    for lang, (jp_name, qualifier) in LANGUAGES.items():
        made = 0
        for index, step in enumerate(ANDROID_STEP_FILES, start=1):
            src_path = ANDROID_RAW / f"{jp_name}{step}a.png"
            if not src_path.exists():
                missing.append(src_path.name)
                continue
            src = load(src_path)
            (top, bottom), box = to_pixels(ANDROID_STEPS[step], src.width, src.height)
            if step == 3:
                # 共有先の一覧。アイコンを探して、その下の名前まで含めて囲む。
                found = find_app_icon(src)
                box = None
                if found:
                    x0, y0, x1, y1 = found
                    pad = int(src.width * 0.018)
                    label = int(src.height * 0.045)   # アイコンの下にある名前のぶん
                    box = (x0 - pad, y0 - pad, x1 + pad, y1 + label)
                    # 囲む場所が見えるように、切り出す範囲をそこへ寄せる。
                    top = max(0, y0 - int(src.height * 0.055))
                    bottom = min(src.height, y1 + int(src.height * 0.085))
                else:
                    print(f"    ⚠️ {lang}: 共有シートで本アプリを見つけられず、枠なしで出す")
            img = src.crop((0, top, src.width, bottom))
            if box:
                x0, y0, x1, y1 = box
                img = rounded_box(img, (x0, y0 - top, x1, y1 - top))
            total += save_android(finish(img), index, qualifier)
            made += 1
        print(f"  {lang}: {made}枚")
    if missing:
        print(f"  ⚠️ 未取得の素材 {len(missing)} 件（例: {missing[0]}）")
    print(f"  Android 合計 {total // 1024}KB")
    return total


# --- Android の素材の切り出し位置 -------------------------------------------
# iOS と違い、Android は**実機の機種が決まっていない**（撮る人の端末による）ので、
# ピクセルではなく**画面に対する割合**で持つ。0.0 が上端、1.0 が下端。
# これなら 1080x2400 でも 1440x3120 でも同じ指定で切り出せる。
#
# 撮る流れは iOS とそろえる（docs/onboarding/CHANNEL_ADD_TUTORIAL.md 第11節）:
#   1 動画ページ（共有ボタンが見える） 2 YouTube の共有シート
#   3 Android の共有シート            4 本アプリが開いた一覧
ANDROID_STEPS = {
    # 1: 動画ページ。タイトルと操作の並びが入り、**共有ボタン（↪）**を囲む。
    1: dict(crop=(0.30, 0.46), box=(0.695, 0.405, 0.785, 0.445)),
    # 2: YouTube 自身の共有シート。ここで「その他」を押さないと共有先の一覧が出ないので囲む。
    #    横に4つ並ぶうちの右端。並びは言語が変わっても同じ。
    2: dict(crop=(0.46, 0.70), box=(0.772, 0.566, 0.916, 0.664)),
    # 3: Android の共有シート。枠は find_app_icon が見つけた位置に描く（ここの値は使わない）。
    3: dict(crop=(0.0, 1.0), box=None),
    # 5: 本アプリが開いた一覧。上部バー・進捗・最初の数本が入る高さ。
    5: dict(crop=(0.02, 0.62), box=None),
}


def to_pixels(spec: dict, width: int, height: int) -> tuple[tuple[int, int], tuple | None]:
    """割合で書いた指定を、その画像の実ピクセルに直す。"""
    top, bottom = (int(height * v) for v in spec["crop"])
    box = None
    if spec["box"]:
        x0, y0, x1, y1 = spec["box"]
        box = (int(width * x0), int(height * y0), int(width * x1), int(height * y1))
    return (top, bottom), box


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
