# -*- coding: utf-8 -*-
"""生成した .xcscheme に StoreKit のテスト設定を差し込む。

XcodeGen の `storeKitConfiguration` はテストアクションには書き出されない（実行アクションのみ）。
UI テストから起動したアプリに価格を出すには TestAction 側に参照が要るので、
`xcodegen generate` のあとにここで足す。

使い方:
  python scripts/patch_storekit_scheme.py ProScreenshot StoreKit/ProStoreKit.storekit
"""
from __future__ import annotations

import io
import sys
from pathlib import Path

PROJECT = "ChannelTimelineViewer.xcodeproj"


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("使い方: patch_storekit_scheme.py <スキーム名> <.storekit のパス>")
    scheme_name, storekit_path = sys.argv[1], sys.argv[2]

    scheme = Path(PROJECT) / "xcshareddata" / "xcschemes" / f"{scheme_name}.xcscheme"
    if not scheme.exists():
        raise SystemExit(f"スキームがありません: {scheme}")
    if not Path(storekit_path).exists():
        raise SystemExit(f"StoreKit 設定がありません: {storekit_path}")

    text = io.open(scheme, encoding="utf-8").read()
    if "StoreKitConfigurationFileReference" in text:
        print("すでに設定済みです")
        return 0

    # 参照は .xcscheme から見た相対パス（xcschemes → xcshareddata → .xcodeproj → リポジトリ直下）。
    reference = (
        '      <StoreKitConfigurationFileReference\n'
        f'         identifier = "../../../{storekit_path}">\n'
        '      </StoreKitConfigurationFileReference>\n'
    )

    marker = "   </TestAction>"
    if marker not in text:
        raise SystemExit("TestAction が見つかりません（スキームの形が変わった可能性）")
    text = text.replace(marker, reference + marker, 1)

    io.open(scheme, "w", encoding="utf-8", newline="\n").write(text)
    print(f"{scheme.name} の TestAction に {storekit_path} を設定しました")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
