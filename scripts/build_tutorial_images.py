# -*- coding: utf-8 -*-
"""チュートリアル用のスクリーンショットを、素材から加工して両OSのアセットへ書き出す。

素材（`docs/tutorial/raw/`）は **Android エミュレータの実機画面**をそのまま撮ったもの。
YouTube アプリと Android のシステム共有シートの本物で、UI を作り替えてはいない。

このスクリプトがやること:
  1. 上のステータスバー（時刻・電波）を落とす … 撮影日時が写ると古く見えるため
  2. 説明に要る範囲だけを切り出す
  3. 押す場所に**枠と矢印**を描く（色は控えめの1色だけ）
  4. 端末の幅に合わせて縮小し、PNG（減色）で書き出す

⚠️ やらないこと（規約・表示上の理由）:
  - YouTube / NASA の画面そのものの改変（文字やロゴの描き替え・合成）
  - 公式提携を思わせる装飾
  - 画像への説明文の焼き込み（文言はアプリ側のローカライズで出す。同じ画像を7言語で使う）

使い方:
    python scripts/build_tutorial_images.py
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "tutorial" / "raw"
ANDROID_OUT = ROOT / "android" / "app" / "src" / "main" / "res" / "drawable-nodpi"
IOS_OUT = ROOT / "Resources" / "Assets.xcassets"

# 画面の横幅（素材は 1080x2400）。書き出し幅はチュートリアルの表示領域に合わせる。
OUT_WIDTH = 720

# ハイライトの色。YouTube の赤や NASA の色と紛れないよう、アプリの緑を使う。
HIGHLIGHT = (46, 125, 50, 255)


def load(name: str) -> Image.Image:
    path = RAW / name
    if not path.exists():
        raise SystemExit(f"素材がありません: {path}\n"
                         f"取り直しの手順は docs/onboarding/CHANNEL_ADD_TUTORIAL.md を参照。")
    return Image.open(path).convert("RGB")


def crop(img: Image.Image, top: int, bottom: int) -> Image.Image:
    """上下を**元画像のピクセル**で切り出す（素材は 1080x2400）。

    割合ではなくピクセルにしているのは、素材を撮り直したときに
    「どこを切っているか」を画面の座標そのままで直せるようにするため。
    """
    return img.crop((0, top, img.width, bottom))


def rounded_box(img: Image.Image, box, width: int = 8, radius: int = 28) -> Image.Image:
    """押す場所を角丸の枠で囲む。塗りつぶさないので下の画面は隠れない。"""
    out = img.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    draw.rounded_rectangle(box, radius=radius, outline=HIGHLIGHT, width=width)
    return out


def arrow(img: Image.Image, start, end, width: int = 9, head: int = 26) -> Image.Image:
    """枠へ向かう矢印。装飾は最小限にする。"""
    out = img.copy()
    draw = ImageDraw.Draw(out, "RGBA")
    draw.line([start, end], fill=HIGHLIGHT, width=width)
    x0, y0 = start
    x1, y1 = end
    dx, dy = x1 - x0, y1 - y0
    length = max(1.0, (dx * dx + dy * dy) ** 0.5)
    ux, uy = dx / length, dy / length
    # 進行方向に対する左右へ開いた三角形。
    left = (x1 - ux * head - uy * head * 0.55, y1 - uy * head + ux * head * 0.55)
    right = (x1 - ux * head + uy * head * 0.55, y1 - uy * head - ux * head * 0.55)
    draw.polygon([(x1, y1), left, right], fill=HIGHLIGHT)
    return out


def finish(img: Image.Image) -> Image.Image:
    """表示幅に縮小する。文字が潰れないよう高品質な縮小を使う。"""
    ratio = OUT_WIDTH / img.width
    return img.resize((OUT_WIDTH, int(img.height * ratio)), Image.LANCZOS)


def save(img: Image.Image, stem: str) -> None:
    """Android の drawable と iOS の imageset へ同じ絵を書き出す。"""
    ANDROID_OUT.mkdir(parents=True, exist_ok=True)
    # 減色して容量を落とす（写真ではなく画面なので、256色でも見た目が崩れない）。
    small = img.convert("P", palette=Image.ADAPTIVE, colors=256)

    a_path = ANDROID_OUT / f"{stem}.png"
    small.save(a_path, optimize=True)

    imageset = IOS_OUT / f"{stem}.imageset"
    imageset.mkdir(parents=True, exist_ok=True)
    small.save(imageset / f"{stem}.png", optimize=True)
    (imageset / "Contents.json").write_text(
        '{\n'
        '  "images" : [\n'
        f'    {{ "filename" : "{stem}.png", "idiom" : "universal" }}\n'
        '  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n'
        '}\n',
        encoding="utf-8",
    )
    print(f"  {stem}.png  {img.width}x{img.height}  "
          f"Android {a_path.stat().st_size // 1024}KB")


def main() -> int:
    print("チュートリアル画像を作ります（素材:", RAW, "）")

    # 座標はすべて素材（1080x2400）の実ピクセル。撮り直したらここだけ直す。

    # --- STEP 1: YouTube でチャンネルを開いた画面 ---------------------------
    # チャンネル名・ハンドル・登録者数・「Subscribe」までが入れば、
    # 「チャンネルのページを開いている」と分かる。ステータスバーは落とす。
    step1 = crop(load("android-channel.png"), 130, 1250)
    save(finish(step1), "tutorial_youtube_channel")

    # --- STEP 2: メニューの中の「共有」 -------------------------------------
    # メニューが開いている下側だけを使い、「Share」の行を枠で囲う。
    # 元画像での Share 行は y=1930〜2040 あたり。
    src = load("android-share-menu.png")
    top = 1800
    step2 = crop(src, top, 2340)
    step2 = rounded_box(step2, (40, 1925 - top, step2.width - 40, 2045 - top), radius=24)
    step2 = arrow(step2, (900, 2210 - top), (900, 2060 - top))
    save(finish(step2), "tutorial_youtube_share")

    # --- STEP 3(Android): システム共有シートの中の本アプリ ------------------
    # アプリのアイコンが並ぶ段。本アプリは左から2番目（x=270〜390、y=2080〜2300）。
    src = load("android-share-sheet.png")
    top = 1985
    step3 = crop(src, top, 2375)
    # アイコンと2行の名前をまとめて囲む（どちらかが切れると何を押すのか分からない）。
    step3 = rounded_box(step3, (232, 2040 - top, 440, 2330 - top), radius=24)
    save(finish(step3), "tutorial_android_share_sheet")

    print("完了。iOS の共有シート画像は未取得（docs/onboarding/CHANNEL_ADD_TUTORIAL.md 参照）。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
