# -*- coding: utf-8 -*-
"""「YouTube の共有から追加する」の案内アニメの素材を、USB でつないだ実機で撮る。

前提:
  - 端末の言語を撮りたい言語にしてある（Android 10 の実機では、検証用の補助アプリで切り替えた）
  - 検証用の試験版（.adstest）が入っている（③の「アプリに戻る」通知を出すのに使う）

NASA の動画を YouTube アプリで開き、次の3枚を docs/tutorial/raw/copyguide-<言語>-<番号>.png に保存する:
  1 … 動画の画面   2 … ［共有］を押したところ
  3 … ［コピー］を押したあと、通知の一覧を引き下ろして「アプリに戻る」が見えているところ

使い方: python scripts/capture_copy_guide.py <言語> [端末のシリアル]
撮れたら、python scripts/build_copy_guide_frames.py <言語> で加工する。
押す位置は 720x1520 の実機（Rakuten Hand 5G）で合わせてある。別の機種なら TAP_* を直すこと。
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "tutorial" / "raw"
ADB = os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe")
VIDEO = "https://www.youtube.com/watch?v=7ZiUbT1-djA"  # NASA's SpaceX Crew-13 Launch
APP = "com.deskflowlabs.channeltimelineviewer.adstest"
TAP_SHARE = (530, 643)
TAP_COPY = (200, 1120)


def main() -> int:
    lang = sys.argv[1]
    serial = sys.argv[2] if len(sys.argv) > 2 else "103e6e96"

    def adb(*args) -> str:
        return subprocess.run([ADB, "-s", serial, *args], capture_output=True, text=True,
                              encoding="utf-8", errors="ignore").stdout

    def shot(n: int):
        data = subprocess.run([ADB, "-s", serial, "exec-out", "screencap", "-p"], capture_output=True).stdout
        out = RAW / f"copyguide-{lang}-{n}.png"
        out.write_bytes(data)
        print("  ", out.relative_to(ROOT))

    def tap_text(pattern: str, tries: int = 6) -> bool:
        """画面の文字（正規表現）を探して押す。見つからなければ False。"""
        for _ in range(tries):
            adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
            xml = adb("shell", "cat", "/sdcard/ui.xml")
            m = re.search(r'text="(?:' + pattern + r')"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', xml)
            if m:
                l, t, r, b = map(int, m.groups())
                adb("shell", "input", "tap", str((l + r) // 2), str((t + b) // 2))
                return True
            time.sleep(1.5)
        return False

    RAW.mkdir(parents=True, exist_ok=True)
    # 試験版で「アプリに戻る」の通知だけを出す（デバッグ専用の起動オプション）。
    adb("shell", "pm", "grant", APP, "android.permission.POST_NOTIFICATIONS")
    adb("shell", "am", "start", "-n", f"{APP}/com.deskflowlabs.channeltimelineviewer.MainActivity",
        "--ez", "postCopyGuideNotification", "true")
    time.sleep(3)

    # 言語を変えたあとは YouTube を一度終了しないと、前の言語のまま表示される。
    adb("shell", "am", "force-stop", "com.google.android.youtube")
    adb("shell", "am", "start", "-a", "android.intent.action.VIEW", "-d", VIDEO, "-p", "com.google.android.youtube")
    time.sleep(12)
    shot(1)
    adb("shell", "input", "tap", *map(str, TAP_SHARE))
    time.sleep(3)
    shot(2)
    adb("shell", "input", "tap", *map(str, TAP_COPY))
    time.sleep(2.5)
    adb("shell", "cmd", "statusbar", "expand-notifications")
    time.sleep(2)
    shot(3)
    adb("shell", "cmd", "statusbar", "collapse")
    adb("shell", "input", "keyevent", "4")
    return 0


if __name__ == "__main__":
    sys.exit(main())
