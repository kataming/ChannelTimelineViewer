# -*- coding: utf-8 -*-
"""「YouTube の共有から追加する」の案内アニメ（Android）用のコマ画像を作る。

実機（720x1520・3ボタンナビ）で、NASA の動画を開いて次の3枚を撮り、
docs/tutorial/raw/copyguide-<言語>-<番号>.png に置く:
  1 … 動画の画面（［共有］が見えている）
  2 … ［共有］を押して共有パネルが出たところ（［コピー］が見えている）
  3 … ［コピー］を押した直後（「コピーされました」が出ている）

加工:
  - 上のステータスバーを切り落とす
  - 動画の映像と、下に出るおすすめ動画はぼかす（他人の映像をアプリ内で見せないため）
  - 押す場所を緑の枠で囲む（既存の案内画像と同じ緑）
  - 丸数字（①②③）と、そこから押す場所へ向かう曲がった矢印を描く
    （2026-10-05 ユーザー指定。参考: 丸の中に数字・白抜きで黒い縁の矢印）

使い方: python scripts/build_copy_guide_frames.py ja   （言語を省略すると raw にある全言語）
出力:   android/app/src/main/res/drawable-<言語>-nodpi/copyguide_frame<番号>.jpg
        （英語は drawable-nodpi = 既定。案内の文字と同じく、未対応の言語は英語の絵になる）
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "tutorial" / "raw"
RES = ROOT / "android" / "app" / "src" / "main" / "res"
GREEN = (46, 125, 50)
INK = (20, 20, 20)
WHITE = (255, 255, 255)

# 言語 → drawable のフォルダ
DIRS = {
    "ja": "drawable-ja-nodpi", "en": "drawable-nodpi", "zh": "drawable-zh-rCN-nodpi",
    "es": "drawable-es-nodpi", "de": "drawable-de-nodpi", "fr": "drawable-fr-nodpi", "ko": "drawable-ko-nodpi",
}

STATUS_BAR = 48  # 切り落とす高さ（元画像のピクセル）
NAV_TOP = 1424   # ナビゲーションバーの上端
PLAYER = (48, 452)  # 動画の映像の上下

# コマごとの設定（元画像のピクセル座標）。言語で位置がずれたら、ここを言語別に足す。
#   badge … 丸数字の中心   tip … 矢印の先（押す場所のすぐ手前）   bend … 矢印の曲がり具合（制御点）
FRAMES = {
    1: {"blur": [PLAYER, (900, NAV_TOP)], "boxes": [(492, 603, 568, 683)],
        "badge": (640, 250), "tip": (548, 590), "bend": (668, 470)},
    2: {"blur": [PLAYER], "boxes": [(28, 1068, 470, 1172)],
        "badge": (640, 1120), "tip": (482, 1120), "bend": (560, 1070)},
    3: {"blur": [PLAYER, (900, 1208), (1314, NAV_TOP)],
        "boxes": [(14, 1208, 706, 1314), (138, 1434, 218, 1508)],
        "badge": (470, 1368), "tip": (228, 1458), "bend": (330, 1350)},
}


def font(size: int) -> ImageFont.FreeTypeFont:
    for name in ("arialbd.ttf", "seguisb.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def bezier(p0, p1, p2, steps=60):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t ** 2 * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t ** 2 * p2[1])
            for t in (i / steps for i in range(steps + 1))]


def arrow(draw: ImageDraw.ImageDraw, start, bend, tip, body=16, edge=5) -> None:
    """白抜きで黒い縁の、曲がった矢印（参考画像の形）。"""
    pts = bezier(start, bend, tip)
    (x1, y1), (x2, y2) = pts[-6], pts[-1]
    ang = math.atan2(y2 - y1, x2 - x1)
    head_len, head_w = 44, 30
    nx, ny = math.cos(ang + math.pi / 2), math.sin(ang + math.pi / 2)
    base = (x2 - head_len * math.cos(ang), y2 - head_len * math.sin(ang))
    head = [(base[0] + head_w * nx, base[1] + head_w * ny), (x2, y2), (base[0] - head_w * nx, base[1] - head_w * ny)]
    shaft = [p for p in pts if math.dist(p, (x2, y2)) > head_len] + [base]
    # 黒い縁（太い線と大きい三角）→ 白い中身（細い線と小さい三角）の順に重ねる
    draw.line(shaft, fill=INK, width=body + edge * 2, joint="curve")
    cx, cy = sum(p[0] for p in head) / 3, sum(p[1] for p in head) / 3
    outer = [(cx + (px - cx) * 1.18, cy + (py - cy) * 1.18) for px, py in head]
    draw.polygon(outer, fill=INK)
    draw.line(shaft, fill=WHITE, width=body, joint="curve")
    inner = [(cx + (px - cx) * 0.82, cy + (py - cy) * 0.82) for px, py in head]
    draw.polygon(inner, fill=WHITE)


def badge(draw: ImageDraw.ImageDraw, center, number: int, r=46) -> None:
    x, y = center
    draw.ellipse([x - r, y - r, x + r, y + r], fill=WHITE, outline=INK, width=8)
    f = font(int(r * 1.35))
    draw.text((x, y + 2), str(number), font=f, fill=INK, anchor="mm")


# ［共有］アイコンの中心の x（言語でボタンの文字の長さが違い、少し左右にずれる）。撮り直したら見て直す。
SHARE_X = {"ja": 530, "en": 516, "zh": 516, "es": 517, "de": 518, "fr": 516, "ko": 516}


def spec_for(lang: str, number: int) -> dict:
    spec = dict(FRAMES[number])
    if number == 1:
        cx = SHARE_X.get(lang, 530)
        spec["boxes"] = [(cx - 38, 603, cx + 38, 683)]
        spec["tip"] = (cx + 18, 590)
    return spec


# ③を「アプリに戻る」の通知にした版（2026-10-05）。copyguide-<言語>-3n.png（通知の一覧を引き下ろした画面）が
# あれば、その中の「アプリに戻る」のカードだけを切り出して、「コピーされました」の画面の上部に貼る
# （画面上部に出るポップアップと同じ見た目。一覧には撮影した端末の他の通知も写るので、そのままは使わない）。
CARD = (8, 950, 712, 1157)          # 通知の一覧の中の「アプリに戻る」のカード
CARD_HEADER = (84, 980, 350, 1020)  # カードの上の行（アプリ名）。試験版の名前が出るので書き直す
CARD_TOP = 64                       # 貼る位置（元画像の y）
NOTIFY_FRAME3 = {"blur": [PLAYER, (900, 1208), (1314, NAV_TOP)],
                 "boxes": [], "badge": (600, 470), "tip": (560, CARD_TOP + 214), "bend": (650, 380)}


def notification_card(lang: str) -> Image.Image:
    shade = Image.open(RAW / f"copyguide-{lang}-3n.png").convert("RGB")
    card = shade.crop(CARD)
    draw = ImageDraw.Draw(card)
    l, t, r, b = CARD_HEADER
    ox, oy = CARD[0], CARD[1]
    draw.rectangle([l - ox, t - oy, r - ox, b - oy], fill=WHITE)
    try:
        f = ImageFont.truetype("YuGothM.ttc", 23)
    except OSError:
        f = font(23)
    draw.text((l - ox + 4, (t + b) / 2 - oy), "Channel Timeline Viewer・現在" if lang == "ja" else "Channel Timeline Viewer",
              font=f, fill=(95, 99, 104), anchor="lm")
    # 角を丸めて影を付ける
    mask = Image.new("L", card.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, card.width - 1, card.height - 1], radius=18, fill=255)
    out = Image.new("RGBA", card.size)
    out.paste(card, (0, 0), mask)
    return out


def build(lang: str, number: int) -> None:
    src = RAW / f"copyguide-{lang}-{number}.png"
    img = Image.open(src).convert("RGB")
    spec = spec_for(lang, number)
    with_card = number == 3 and (RAW / f"copyguide-{lang}-3n.png").exists()
    if with_card:
        spec = dict(NOTIFY_FRAME3)
    for top, bottom in spec["blur"]:
        region = img.crop((0, top, img.width, bottom)).filter(ImageFilter.GaussianBlur(18))
        img.paste(region, (0, top))
    if with_card:
        card = notification_card(lang)
        shadow = Image.new("RGBA", (card.width + 30, card.height + 30), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).rounded_rectangle([15, 18, card.width + 15, card.height + 15], radius=20, fill=(0, 0, 0, 110))
        shadow = shadow.filter(ImageFilter.GaussianBlur(8))
        img.paste(shadow, (CARD[0] - 15, CARD_TOP - 15), shadow)
        img.paste(card, (CARD[0], CARD_TOP), card)
        spec["boxes"] = [(CARD[0] - 2, CARD_TOP - 2, CARD[2] + 2, CARD_TOP + card.height + 2)]
    draw = ImageDraw.Draw(img)
    for l, t, r, b in spec["boxes"]:
        draw.rounded_rectangle([l, t, r, b], radius=14, outline=GREEN, width=6)
    arrow(draw, spec["badge"], spec["bend"], spec["tip"])
    badge(draw, spec["badge"], number)
    img = img.crop((0, STATUS_BAR, img.width, img.height))
    out = RES / DIRS[lang] / f"copyguide_frame{number}.jpg"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, quality=82, optimize=True)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


# ③を「画面の端のロゴのボタン」にした版（2026-10-05・ユーザー指定）。
# 「他のアプリの上に重ねて表示」を許可した人に見せる（許可していない人には通知の③のまま）。
# 「コピーされました」の画面（copyguide-<言語>-3.png）に、アプリが実際に出すボタン
# （ui/CopyGuideOverlay.kt: 56dp の緑の丸＋ロゴ＋白い縁・右端から 6dp・高さの 70% あたり）を描き、
# 丸数字の代わりに「クリック」の文字から矢印でボタンを指す。実機は 320dpi（1dp = 2px）。
LOGO_GREEN = (0x17, 0x91, 0x4A)
LOGO_D = 112                 # 56dp
LOGO_CENTER = (720 - 12 - LOGO_D // 2, 1000)
CLICK_LABEL = {"ja": "クリック", "en": "Tap", "zh": "点击", "es": "Toca", "de": "Tippen", "fr": "Touchez", "ko": "탭"}
CLICK_FONT = {"ja": "YuGothB.ttc", "zh": "msyhbd.ttc", "ko": "malgunbd.ttf"}
# 文字の中心（元画像のピクセル）。下のぼかした画面の左寄り（上の YouTube の文字に重ねると読みにくい・ユーザー指摘）
CLICK_CENTER = (230, 1090)


def overlay_logo(d: int) -> Image.Image:
    """CopyGuideOverlay と同じ見た目のボタン（緑の丸・白い縁・ic_launcher_foreground のロゴ）。"""
    k = 4  # 大きく描いて縮め、縁を滑らかにする
    big = Image.new("RGBA", (d * k, d * k), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    g.ellipse([0, 0, d * k - 1, d * k - 1], fill=WHITE)
    edge = 2 * 2 * k  # 2dp
    g.ellipse([edge, edge, d * k - 1 - edge, d * k - 1 - edge], fill=LOGO_GREEN)
    s = d * k / 108  # ロゴのベクター（108 四方・中身は 27 ずらした 54 四方）
    off = 27 * s

    def bar(x1, x2, y):
        g.rounded_rectangle([off + x1 * s - 2.5 * s, off + y * s, off + x2 * s + 2.5 * s, off + (y + 5) * s],
                            radius=2.5 * s, fill=WHITE)
    bar(8, 38, 10)
    bar(8, 31, 24.5)
    bar(8, 24, 39)
    g.polygon([(off + 40 * s, off + 20 * s), (off + 52 * s, off + 27 * s), (off + 40 * s, off + 34 * s)], fill=WHITE)
    return big.resize((d, d), Image.LANCZOS)


def click_label(draw: ImageDraw.ImageDraw, lang: str, center) -> tuple:
    """白い角丸の札に黒い縁、太字の「クリック」。札の右端の中央を返す（矢印の出発点）。"""
    name = CLICK_FONT.get(lang)
    try:
        f = ImageFont.truetype(name, 50) if name else font(50)
    except OSError:
        f = font(50)
    text = CLICK_LABEL.get(lang, CLICK_LABEL["en"])
    l, t, r, b = draw.textbbox(center, text, font=f, anchor="mm")
    pad_x, pad_y = 30, 18
    box = [l - pad_x, t - pad_y, r + pad_x, b + pad_y]
    draw.rounded_rectangle(box, radius=(box[3] - box[1]) // 2, fill=WHITE, outline=INK, width=8)
    draw.text(center, text, font=f, fill=INK, anchor="mm")
    return box


def build_overlay(lang: str) -> None:
    img = Image.open(RAW / f"copyguide-{lang}-3.png").convert("RGB")
    for top, bottom in FRAMES[3]["blur"]:
        region = img.crop((0, top, img.width, bottom)).filter(ImageFilter.GaussianBlur(18))
        img.paste(region, (0, top))
    logo = overlay_logo(LOGO_D)
    cx, cy = LOGO_CENTER
    img.paste(logo, (cx - LOGO_D // 2, cy - LOGO_D // 2), logo)
    draw = ImageDraw.Draw(img)
    # 押す場所の緑の枠（他のコマと同じ）。丸いボタンなので丸で囲む。
    ring = LOGO_D // 2 + 14
    draw.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], outline=GREEN, width=6)
    # 矢印を先に描き、札をその上に重ねる（出発点が札の下に隠れるように）。
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    box = click_label(probe, lang, CLICK_CENTER)
    start = (box[2] - 10, (box[1] + box[3]) / 2)
    tip = (cx - ring - 10, cy + 4)
    arrow(draw, start, ((start[0] + tip[0]) / 2 + 10, start[1] + 10), tip)
    click_label(draw, lang, CLICK_CENTER)
    img = img.crop((0, STATUS_BAR, img.width, img.height))
    out = RES / DIRS[lang] / "copyguide_frame3_overlay.jpg"
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out, quality=82, optimize=True)
    print(f"  {out.relative_to(ROOT)}  {img.size}")


# ---- iOS 版（2026-10-06・ユーザー指定）-------------------------------------------------
# iOS の画面はこちらで撮れないので、Android で撮った YouTube の画面（YouTube 独自の画面なので
# iOS でもほぼ同じ）を元に iOS の見た目へ加工する:
#   - 上端の Android のステータスバーを、iOS の「◀ Channel Timeline Viewer」（アプリから YouTube を
#     開いたとき iOS が左上に出す戻るリンク）入りのステータスバーに描き替える
#   - 下端の Android のナビゲーションバー（◁ ○ □）を外し、iOS のホームインジケーターにする
#   - ③は「左上の ◀ を押す」（iOS の案内の手順）。①②は Android と同じ
# 出力: Resources/Assets.xcassets/copyguide_ios_frame<番号>_<言語>.imageset/
#   （asset catalog は言語で切り替わらないので名前に言語を入れる。ChannelTutorialView と同じ方式）
ASSETS = ROOT / "Resources" / "Assets.xcassets"
IOS_LANG = {"ja": "ja", "en": "en", "zh": "zh_Hans", "es": "es", "de": "de", "fr": "fr", "ko": "ko"}
IOS_BAR = 56                      # iOS のステータスバーの高さ（出力画像のピクセル）
IOS_BACK_TEXT = "Channel Timeline Viewer"
IOS_HOME = 34                     # ホームインジケーターの帯


def ios_status_bar(img: Image.Image, top_color) -> tuple:
    """上端に iOS のステータスバー（左に「◀ アプリ名」）を描き、戻るリンクの範囲を返す。"""
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, img.width, IOS_BAR], fill=top_color)
    ink = WHITE if sum(top_color) < 384 else INK
    f = font(22)
    cy = IOS_BAR // 2 + 2
    # ◀（フォントに無いことがあるので三角形で描く）
    draw.polygon([(30, cy), (41, cy - 8), (41, cy + 8)], fill=ink)
    draw.text((48, cy), IOS_BACK_TEXT, font=f, fill=ink, anchor="lm")
    right = 48 + draw.textlength(IOS_BACK_TEXT, font=f)
    # 右側の電池（簡略）
    bx = img.width - 64
    draw.rounded_rectangle([bx, cy - 10, bx + 38, cy + 10], radius=5, outline=ink, width=2)
    draw.rounded_rectangle([bx + 4, cy - 6, bx + 30, cy + 6], radius=2, fill=ink)
    draw.rectangle([bx + 40, cy - 4, bx + 43, cy + 4], fill=ink)
    return (18, cy - 18, int(right) + 12, cy + 18)


def build_ios(lang: str, number: int) -> None:
    src = RAW / f"copyguide-{lang}-{number}.png"
    img = Image.open(src).convert("RGB")
    spec = dict(spec_for(lang, number))
    blur = list(spec["blur"])
    if number == 2:
        # 共有パネルの共有先の並び（Viber・Bluetooth など）と［コピー］より下（Quick Share 等）は
        # Android の端末に固有で、iPhone では違うものが出るのでぼかす。［コピー］の行だけ見せる。
        for top, bottom in [(840, 1015), (1185, NAV_TOP)]:
            # パネルの幅（左右の余白の内側）だけをぼかす。外までぼかすと縁ににじむ
            region = img.crop((18, top, img.width - 18, bottom)).filter(ImageFilter.GaussianBlur(18))
            img.paste(region, (18, top))
    for top, bottom in blur:
        region = img.crop((0, top, img.width, min(bottom, NAV_TOP))).filter(ImageFilter.GaussianBlur(18))
        img.paste(region, (0, top))
    # Android のステータスバーとナビゲーションバーを外す
    img = img.crop((0, STATUS_BAR, img.width, NAV_TOP))
    page = Image.new("RGB", (img.width, IOS_BAR + img.height + IOS_HOME), WHITE)
    page.paste(img, (0, IOS_BAR))
    dy = IOS_BAR - STATUS_BAR      # 元画像の y → 出力の y
    top_color = img.getpixel((img.width // 2, 4))
    back = ios_status_bar(page, top_color)
    draw = ImageDraw.Draw(page)
    # ホームインジケーター
    draw.rounded_rectangle([page.width // 2 - 70, page.height - 18, page.width // 2 + 70, page.height - 11],
                           radius=4, fill=INK)
    if number == 3:
        # ③ 左上の「◀ アプリ名」を押す
        draw.rounded_rectangle(back, radius=12, outline=GREEN, width=6)
        badge_at = (470, 250)
        tip = ((back[0] + back[2]) // 2 + 30, back[3] + 12)
        arrow(draw, badge_at, (480, 120), tip)
        badge(draw, badge_at, 3)
    else:
        for l, t, r, b in spec["boxes"]:
            draw.rounded_rectangle([l, t + dy, r, b + dy], radius=14, outline=GREEN, width=6)
        bx, by = spec["badge"]
        tx, ty = spec["tip"]
        mx, my = spec["bend"]
        arrow(draw, (bx, by + dy), (mx, my + dy), (tx, ty + dy))
        badge(draw, (bx, by + dy), number)
    name = f"copyguide_ios_frame{number}_{IOS_LANG[lang]}"
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    page.save(folder / f"{name}.jpg", quality=82, optimize=True)
    (folder / "Contents.json").write_text(
        '{\n  "images" : [\n    { "filename" : "' + name + '.jpg", "idiom" : "universal" }\n  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n}\n', encoding="utf-8")
    print(f"  {folder.relative_to(ROOT)}  {page.size}")


# ④ 戻ったときに iOS が出す「ペーストを許可」の確認（2026-10-06・ユーザー指定）。
# iOS の画面は撮れないので、アプリの最初の画面（文言は strings.json から）を簡略に描き、
# その上に iOS の確認ダイアログを描く。ダイアログの文言は iOS の表示に合わせた（実機と細部が違えば直す）。
PASTE_ALERT = {
    "ja": ("“Channel Timeline Viewer”に“YouTube”からペーストしようとしています。よろしいですか?",
           "許可しますか?", "ペーストを許可しない", "ペーストを許可"),
    "en": ("“Channel Timeline Viewer” would like to paste from “YouTube”",
           "Do you want to allow this?", "Don’t Allow Paste", "Allow Paste"),
    "zh": ("“Channel Timeline Viewer”想要粘贴来自“YouTube”的内容",
           "要允许吗？", "不允许粘贴", "允许粘贴"),
    "es": ("“Channel Timeline Viewer” quiere pegar desde “YouTube”",
           "¿Quieres permitirlo?", "No permitir pegar", "Permitir pegar"),
    "de": ("„Channel Timeline Viewer“ möchte aus „YouTube“ einsetzen",
           "Möchtest du das erlauben?", "Einsetzen nicht erlauben", "Einsetzen erlauben"),
    "fr": ("« Channel Timeline Viewer » souhaite coller depuis « YouTube »",
           "Voulez-vous l’autoriser ?", "Ne pas autoriser le collage", "Autoriser le collage"),
    "ko": ("‘Channel Timeline Viewer’이(가) ‘YouTube’에서 붙여넣으려고 합니다.",
           "허용하겠습니까?", "붙여넣기 허용 안 함", "붙여넣기 허용"),
}
UI_FONT = {"ja": ("YuGothB.ttc", "YuGothM.ttc"), "zh": ("msyhbd.ttc", "msyh.ttc"),
           "ko": ("malgunbd.ttf", "malgun.ttf")}
STRINGS_LANG = {"zh": "zh-Hans"}


def ui_font(lang: str, size: int, bold: bool) -> ImageFont.FreeTypeFont:
    names = UI_FONT.get(lang, ("seguisb.ttf", "segoeui.ttf"))
    try:
        return ImageFont.truetype(names[0] if bold else names[1], size)
    except OSError:
        return font(size)


def wrap(draw: ImageDraw.ImageDraw, text: str, f, width: int) -> list[str]:
    """幅に収まるように折り返す（空白の無い言語は1文字ずつ）。"""
    lines, line = [], ""
    cjk = any("぀" <= c <= "鿿" for c in text)
    # 日本語・中国語は1文字ずつ折り返すが、英単語（YouTube など）の途中では切らない
    import re as _re
    tokens = _re.findall(r"[A-Za-z0-9’'“”\"]+ ?|.", text) if cjk else text.split(" ")
    joiner = "" if cjk else " "
    for tok in tokens:
        trial = (line + joiner + tok) if line else tok
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            if line:
                lines.append(line)
            line = tok
    if line:
        lines.append(line)
    return lines


def build_ios_paste(lang: str) -> None:
    import json
    strings = json.loads((ROOT / "Localization" / "strings.json").read_text(encoding="utf-8"))
    key = STRINGS_LANG.get(lang, lang)
    W, H = 720, IOS_BAR + (NAV_TOP - STATUS_BAR) + IOS_HOME
    page = Image.new("RGB", (W, H), (242, 242, 247))
    draw = ImageDraw.Draw(page)
    # ステータスバー（左に時刻）
    draw.text((52, IOS_BAR // 2 + 2), "9:41", font=ui_font("en", 24, True), fill=INK, anchor="lm")
    bx = W - 64
    cy = IOS_BAR // 2 + 2
    draw.rounded_rectangle([bx, cy - 10, bx + 38, cy + 10], radius=5, outline=INK, width=2)
    draw.rounded_rectangle([bx + 4, cy - 6, bx + 30, cy + 6], radius=2, fill=INK)
    # アプリの最初の画面（簡略）
    draw.text((32, 150), "Channel Timeline", font=ui_font("en", 58, True), fill=INK, anchor="lm")
    blue = (52, 120, 246)
    draw.rounded_rectangle([24, 210, W - 24, 290], radius=40, fill=blue)
    draw.text((W // 2, 250), strings["tutorial.pick.howto"][key], font=ui_font(lang, 28, True), fill=WHITE, anchor="mm")
    draw.rounded_rectangle([24, 310, W - 24, 386], radius=20, fill=WHITE, outline=(205, 205, 210), width=2)
    draw.text((W // 2, 348), strings["tutorial.pick.title"][key], font=ui_font(lang, 28, True), fill=blue, anchor="mm")
    for top in (420, 560, 700, 840):
        draw.rounded_rectangle([24, top, W - 24, top + 116], radius=22, fill=WHITE)
        draw.rounded_rectangle([48, top + 28, 300, top + 50], radius=8, fill=(225, 225, 230))
        draw.rounded_rectangle([48, top + 66, 520, top + 84], radius=8, fill=(235, 235, 240))
    # 暗くする
    dim = Image.new("RGBA", (W, H), (0, 0, 0, 90))
    page = Image.alpha_composite(page.convert("RGBA"), dim).convert("RGB")
    draw = ImageDraw.Draw(page)
    # 確認ダイアログ
    title, sub, deny, allow = PASTE_ALERT[lang]
    ft, fs, fb = ui_font(lang, 30, True), ui_font(lang, 24, False), ui_font(lang, 28, False)
    aw = 560
    ax = (W - aw) // 2
    tlines = wrap(draw, title, ft, aw - 80)
    line_h = 40
    ah = 50 + len(tlines) * line_h + 46 + 30 + 84 * 2 + 16 + 30
    ay = (H - ah) // 2 + 40
    draw.rounded_rectangle([ax, ay, ax + aw, ay + ah], radius=44, fill=(246, 246, 248))
    y = ay + 50
    for line in tlines:
        draw.text((ax + 40, y), line, font=ft, fill=INK, anchor="lm")
        y += line_h
    draw.text((ax + 40, y + 6), sub, font=fs, fill=(110, 110, 115), anchor="lm")
    y += 56
    # ペーストを許可しない（青）／ペーストを許可（灰）
    draw.rounded_rectangle([ax + 30, y, ax + aw - 30, y + 72], radius=36, fill=blue)
    draw.text((W // 2, y + 36), deny, font=fb, fill=WHITE, anchor="mm")
    y2 = y + 84
    draw.rounded_rectangle([ax + 30, y2, ax + aw - 30, y2 + 72], radius=36, fill=(222, 222, 226))
    draw.text((W // 2, y2 + 36), allow, font=fb, fill=INK, anchor="mm")
    # 押す場所（ペーストを許可）
    box = (ax + 22, y2 - 8, ax + aw - 22, y2 + 80)
    draw.rounded_rectangle(box, radius=44, outline=GREEN, width=6)
    badge_at = (W - 120, y2 + 250)
    arrow(draw, badge_at, (W - 70, y2 + 160), (W // 2 + 150, box[3] + 10))
    badge(draw, badge_at, 4)
    # ホームインジケーター
    draw.rounded_rectangle([W // 2 - 70, H - 18, W // 2 + 70, H - 11], radius=4, fill=INK)
    name = f"copyguide_ios_frame4_{IOS_LANG[lang]}"
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    page.save(folder / f"{name}.jpg", quality=82, optimize=True)
    (folder / "Contents.json").write_text(
        '{\n  "images" : [\n    { "filename" : "' + name + '.jpg", "idiom" : "universal" }\n  ],\n'
        '  "info" : { "author" : "xcode", "version" : 1 }\n}\n', encoding="utf-8")
    print(f"  {folder.relative_to(ROOT)}  {page.size}")


def main() -> int:
    args = sys.argv[1:]
    ios_only = "--ios" in args
    langs = [a for a in args if not a.startswith("--")] or \
        sorted({p.name.split("-")[1] for p in RAW.glob("copyguide-*-1.png")})
    for lang in langs:
        if not ios_only:
            for number in FRAMES:
                build(lang, number)
            build_overlay(lang)
        for number in FRAMES:
            build_ios(lang, number)
        build_ios_paste(lang)
    return 0


if __name__ == "__main__":
    sys.exit(main())
