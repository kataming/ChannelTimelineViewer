# -*- coding: utf-8 -*-
"""Android のチュートリアル素材を、エミュレータから7言語ぶん撮る。

iOS は実機で撮った素材（docs/tutorial/ss/）を使うが、Android は
**端末の言語を切り替えながら撮る**必要がある。共有シートは OS の画面なので、
アプリ単位の言語設定（cmd locale set-app-locales）では切り替わらないため。

root の要らない方法として、設定アプリの「言語」画面を自動操作している
（Play ストア入りのイメージでは adb root も setprop も使えない）。

撮る4枚（iOS と同じ流れに揃える）:
  1. YouTube で動画を開いた画面（共有ボタンが見える）
  2. YouTube 自身の共有シート（「その他」が見える）
  3. Android の共有シート（本アプリが並んでいる）
  4. 本アプリが一覧を開いたところ

使い方:
    python scripts/capture_android_tutorial.py            # 全言語
    python scripts/capture_android_tutorial.py --lang ja  # 1言語だけ

前提: エミュレータが起動していて、本アプリの APK が入っていること。

⚠️ **分かっている限界（2026-09-16）**
  システム言語の切り替えと、OS の画面（共有シート・許可ダイアログ）の言語切り替えは
  この仕組みで動く。実際に英語と日本語は最後まで撮れた。

  ところが **YouTube アプリだけがシステム言語に追随しない**ことがある。
  システムを de-AT にして許可ダイアログが「Zulassen」になっていても、
  YouTube の中は日本語のまま、という状態を確認した。次はすべて試して効かなかった:
    - cmd locale set-app-locales com.google.android.youtube --locales de-DE
    - 同 --locales（空にしてシステムへ従わせる）
    - pm clear com.google.android.youtube（データごと消す）

  そのため中国語・スペイン語・ドイツ語・フランス語・韓国語は撮れていない。
  **実機で撮るのが確実**（iOS 版の素材はそうやって用意した）。
  撮ったら docs/tutorial/raw/android-<言語>-<番号>.png に置けば、
  build_tutorial_images.py がそのまま加工する。
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "docs" / "tutorial" / "raw"
ADB = Path(os.environ["LOCALAPPDATA"]) / "Android" / "Sdk" / "platform-tools" / "adb.exe"

PACKAGE = "com.deskflowlabs.channeltimelineviewer"
YOUTUBE = "com.google.android.youtube"
# 例に使うチャンネル。動画IDを直に書くと消えたときに撮れなくなるので、
# 「動画」タブを開いて**先頭の動画**を使う（iOS の素材と同じく動画から共有する）。
CHANNEL_URL = "https://www.youtube.com/@nasa"

# 言語ごとに:
#   search  … 設定アプリの「言語を追加」で検索する語（英語表記。input text は ASCII しか打てない）
#   locale  … 切り替わったか確かめるロケール
#   share   … YouTube の共有ボタンの読み上げ文（画面から探すのに使う）
#   more    … YouTube の共有シートの「その他」
# 座標を決め打ちにすると動画の中身で位置が変わるので、**文字で探して**押す。
LANGUAGES = {
    "en": dict(search="English", native="English", locale="en-US",
               share="Share", more="More"),
    "ja": dict(search="Japanese", native="日本語", locale="ja-JP",
               share="共有", more="その他"),
    "zh-Hans": dict(search="Simplified", native="中文", locale="zh-CN",
                    share="分享", more="更多"),
    "es": dict(search="Spanish", native="Español", locale="es-ES",
               share="Compartir", more="Más"),
    "de": dict(search="German", native="Deutsch", locale="de-DE",
               share="Teilen", more="Mehr"),
    "fr": dict(search="French", native="Français", locale="fr-FR",
               share="Partager", more="Plus"),
    "ko": dict(search="Korean", native="한국어", locale="ko-KR",
               share="공유", more="더보기"),
}

# 本アプリは全言語で同じ名前なので、これだけは共通で探せる。
APP_LABEL = "Channel Timeline"

# 設定アプリの「言語を追加」。設定画面はそのときのシステム言語で出るので、
# 7言語ぶんの言い方を並べて探す（言語が増えると位置がずれるため、座標は使わない）。
ADD_LANGUAGE = [
    "Add a language", "言語を追加", "添加语言",
    "Añadir un idioma", "Sprache hinzufügen", "Ajouter une langue", "언어 추가",
]


def sh(*args: str, timeout: int = 120) -> str:
    return subprocess.run([str(ADB), *args], capture_output=True, text=True,
                          timeout=timeout).stdout.strip()


def tap(x: int, y: int, wait: float = 2.0) -> None:
    sh("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def shot(name: str) -> None:
    RAW.mkdir(parents=True, exist_ok=True)
    out = RAW / name
    data = subprocess.run([str(ADB), "exec-out", "screencap", "-p"],
                          capture_output=True, timeout=120).stdout
    out.write_bytes(data)
    print(f"    撮影 {name} ({len(data) // 1024}KB)")


def dump_ui() -> str:
    """いま出ている画面の構造を読む。座標を決め打ちにしないために使う。"""
    subprocess.run([str(ADB), "shell", "uiautomator", "dump", "/sdcard/ui.xml"],
                   capture_output=True, timeout=120)
    return subprocess.run([str(ADB), "shell", "cat", "/sdcard/ui.xml"],
                          capture_output=True, text=True, timeout=120,
                          encoding="utf-8", errors="replace").stdout


def find(word: str, tries: int = 6) -> tuple[int, int] | None:
    """`word` を含む要素の中心を返す。見つかるまで少し待って読み直す。

    text と content-desc の両方を見る（YouTube はボタンを読み上げ文で持っている）。
    """
    for _ in range(tries):
        xml = dump_ui()
        for node in re.findall(r"<node[^>]*/?>", xml):
            label = " ".join(re.findall(r'(?:text|content-desc)="([^"]*)"', node))
            if word.lower() not in label.lower():
                continue
            bounds = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', node)
            if not bounds:
                continue
            x0, y0, x1, y1 = map(int, bounds.groups())
            if x1 - x0 < 8 or y1 - y0 < 8:
                continue
            return (x0 + x1) // 2, (y0 + y1) // 2
        time.sleep(3)
    return None


def tap_word(word: str, wait: float, what: str) -> bool:
    spot = find(word)
    if not spot:
        print(f"    × 『{word}』が見つからない（{what}）")
        return False
    tap(spot[0], spot[1], wait)
    return True


def find_app_in_sheet(label: str, row_y: int = 2140) -> tuple[int, int] | None:
    """共有シートの中から本アプリを探す。

    アイコンの並びは**使った回数で変わる**ので、右のほうに隠れていることがある。
    見つからなければ列を左へ送って探し直す。
    """
    for _ in range(4):
        spot = find(label, tries=1)
        if spot:
            return spot
        sh("shell", "input", "swipe", "900", str(row_y), "220", str(row_y), "400")
        time.sleep(2)
    return None


# YouTube を入れ直すと最初に通知の許可を聞いてくる。7言語ぶんの「許可しない」。
DENY_NOTICE = ("Don't allow", "許可しない", "不允许", "No permitir",
               "Nicht zulassen", "Ne pas autoriser", "허용 안 함")


def dismiss_notice() -> None:
    """通知の許可ダイアログが出ていたら断る。出ていなければ何もしない。"""
    for deny in DENY_NOTICE:
        spot = find(deny, tries=1)
        if spot:
            tap(spot[0], spot[1], 4)
            return


def current_locale() -> str:
    return sh("shell", "getprop", "persist.sys.locale")


def set_system_language(words: dict, ) -> bool:
    """設定アプリを自動操作してシステム言語を変える。

    一度使った言語は一覧に残るので、**2通り**を扱う:
      - まだ無い  … 「言語を追加」→ 検索 → 選ぶ
      - すでに有る … 一覧にあるその行を掴んで一番上へ運ぶ
    どちらも最後は「一番上へ運ぶ → 確認ダイアログで変更」で同じ。
    """
    expect, native = words["locale"], words["native"]

    def matches(now: str) -> bool:
        """言語が合っていれば地域は問わない。

        検索で「Deutsch (Österreich)」が先に出て de-AT になることがあるが、
        画面はドイツ語なので素材としては問題ない。中国語だけは簡体字かを確かめる。
        """
        if not now:
            return False
        if expect.startswith("zh"):
            return now.startswith("zh") and ("CN" in now or "Hans" in now)
        return now.split("-")[0] == expect.split("-")[0]

    if matches(current_locale()):
        print(f"    すでに {current_locale()}")
        return True

    # 前の操作で設定の下の階層に残っていることがある。ホームまで戻してから開く
    # （残っていると「言語を追加」が見つからず、関係ない行を押してしまう）。
    for _ in range(2):
        sh("shell", "input", "keyevent", "4")
    sh("shell", "input", "keyevent", "3")
    time.sleep(2)
    sh("shell", "am", "start", "-a", "android.settings.LOCALE_SETTINGS")
    time.sleep(5)

    if not find(native, tries=2):
        # 一覧に無いので追加する。
        added = False
        for label in ADD_LANGUAGE:
            spot = find(label, tries=1)
            if spot:
                tap(spot[0], spot[1], 3)
                added = True
                break
        if not added:
            print("    ×「言語を追加」が見つからない")
            return False
        tap(1015, 210, 2)      # 検索
        sh("shell", "input", "text", words["search"])  # 1単語。括弧や空白は壊れる
        time.sleep(3)
        if not tap_word(native, 5, "候補の言語"):
            return False
        time.sleep(2)

    # 一覧の中のその行を掴んで一番上へ。掴む場所は行の右端のハンドル。
    spot = find(native, tries=4)
    if not spot:
        print(f"    × 一覧に『{native}』が出てこない")
        return False
    sh("shell", "input", "swipe", "1006", str(spot[1]), "1006", "980", "1500")
    time.sleep(3)

    # 確認ダイアログ。文言は言語で変わるので、位置で押す（右下のボタン）。
    tap(883, 1524, 9)
    ok = matches(current_locale())
    print(f"    ロケール: {current_locale()} {'OK' if ok else '←期待と違う'}")
    return ok


def capture(lang: str) -> bool:
    """4枚撮る。

    動画ページは読み込みの速さで中身が変わり、座標も文字も安定しない。
    **チャンネルページ**と**共有インテント**だけを使うことで、毎回同じ画面にする。
    """
    print(f"  [{lang}]")
    words = LANGUAGES[lang]
    tag = words["locale"]
    # ⚠️ アプリ単位の言語設定は**システム言語より強い**。前の言語のまま残っていると
    #    システムを切り替えても画面がその言語のままになる（実際に日本語が残っていた）。
    #    ここでは一切使わず、必ず空にしてシステム言語に従わせる。
    sh("shell", "cmd", "locale", "set-app-locales", YOUTUBE, "--locales")
    sh("shell", "cmd", "locale", "set-app-locales", PACKAGE, "--locales")

    # 前の言語のまま動いているプロセスを畳んでから、一度だけ起動し直す。
    #   force-stop だけだと「停止状態」になり共有先の一覧から消えてしまうので、
    #   すぐ起動して停止状態を解く。これで言語も新しくなる。
    sh("shell", "am", "force-stop", PACKAGE)
    time.sleep(2)
    sh("shell", "am", "start", "-n", f"{PACKAGE}/.MainActivity")
    time.sleep(8)
    sh("shell", "input", "keyevent", "3")
    time.sleep(2)

    # 1. YouTube でチャンネルを開く
    # ⚠️ YouTube は**自分で表示言語を覚えている**。システム言語を変えても前の言語のまま
    #    出ることがあるので、データごと消してシステムに従わせる
    #    （アプリ単位のロケール設定を空にするだけでは足りなかった）。
    sh("shell", "pm", "clear", YOUTUBE, timeout=180)
    time.sleep(3)
    sh("shell", "am", "force-stop", YOUTUBE)
    # 冷えた状態から深いリンクを開くと、ホームだけ出て終わることがある。
    # チャンネル名が出るまで確かめ、出なければもう一度投げる。
    opened = False
    for attempt in range(3):
        sh("shell", "am", "start", "-a", "android.intent.action.VIEW",
           "-d", CHANNEL_URL, "-p", YOUTUBE)
        time.sleep(20 if attempt == 0 else 14)
        dismiss_notice()          # 通知の許可が被っていると中が読めない
        if find("NASA", tries=2):
            opened = True
            break
        print(f"    チャンネルが開かなかったので投げ直す（{attempt + 1}回目）")
    if not opened:
        print("    × チャンネルページを開けなかった")
        return False
    dismiss_notice()
    shot(f"android-{lang}-1.png")

    # 2. 右上の ⋮ → メニューの「共有」が見えている状態
    tap(1015, 199, 5)
    if not find(words["share"]):
        print("    × メニューに共有が出ない")
        return False
    shot(f"android-{lang}-2.png")

    # 3. 「共有」→ YouTube 自身のシート →「その他」→ Android の共有シート。
    #    ACTION_SEND を直に投げると旧式の「アプリを選択」ダイアログになってしまうので、
    #    利用者が実際に通る道をそのまま辿る。
    if not tap_word(words["share"], 7, "共有"):
        return False
    if not tap_word(words["more"], 8, "その他"):
        return False
    spot = find_app_in_sheet(APP_LABEL)
    if not spot:
        print("    × 共有シートに本アプリが見つからない（APK が入っているか確認）")
        return False
    shot(f"android-{lang}-3.png")

    # 4. 本アプリを選ぶ → 一覧が開く。
    #    一覧の取得に時間がかかるので「取得中…」が消えるまで待つ。
    tap(spot[0], spot[1], 20)
    # 一覧の取得は数十秒かかる。**言語に依存しない判定**にするため、
    # 「画面に文字を持つ要素がいくつ出たか」で数える（読み込み中は数個しか無い）。
    for _ in range(20):
        rows = len([t for t in re.findall(r'text="([^"]+)"', dump_ui()) if t.strip()])
        if rows >= 20:
            break
        time.sleep(6)
    time.sleep(3)
    shot(f"android-{lang}-4.png")
    # ⚠️ force-stop しない。停止状態のアプリは共有先の一覧に出なくなり、
    #    次の言語で「本アプリが見つからない」になる（実際にそれで失敗した）。
    sh("shell", "input", "keyevent", "3")
    time.sleep(2)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lang", help="この言語だけ撮る")
    args = parser.parse_args()

    targets = [args.lang] if args.lang else list(LANGUAGES)
    for lang in targets:
        words = LANGUAGES[lang]
        print(f"== {lang} ==")
        if not set_system_language(words):
            print("    言語を変えられなかったので、この言語は飛ばす")
            continue
        if not capture(lang):
            print(f'    ! {lang} は撮り切れなかった')
    print("完了。次に python scripts/build_tutorial_images.py --android")
    return 0


if __name__ == "__main__":
    sys.exit(main())
