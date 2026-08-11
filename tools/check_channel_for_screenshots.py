# -*- coding: utf-8 -*-
"""スクリーンショット撮影に向いたチャンネルかどうかを YouTube Data API v3 で下調べする。

見るもの:
  - 動画本数（進捗バーに意味のある数字が出るか。数千本あると「3 / 5,000本（0%）」になってしまう）
  - 先頭の数本が **埋め込み再生可能か**（status.embeddable）
    → 埋め込み不可の動画だと再生画面が「This video is unavailable」になる

APIキーはコマンドラインに書かず、ファイルから読む（履歴に残さないため）。

使い方:
    python tools/check_channel_for_screenshots.py --api-key-file <キーを書いたファイル> \
        --handle @3blue1brown --handle @NASA
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://www.googleapis.com/youtube/v3"


def get(path: str, params: dict) -> dict:
    url = f"{API}/{path}?{urllib.parse.urlencode(params)}"
    with urllib.request.urlopen(url, timeout=30) as r:
        return json.loads(r.read())


def inspect(handle: str, key: str, sample: int = 5) -> None:
    print(f"\n=== {handle} ===")
    h = handle if handle.startswith("@") else "@" + handle
    ch = get("channels", {"part": "contentDetails,statistics,snippet",
                          "forHandle": h, "key": key})
    items = ch.get("items") or []
    if not items:
        print("  チャンネルが見つかりません")
        return
    it = items[0]
    title = it["snippet"]["title"]
    total = it["statistics"].get("videoCount", "?")
    uploads = it["contentDetails"]["relatedPlaylists"]["uploads"]
    print(f"  タイトル : {title}")
    print(f"  動画本数 : {total}")

    # uploads プレイリストの先頭（＝最新側）から数本サンプリング
    pl = get("playlistItems", {"part": "contentDetails", "playlistId": uploads,
                               "maxResults": str(sample), "key": key})
    ids = [x["contentDetails"]["videoId"] for x in pl.get("items", [])]
    if not ids:
        print("  動画が取得できませんでした")
        return

    vids = get("videos", {"part": "status,snippet", "id": ",".join(ids), "key": key})
    ok = 0
    print(f"  埋め込み可否（サンプル{len(ids)}本）:")
    for v in vids.get("items", []):
        embeddable = v["status"].get("embeddable")
        ok += 1 if embeddable else 0
        mark = "○" if embeddable else "×"
        print(f"    {mark} {v['snippet']['title'][:48]}")
    print(f"  → 埋め込み可: {ok}/{len(vids.get('items', []))}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--api-key-file", required=True, type=Path)
    p.add_argument("--handle", action="append", required=True)
    p.add_argument("--sample", type=int, default=5)
    a = p.parse_args()

    key = a.api_key_file.read_text(encoding="utf-8").strip()
    for h in a.handle:
        try:
            inspect(h, key, a.sample)
        except Exception as e:  # noqa: BLE001 - 下調べ用なので握りつぶして次へ
            print(f"  エラー: {e}")


if __name__ == "__main__":
    sys.exit(main())
