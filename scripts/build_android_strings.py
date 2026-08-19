# -*- coding: utf-8 -*-
"""`Localization/strings.json` から Android の strings.xml（7言語）を生成する。

iOS 版と Android 版で**同じ翻訳原本**を使うためのスクリプト。
文言を足すときは strings.json に7言語ぶん書いて、iOS 用（build_localizations.py）と
Android 用（このファイル）の両方を生成する。

変換の要点:
  - キー: `player.nav.next` → `player_nav_next`（Android のリソース名にドットは使えない）
  - 書式: `%@` → `%s`、`%1$@` → `%1$s`（`%%` はそのまま）
  - エスケープ: `'` `"` `\\` と XML 実体参照、改行は `\\n`
  - 既定（values/）は英語。端末の言語が未対応なら英語になる（iOS と同じ挙動）

使い方:
    python scripts/build_android_strings.py            # 生成
    python scripts/build_android_strings.py --check    # 生成せず確認だけ
"""
from __future__ import annotations

import argparse
import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Localization" / "strings.json"
RES_DIR = ROOT / "android" / "app" / "src" / "main" / "res"

# 原本の言語キー → Android のリソース修飾子。既定（values/）は英語。
LANGUAGE_DIRS = {
    "en": "values",
    "ja": "values-ja",
    "zh-Hans": "values-zh-rCN",
    "es": "values-es",
    "de": "values-de",
    "fr": "values-fr",
    "ko": "values-ko",
}

# Android だけで使う文言（アプリ名など）。翻訳しないものはここに置く。
EXTRA_STRINGS = {"app_name": "Channel Timeline Viewer"}

# iOS 専用の文言（Android では出番が無い）は入れない。
SKIP_PREFIXES = ("handoff.", "shareTips.", "share.", "openExtension.", "notification.")


def resource_name(key: str) -> str:
    return re.sub(r"[^a-z0-9_]", "_", key.replace(".", "_").lower())


def convert_format(value: str) -> str:
    """iOS の書式指定子を Android のものに直す。"""
    value = re.sub(r"%(\d+)\$@", r"%\1$s", value)
    return value.replace("%@", "%s")


def escape(value: str) -> str:
    """strings.xml のテキストとして安全にする。"""
    value = (value.replace("\\", "\\\\")
                  .replace("&", "&amp;")
                  .replace("<", "&lt;")
                  .replace(">", "&gt;")
                  .replace("'", "\\'")
                  .replace('"', "\\\""))
    return value.replace("\n", "\\n")


def load() -> dict:
    return json.loads(io.open(SOURCE, encoding="utf-8").read())


def included(key: str) -> bool:
    return not key.startswith(SKIP_PREFIXES)


def write(data: dict, check_only: bool) -> int:
    keys = [key for key in sorted(data) if included(key)]
    for lang, folder in LANGUAGE_DIRS.items():
        lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- このファイルは scripts/build_android_strings.py が生成します。直接編集しないこと。 -->",
            f"<!-- language: {lang} -->",
            "<resources>",
        ]
        if folder == "values":
            for name, value in EXTRA_STRINGS.items():
                lines.append(f'    <string name="{name}">{escape(value)}</string>')
        for key in keys:
            entry = data[key]
            value = entry.get(lang) or entry["ja"]
            comment = entry.get("comment")
            if comment and folder == "values":
                lines.append(f"    <!-- {comment} -->")
            lines.append(
                f'    <string name="{resource_name(key)}">{escape(convert_format(value))}</string>')
        lines.append("</resources>")

        path = RES_DIR / folder / "strings.xml"
        if check_only:
            print(f"  確認: {path.relative_to(ROOT)}（{len(keys)} 件）")
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
        print(f"  書き出し: {path.relative_to(ROOT)}（{len(keys)} 件）")
    return len(keys)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="生成せず確認だけ行う")
    args = parser.parse_args()

    data = load()
    count = write(data, args.check)
    skipped = [key for key in data if not included(key)]
    print(f"完了: {count} 件 × {len(LANGUAGE_DIRS)} 言語"
          f"（iOS 専用のため除外: {len(skipped)} 件）")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
