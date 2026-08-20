# -*- coding: utf-8 -*-
"""つないだ Android 実機から、Google Play 用のスクリーンショットを言語別に撮る。

アプリのデバッグビルドに入れてある「表示言語の切り替え」（`--es locale <言語>`）を使うので、
端末の言語設定を変えずに7言語ぶんを撮れる。

前提:
  - USB デバッグを許可した端末が1台つながっている
  - **CI でビルドした APK**（APIキー入り）が入っている
  - 撮影に使うチャンネルを一度開いてキャッシュしてある（既定は NASA）

使い方:
    python scripts/capture_play_screenshots.py                # 全7言語
    python scripts/capture_play_screenshots.py --locales ja   # 一部だけ
出力:
    docs/PlayStore/screenshots/<ロケール>/01-home.png ほか
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "PlayStore" / "screenshots"
ADB = Path.home() / "AppData/Local/Android/Sdk/platform-tools/adb.exe"
PACKAGE = "com.deskflowlabs.channeltimelineviewer"
ACTIVITY = f"{PACKAGE}/.MainActivity"

# 表示言語（アプリ内） → Play のロケール名
LOCALES = {
    "ja": "ja-JP",
    "en": "en-US",
    "zh-Hans": "zh-CN",
    "es": "es-ES",
    "de": "de-DE",
    "fr": "fr-FR",
    "ko": "ko-KR",
}

# 画面上の位置（720×1520 の端末で確認した値）。別解像度の端末では調整が要る。
# 「次に見る」の行は進捗ヘッダーの下に固定で出るので、言語が変わっても位置は動かない。
TAP_NEXT_ROW = (360, 393)


def adb(*args: str, capture: bool = False) -> bytes:
    command = [str(ADB), *args]
    if capture:
        return subprocess.run(command, capture_output=True, timeout=180).stdout
    subprocess.run(command, capture_output=True, timeout=180)
    return b""


# ストア用に落とす帯（この端末の実測値）。
# 上=ステータスバー（時刻・電波）、下=ナビゲーションバー。
# 落とすと見た目が締まるうえ、縦横比が Play の上限（2:1）に収まる。
STATUS_BAR_HEIGHT = 48
NAVIGATION_BAR_HEIGHT = 96


def screencap(path: Path, trim: bool = True) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(adb("exec-out", "screencap", "-p", capture=True))
    if not trim:
        return
    try:
        from PIL import Image
    except ImportError:
        return
    with Image.open(path) as image:
        width, height = image.size
        # 端末が横向きだと Play の規格（縦長・縦横比 2.3 以内）を満たさない。
        # 撮り直しに気づけるよう、ここで弾いて例外にする。
        if width >= height:
            message = (
                "横向きで撮れています（{}×{}）: {}".format(width, height, path)
                + " / 端末の画面回転を縦に固定してから撮り直してください。"
            )
            raise SystemExit(message)
        box = (0, STATUS_BAR_HEIGHT, width, height - NAVIGATION_BAR_HEIGHT)
        image.crop(box).save(path)


def launch(app_locale: str, share_url: str | None = None) -> None:
    """指定の言語でアプリを開く。share_url を渡すと、そのチャンネルを直接開く。"""
    adb("shell", "am", "force-stop", PACKAGE)
    time.sleep(1)
    args = ["shell", "am", "start", "-n", ACTIVITY, "--es", "locale", app_locale]
    if share_url:
        # 共有と同じ経路で開く。行の位置に依存しないので、言語が変わっても確実に同じ画面になる。
        args = [
            "shell", "am", "start",
            "-a", "android.intent.action.SEND",
            "-t", "text/plain",
            "--es", "android.intent.extra.TEXT", share_url,
            "--es", "locale", app_locale,
            "-n", ACTIVITY,
        ]
    adb(*args)


def capture_locale(app_locale: str, play_locale: str, channel_url: str) -> None:
    out = OUT_DIR / play_locale
    print(f"  {play_locale}: 撮影中…")

    # 1) ホーム（最近使ったチャンネル）
    launch(app_locale)
    time.sleep(4)
    screencap(out / "01-home.png")

    # 2) 一覧（共有と同じ経路で開くので、行の位置に左右されない）
    launch(app_locale, channel_url)
    time.sleep(12)
    screencap(out / "02-list.png")

    # 3) 再生画面
    adb("shell", "input", "tap", str(TAP_NEXT_ROW[0]), str(TAP_NEXT_ROW[1]))
    time.sleep(14)
    screencap(out / "03-player.png")

    # 4) 再生画面を下へスクロールして、移動ボタンとメモが見える位置
    adb("shell", "input", "swipe", "360", "1100", "360", "760", "300")
    time.sleep(2)
    screencap(out / "04-player-controls.png")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--locales", default="", help="カンマ区切り（例 ja,en）。空なら全部")
    parser.add_argument("--channel", default="https://www.youtube.com/@NASA",
                        help="撮影に使うチャンネル（あらかじめ開いてキャッシュしておく）")
    args = parser.parse_args()

    if not ADB.exists():
        print(f"adb が見つかりません: {ADB}")
        return 1
    devices = adb("devices", capture=True).decode(errors="replace")
    if "\tdevice" not in devices:
        print("端末がつながっていません（USB デバッグの許可も確認してください）")
        return 1

    wanted = [item.strip() for item in args.locales.split(",") if item.strip()] or list(LOCALES)
    for app_locale in wanted:
        play_locale = LOCALES.get(app_locale)
        if play_locale is None:
            print(f"  {app_locale}: 対応していない言語です")
            continue
        capture_locale(app_locale, play_locale, args.channel)

    print(f"\n出力先: {OUT_DIR.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
