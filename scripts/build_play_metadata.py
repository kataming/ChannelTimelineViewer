# -*- coding: utf-8 -*-
"""`docs/PlayStore/metadata.json` から Google Play 用の言語別ファイルを生成し、文字数を検証する。

Play Console の入力欄は App Store と違う（キーワード欄が無く、代わりに「短い説明」80文字がある）ので
原本を分けている。文章の中身は App Store 版と揃えてある。

出力:
  docs/PlayStore/listing/<ロケール>.md   … 画面に貼り付ける用
  docs/PlayStore/listing/<ロケール>/     … API/fastlane 互換のテキスト（title.txt など）

使い方:
    python scripts/build_play_metadata.py           # 生成 + 検証
    python scripts/build_play_metadata.py --check   # 検証だけ
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "PlayStore" / "metadata.json"
OUT_DIR = ROOT / "docs" / "PlayStore" / "listing"

FIELDS = ["title", "shortDescription", "fullDescription"]
FIELD_LABELS = {
    "title": "アプリ名（Title）",
    "shortDescription": "短い説明（Short description）",
    "fullDescription": "詳しい説明（Full description）",
}
FIELD_FILES = {
    "title": "title.txt",
    "shortDescription": "short_description.txt",
    "fullDescription": "full_description.txt",
}


def load() -> dict:
    return json.loads(io.open(SOURCE, encoding="utf-8").read())


def check(data: dict) -> list[str]:
    limits = data["_limits"]
    problems: list[str] = []
    for field in FIELDS:
        for locale in data["_locales"]:
            value = data[field].get(locale)
            if not value:
                problems.append(f"{field} / {locale}: 未入力")
                continue
            if len(value) > limits[field]:
                problems.append(
                    f"{field} / {locale}: {len(value)}文字（上限 {limits[field]}）"
                    f"＝{len(value) - limits[field]}文字オーバー")
    return problems


def write(data: dict) -> None:
    limits = data["_limits"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for locale, label in data["_locales"].items():
        lines = [
            f"# Google Play ストア掲載情報 — {label}（{locale}）",
            "",
            "> このファイルは `scripts/build_play_metadata.py` が生成します。直接編集せず、",
            "> `docs/PlayStore/metadata.json` を直してから再生成してください。",
            "",
            f"- メール: {data['contactEmail']}",
            f"- ウェブサイト: {data['contactWebsite']}",
            f"- プライバシーポリシー: {data['privacyPolicyUrl']}",
            "",
        ]
        for field in FIELDS:
            value = data[field][locale]
            lines += [
                f"## {FIELD_LABELS[field]}",
                f"<!-- {len(value)} / {limits[field]} 文字 -->",
                "",
                "```",
                value,
                "```",
                "",
            ]
        io.open(OUT_DIR / f"{locale}.md", "w", encoding="utf-8", newline="\n").write("\n".join(lines))

        # API から流し込むとき用に、項目ごとの素のテキストも置く。
        locale_dir = OUT_DIR / locale
        locale_dir.mkdir(parents=True, exist_ok=True)
        for field in FIELDS:
            io.open(locale_dir / FIELD_FILES[field], "w", encoding="utf-8", newline="\n").write(
                data[field][locale])
        print(f"  書き出し: {(OUT_DIR / f'{locale}.md').relative_to(ROOT)}")

    index = [
        "# Google Play ストア掲載情報（7言語）",
        "",
        "原本は [`../metadata.json`](../metadata.json)。編集後は次を実行します。",
        "",
        "```",
        "python scripts/build_play_metadata.py",
        "```",
        "",
        "| ロケール | ファイル |",
        "| --- | --- |",
    ]
    for locale, label in data["_locales"].items():
        index.append(f"| {label} | [{locale}.md]({locale}.md) |")
    index += ["", "## 文字数（上限に対する使用量）", "",
              "| 項目 | " + " | ".join(data["_locales"]) + " |",
              "| --- | " + " | ".join("---" for _ in data["_locales"]) + " |"]
    for field in FIELDS:
        cells = [f"{len(data[field][locale])}/{limits[field]}" for locale in data["_locales"]]
        index.append(f"| {field} | " + " | ".join(cells) + " |")
    index.append("")
    io.open(OUT_DIR / "README.md", "w", encoding="utf-8", newline="\n").write("\n".join(index))
    print(f"  書き出し: {(OUT_DIR / 'README.md').relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="生成せず検証だけ行う")
    args = parser.parse_args()

    data = load()
    problems = check(data)
    if problems:
        print(f"問題が {len(problems)} 件あります:")
        for problem in problems:
            print("  -", problem)
        return 1

    print(f"OK: {len(FIELDS)} 項目 × {len(data['_locales'])} 言語すべて上限内")
    if not args.check:
        write(data)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
