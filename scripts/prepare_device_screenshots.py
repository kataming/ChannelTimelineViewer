# -*- coding: utf-8 -*-
"""実機で撮ったスクリーンショットを、App Store 用のサイズに揃えて配置する。

再生画面のカットだけは CI（シミュレーター）だと YouTube の bot 確認画面が写るため、
実機で撮ったものを使う。実機の解像度（例: iPhone 12〜14 の 1170×2532）は
6.9インチ枠（1320×2868）と違うので、ここで拡大して揃える。
縦横比の差は 0.5% 未満なので、見た目に影響しない範囲でそのまま合わせる。

入力: docs/ui-upload/<言語名>.jpg（日本語名のファイル名でよい）
出力: docs/AppStore/screenshots/<言語キー>/04-player-device.png

使い方:
    python scripts/prepare_device_screenshots.py            # 変換
    python scripts/prepare_device_screenshots.py --check    # 変換せず内容だけ確認
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "docs" / "ui-upload"
OUT_DIR = ROOT / "docs" / "AppStore" / "screenshots"

# App Store の 6.9インチ枠。CI が撮る画像もこの大きさなので、これに合わせる。
TARGET_SIZE = (1320, 2868)

# 拡大しすぎるとぼやけるので、この倍率を超えるものは弾く（撮り直しを促す）。
MAX_UPSCALE = 1.35

# 日本語のファイル名 → 言語キー（Localization/strings.json と同じ）。
NAME_TO_LANG = {
    "日本語": "ja",
    "英語": "en",
    "中国語": "zh-Hans",
    "スペイン語": "es",
    "ドイツ語": "de",
    "フランス語": "fr",
    "韓国語": "ko",
}

OUTPUT_NAME = "04-player-device.png"  # 01,02,03,05,06 の間に入る名前にして並び順を保つ


def convert(check_only: bool) -> int:
    if not SOURCE_DIR.is_dir():
        print(f"入力フォルダがありません: {SOURCE_DIR}")
        return 1

    problems: list[str] = []
    done = 0
    for path in sorted(SOURCE_DIR.iterdir()):
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg"}:
            continue
        lang = NAME_TO_LANG.get(path.stem)
        if lang is None:
            problems.append(f"{path.name}: 言語が判別できません（{'/'.join(NAME_TO_LANG)} のいずれかにしてください）")
            continue

        with Image.open(path) as image:
            width, height = image.size
            upscale = max(TARGET_SIZE[0] / width, TARGET_SIZE[1] / height)
            note = f"{path.name}: {width}×{height} → {TARGET_SIZE[0]}×{TARGET_SIZE[1]}（{upscale:.2f}倍）"
            if upscale > MAX_UPSCALE:
                problems.append(note + " ← 拡大しすぎでぼやけます。実機で撮り直してください")
                continue
            print("  " + note)
            if check_only:
                done += 1
                continue
            out_path = OUT_DIR / lang / OUTPUT_NAME
            out_path.parent.mkdir(parents=True, exist_ok=True)
            image.convert("RGB").resize(TARGET_SIZE, Image.LANCZOS).save(out_path, "PNG")
            done += 1

    if problems:
        print("\n対応できなかったもの:")
        for item in problems:
            print("  -", item)
    print(f"\n{'確認' if check_only else '変換'}できたもの: {done} 件")
    return 1 if problems and done == 0 else 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="変換せず内容だけ確認する")
    args = parser.parse_args()
    return convert(args.check)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
