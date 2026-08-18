"""Swift ソース内に残っている日本語リテラルを洗い出す補助スクリプト。

使い方:
    python scripts/find_untranslated_strings.py [ファイル...]

引数を省略すると Views / ViewModels / Services / ExtensionShared を走査する。
コメント（// 以降）は対象外。文字列リテラルのうち日本語を含むものだけを行番号付きで表示する。
"""
from __future__ import annotations

import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_DIRS = ["Views", "ViewModels", "Services", "ExtensionShared", "Models"]

JAPANESE = re.compile("[぀-ヿ一-鿿]")
STRING_LITERAL = re.compile(r'"(?:[^"\\\n]|\\.)*"')


def scan(path: Path) -> list[tuple[int, str]]:
    found: list[tuple[int, str]] = []
    text = io.open(path, encoding="utf-8").read()
    for lineno, line in enumerate(text.split("\n"), 1):
        code = line.split("//")[0]
        for match in STRING_LITERAL.finditer(code):
            literal = match.group(0)
            if JAPANESE.search(literal):
                found.append((lineno, literal))
    return found


def main() -> int:
    if len(sys.argv) > 1:
        paths = [Path(p) for p in sys.argv[1:]]
    else:
        paths = sorted(p for d in DEFAULT_DIRS for p in (ROOT / d).rglob("*.swift"))

    total = 0
    for path in paths:
        hits = scan(path)
        if not hits:
            continue
        rel = path.relative_to(ROOT) if path.is_absolute() else path
        print(f"===== {rel} ({len(hits)})")
        for lineno, literal in hits:
            print(f"  {lineno}: {literal}")
        total += len(hits)
    print(f"合計 {total} 件")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
