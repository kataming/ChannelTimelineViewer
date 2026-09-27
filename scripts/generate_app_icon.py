# -*- coding: utf-8 -*-
"""Channel Timeline Viewer の iOS アプリアイコン(1024x1024 PNG)を生成する。

2026-09-27 に、Android・Google Play・公式サイト・広告と同じ**緑の「一覧＋再生」**に揃えた。
それまでの iOS だけネイビーの「タイムライン」意匠は、8/18 以降に緑が正式な意匠になったあとも
差し替えられずに残っていた（App Store と iPhone のホーム画面だけ別のアイコンになっていた）。

**意匠は scripts/make_play_graphics.py の draw_mark() をそのまま使う**（Play のアイコン icon-512.png と
同じ比率・同じ緑）。ここで別に描かないこと — 別々に描くと、また iOS だけ違うアイコンになる。

docs/app-icon-requirements.md の要件:
  - 1024x1024 / PNG / sRGB / アルファなし(不透明) / 角丸なし(四角のまま。角丸は iOS がかける)
  - YouTube ロゴ・赤い再生ボタン・赤主体の配色・「Tube」文字は使わない（白い三角・緑背景）

出力: Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

実行: python scripts/generate_app_icon.py
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_play_graphics import GREEN, draw_mark  # noqa: E402  Play のアイコンと同じ意匠

SIZE = 1024
SS = 4  # スーパーサンプリング倍率（縁をなめらかにする）

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = (
    REPO_ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
)


def main() -> None:
    big = SIZE * SS
    image = Image.new("RGB", (big, big), GREEN)
    draw = ImageDraw.Draw(image)
    # make_play_graphics.make_icon() と同じ配置（左上 16%/18%・一辺 68%）
    draw_mark(draw, big * 0.16, big * 0.18, big * 0.68)
    out = image.resize((SIZE, SIZE), Image.LANCZOS).convert("RGB")
    out.save(OUT_PATH, format="PNG")
    print(f"書き出し: {OUT_PATH.relative_to(REPO_ROOT)} ({SIZE}x{SIZE}, {out.mode})")


if __name__ == "__main__":
    main()
