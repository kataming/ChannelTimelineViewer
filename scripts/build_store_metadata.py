# -*- coding: utf-8 -*-
"""`docs/AppStore/metadata.json` から言語別の入力用ファイルを生成し、文字数上限を検証する。

App Store Connect には言語ごとに手で貼り付けるため、1言語=1ファイルにして
「そのままコピペできる形」で書き出す。上限を超えていればエラーにする（提出前に気付くため）。

使い方:
    python scripts/build_store_metadata.py           # 生成 + 検証
    python scripts/build_store_metadata.py --check   # 検証だけ
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "AppStore" / "metadata.json"
OUT_DIR = ROOT / "docs" / "AppStore" / "metadata"

# App Store Connect の入力欄と、その並び順。
FIELDS = ["name", "subtitle", "promotionalText", "keywords", "description", "whatsNew"]
FIELD_LABELS = {
    "name": "App 名（Name）",
    "subtitle": "サブタイトル（Subtitle）",
    "promotionalText": "プロモーション用テキスト（Promotional Text）",
    "keywords": "キーワード（Keywords／カンマ区切り・スペースを入れない）",
    "description": "説明（Description）",
    "whatsNew": "このバージョンの新機能（What's New）",
}


def load() -> dict:
    return json.loads(io.open(SOURCE, encoding="utf-8").read())


def check(data: dict) -> list[str]:
    """文字数上限と、翻訳の抜けを調べる。"""
    limits = data["_limits"]
    locales = list(data["_locales"].keys())
    problems: list[str] = []
    for field in FIELDS:
        for locale in locales:
            value = data[field].get(locale)
            if not value:
                problems.append(f"{field} / {locale}: 未入力")
                continue
            limit = limits[field]
            if len(value) > limit:
                problems.append(
                    f"{field} / {locale}: {len(value)}文字（上限 {limit}）＝{len(value) - limit}文字オーバー")
    return problems


def write(data: dict) -> None:
    locales = data["_locales"]
    limits = data["_limits"]
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    for locale, label in locales.items():
        lines = [
            f"# App Store メタデータ — {label}",
            "",
            "> このファイルは `scripts/build_store_metadata.py` が生成します。直接編集せず、",
            "> `docs/AppStore/metadata.json` を直してから再生成してください。",
            "",
            f"- サポートURL: {data['supportURL']}",
            f"- マーケティングURL: {data['marketingURL']}",
            f"- プライバシーポリシーURL: {data['privacyPolicyURL']}",
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
        path = OUT_DIR / f"{locale}.md"
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
        print(f"  書き出し: {path.relative_to(ROOT)}")

    # 一覧（文字数の早見表）
    index = [
        "# App Store メタデータ（7言語）",
        "",
        "`docs/AppStore/metadata.json` が原本です。編集後は次を実行してください。",
        "",
        "```",
        "python scripts/build_store_metadata.py",
        "```",
        "",
        "## 言語別ファイル",
        "",
    ]
    for locale, label in locales.items():
        index.append(f"- [{label}]({locale}.md)")
    index += ["", "## 文字数（上限に対する使用量）", "",
              "| 項目 | " + " | ".join(locales.keys()) + " |",
              "| --- | " + " | ".join("---" for _ in locales) + " |"]
    for field in FIELDS:
        cells = [f"{len(data[field][locale])}/{limits[field]}" for locale in locales]
        index.append(f"| {field} | " + " | ".join(cells) + " |")
    index.append("")
    io.open(OUT_DIR / "README.md", "w", encoding="utf-8", newline="\n").write("\n".join(index))
    print(f"  書き出し: {(OUT_DIR / 'README.md').relative_to(ROOT)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="生成せずに検証だけ行う")
    args = parser.parse_args()

    data = load()
    problems = check(data)
    if problems:
        print(f"問題が {len(problems)} 件あります:")
        for p in problems:
            print("  -", p)
        return 1

    locales = data["_locales"]
    print(f"OK: {len(FIELDS)} 項目 × {len(locales)} 言語すべて上限内")
    if not args.check:
        write(data)
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
