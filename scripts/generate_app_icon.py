# -*- coding: utf-8 -*-
"""Channel Timeline Viewer のアプリアイコン(1024x1024 PNG)を生成する。

docs/app-icon-requirements.md の要件に従う:
  - 1024x1024 / PNG / sRGB / アルファなし(不透明) / 角丸なし(四角のまま)
  - YouTube ロゴ・赤い再生ボタン・赤主体の配色・「Tube」文字は使わない
  - モチーフは「時系列・順番・進捗」(タイムライン上に並ぶ動画フレーム + チェック + 進捗バー)

出力: Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png

実行: python scripts/generate_app_icon.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

# --- 基本設定 -----------------------------------------------------------------
SIZE = 1024
SS = 4  # スーパーサンプリング倍率(アンチエイリアス用)
S = SIZE * SS

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = (
    REPO_ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon-1024.png"
)

# --- 配色(青〜ティール系。赤は使わない) ----------------------------------------
BG_TOP = (18, 32, 62)         # 深いネイビー
BG_BOTTOM = (12, 74, 96)      # 濃いティール
CARD_WATCHED = (86, 204, 214)  # 視聴済みカード(明るいティール)
CARD_CURRENT = (255, 255, 255)  # 現在地のカード(白)
CARD_UNWATCHED = (72, 100, 140)  # 未視聴カード(くすんだ青)
LINE_DONE = (140, 226, 232)   # 進んだタイムライン
LINE_TODO = (58, 84, 122)     # これからのタイムライン
CHECK = (18, 32, 62)          # チェックマーク(カード上に描くので背景色)


def rounded_rect(draw: ImageDraw.ImageDraw, box, radius, fill):
    draw.rounded_rectangle(box, radius=radius, fill=fill)


def main() -> None:
    # 背景: 縦方向グラデーション(アルファなし = RGB モード)
    img = Image.new("RGB", (S, S), BG_TOP)
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        d.line(
            [(0, y), (S, y)],
            fill=(
                round(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t),
                round(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t),
                round(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t),
            ),
        )

    u = S / 1024.0  # 1024 基準の座標をスケールするための単位

    # --- タイムライン(横線) ---------------------------------------------------
    # 構図全体を 1024 の縦中央に収める(上下の余白を均等に)
    line_y = 540 * u
    line_x0, line_x1 = 196 * u, 828 * u
    line_w = 28 * u
    # 進捗位置(3枚中2枚目まで完了 = 2/3 付近)
    progress_x = line_x0 + (line_x1 - line_x0) * 0.5

    d.rounded_rectangle(
        [line_x0, line_y - line_w / 2, line_x1, line_y + line_w / 2],
        radius=line_w / 2,
        fill=LINE_TODO,
    )
    d.rounded_rectangle(
        [line_x0, line_y - line_w / 2, progress_x, line_y + line_w / 2],
        radius=line_w / 2,
        fill=LINE_DONE,
    )

    # --- 動画フレーム(3枚。左から右へ = 古い順に進む) --------------------------
    # 中央のカードを一番大きく(現在地)。セーフエリア内に収める。
    cards = [
        # (中心x, 幅, 高さ, 色)
        (292 * u, 224 * u, 150 * u, CARD_WATCHED),
        (512 * u, 288 * u, 194 * u, CARD_CURRENT),
        (732 * u, 224 * u, 150 * u, CARD_UNWATCHED),
    ]
    card_bottom = line_y - 74 * u  # タイムラインの少し上に浮かせる

    def bg_at(y: float):
        """背景グラデーションの、その高さでの色を返す(重なりの見切り線用)。"""
        t = max(0.0, min(1.0, y / (S - 1)))
        return (
            round(BG_TOP[0] + (BG_BOTTOM[0] - BG_TOP[0]) * t),
            round(BG_TOP[1] + (BG_BOTTOM[1] - BG_TOP[1]) * t),
            round(BG_TOP[2] + (BG_BOTTOM[2] - BG_TOP[2]) * t),
        )

    for cx, w, h, color in cards:
        box = [cx - w / 2, card_bottom - h, cx + w / 2, card_bottom]
        rounded_rect(d, box, radius=30 * u, fill=color)

    # 中央カード(現在地)は左右のカードと重なるため、背景色の見切りを入れて分離する
    cx0, w0, h0, _ = cards[1]
    gap = 14 * u
    rounded_rect(
        d,
        [cx0 - w0 / 2 - gap, card_bottom - h0 - gap, cx0 + w0 / 2 + gap, card_bottom + gap],
        radius=30 * u + gap,
        fill=bg_at(card_bottom - h0 / 2),
    )
    rounded_rect(
        d,
        [cx0 - w0 / 2, card_bottom - h0, cx0 + w0 / 2, card_bottom],
        radius=30 * u,
        fill=CARD_CURRENT,
    )

    # 中央カード(現在地)に「順番」を示す三本のバー(内容の抽象化)
    cx, w, h, _ = cards[1]
    bar_x0 = cx - w / 2 + 38 * u
    bar_top = card_bottom - h + 44 * u
    bar_h = 22 * u
    bar_gap = 32 * u
    for i, ratio in enumerate((1.0, 0.72, 0.44)):
        y0 = bar_top + i * (bar_h + bar_gap)
        d.rounded_rectangle(
            [bar_x0, y0, bar_x0 + (w - 76 * u) * ratio, y0 + bar_h],
            radius=bar_h / 2,
            fill=(BG_TOP[0], BG_TOP[1], BG_TOP[2]),
        )

    # --- タイムライン上のノード ------------------------------------------------
    node_r = 42 * u
    nodes = [
        (292 * u, LINE_DONE, True),    # 視聴済み: チェック
        (512 * u, CARD_CURRENT, True),  # 現在地: チェック(白)
        (732 * u, LINE_TODO, False),   # 未視聴: 中空
    ]
    for nx, color, checked in nodes:
        d.ellipse([nx - node_r, line_y - node_r, nx + node_r, line_y + node_r], fill=color)
        if checked:
            # チェックマーク(2本の太線)
            d.line(
                [(nx - 18 * u, line_y + 1 * u), (nx - 5 * u, line_y + 15 * u)],
                fill=CHECK,
                width=int(11 * u),
            )
            d.line(
                [(nx - 5 * u, line_y + 15 * u), (nx + 19 * u, line_y - 14 * u)],
                fill=CHECK,
                width=int(11 * u),
            )
        else:
            inner = node_r - 14 * u
            d.ellipse(
                [nx - inner, line_y - inner, nx + inner, line_y + inner],
                fill=bg_at(line_y),
            )

    # --- 進捗バー(下部) --------------------------------------------------------
    pb_y = 706 * u
    pb_h = 36 * u
    pb_x0, pb_x1 = 244 * u, 780 * u
    d.rounded_rectangle(
        [pb_x0, pb_y, pb_x1, pb_y + pb_h], radius=pb_h / 2, fill=LINE_TODO
    )
    d.rounded_rectangle(
        [pb_x0, pb_y, pb_x0 + (pb_x1 - pb_x0) * 0.62, pb_y + pb_h],
        radius=pb_h / 2,
        fill=LINE_DONE,
    )

    # --- 出力(縮小してアンチエイリアス / RGB のままなので透過なし) ---------------
    out = img.resize((SIZE, SIZE), Image.LANCZOS)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT_PATH, format="PNG")

    print("wrote:", OUT_PATH)
    print("mode:", out.mode, "size:", out.size)


if __name__ == "__main__":
    main()
