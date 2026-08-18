# -*- coding: utf-8 -*-
"""`Localization/strings.json` から各言語の Localizable.strings を生成する。

翻訳の元データは strings.json 1か所だけ。ここから 7言語ぶんを書き出す。
言語を足すときは LANGUAGES に追加して、strings.json に訳を入れる。

使い方:
    python scripts/build_localizations.py          # 生成
    python scripts/build_localizations.py --check   # 未翻訳が無いか確認だけ
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Localization" / "strings.json"
LANGUAGES = ["ja", "en", "zh-Hans", "es", "de", "fr", "ko"]
BASE_LANGUAGE = "ja"


def escape(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\n")


def load() -> dict:
    return json.loads(io.open(SOURCE, encoding="utf-8").read())


def missing_translations(data: dict) -> list[str]:
    problems = []
    for key, entry in data.items():
        for lang in LANGUAGES:
            if not entry.get(lang):
                problems.append(f"{key}: {lang} が未翻訳")
    return problems


def write_strings(data: dict) -> None:
    for lang in LANGUAGES:
        lines = [
            "/* このファイルは scripts/build_localizations.py が生成します。直接編集しないこと。 */",
            f"/* language: {lang} */",
            "",
        ]
        for key in sorted(data):
            entry = data[key]
            comment = entry.get("comment")
            if comment:
                lines.append(f"/* {comment} */")
            value = entry.get(lang) or entry[BASE_LANGUAGE]
            lines.append(f'"{key}" = "{escape(value)}";')
        path = ROOT / "Localization" / f"{lang}.lproj" / "Localizable.strings"
        path.parent.mkdir(parents=True, exist_ok=True)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
        print(f"  書き出し: {path.relative_to(ROOT)}（{len(data)} 件）")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="生成せずに未翻訳の有無だけ確認する")
    args = parser.parse_args()

    data = load()
    problems = missing_translations(data)
    if problems:
        print(f"未翻訳が {len(problems)} 件あります:")
        for p in problems[:40]:
            print("  -", p)
        if args.check:
            return 1

    if args.check:
        print(f"OK: {len(data)} 件 × {len(LANGUAGES)} 言語すべて翻訳済み")
        return 0

    write_strings(data)
    print(f"完了: {len(data)} 件 × {len(LANGUAGES)} 言語")
    return 0


if __name__ == "__main__":
    sys.exit(main())
