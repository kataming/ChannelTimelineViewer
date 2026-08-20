# -*- coding: utf-8 -*-
"""Google Play に必要な画像（アプリアイコン 512×512 / フィーチャーグラフィック 1024×500）を作る。

Play Console は次を必須にしている:
  - アプリアイコン: 512×512 PNG
  - フィーチャーグラフィック: 1024×500 PNG または JPG（ストアの一番上に出る横長画像）

意匠はアプリのランチャーアイコン（`res/drawable/ic_launcher_foreground.xml`）と公式サイトの
ファビコンに合わせる: 緑地に「一覧（3本の横棒）＋再生の三角」。

使い方:
    python scripts/make_play_graphics.py
出力:
    docs/PlayStore/graphics/icon-512.png
    docs/PlayStore/graphics/feature-1024x500.png
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "PlayStore" / "graphics"

GREEN = (23, 145, 74)        # 公式サイト・ランチャーアイコンと同じ緑
GREEN_DARK = (12, 92, 47)
WHITE = (255, 255, 255)

APP_NAME = "Channel Timeline Viewer"
TAGLINE = "Watch a channel from its very first video"


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    """Windows に入っている一般的なフォントを使う。無ければ既定にする。"""
    candidates = [
        "C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf",
        "C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf",
    ]
    for path in candidates:
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_mark(draw: ImageDraw.ImageDraw, x: float, y: float, size: float) -> None:
    """一覧＋再生のマーク。左上を (x, y)、一辺 size の正方形に収める。"""
    def px(value: float) -> float:
        return x + size * value

    def py(value: float) -> float:
        return y + size * value

    bar_height = size * 0.09
    radius = bar_height / 2
    for index, width in enumerate((0.56, 0.43, 0.30)):
        top = py(0.18 + index * 0.27)
        draw.rounded_rectangle(
            [px(0.06), top, px(0.06 + width), top + bar_height],
            radius=radius,
            fill=WHITE,
        )
    # 再生の三角
    draw.polygon(
        [(px(0.70), py(0.30)), (px(0.94), py(0.44)), (px(0.70), py(0.58))],
        fill=WHITE,
    )


def make_icon() -> Path:
    size = 512
    image = Image.new("RGB", (size, size), GREEN)
    draw = ImageDraw.Draw(image)
    # 角丸は Play 側で自動的にかかるので、ここでは塗りとマークだけ置く。
    draw_mark(draw, size * 0.16, size * 0.18, size * 0.68)
    path = OUT_DIR / "icon-512.png"
    image.save(path)
    return path


def make_feature_graphic() -> Path:
    width, height = 1024, 500
    image = Image.new("RGB", (width, height), GREEN)
    draw = ImageDraw.Draw(image)

    # 斜めのグラデーション風（単純な帯を重ねるだけ。派手にしない）
    for index in range(height):
        ratio = index / height
        color = (
            int(GREEN[0] + (GREEN_DARK[0] - GREEN[0]) * ratio),
            int(GREEN[1] + (GREEN_DARK[1] - GREEN[1]) * ratio),
            int(GREEN[2] + (GREEN_DARK[2] - GREEN[2]) * ratio),
        )
        draw.line([(0, index), (width, index)], fill=color)

    draw_mark(draw, 70, 150, 200)

    draw.text((320, 180), APP_NAME, font=font(58), fill=WHITE)
    draw.text((322, 260), TAGLINE, font=font(30, bold=False), fill=(226, 240, 231))

    path = OUT_DIR / "feature-1024x500.png"
    image.save(path)
    return path


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in (make_icon(), make_feature_graphic()):
        with Image.open(path) as image:
            print(f"  書き出し: {path.relative_to(ROOT)}（{image.size[0]}×{image.size[1]}）")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
