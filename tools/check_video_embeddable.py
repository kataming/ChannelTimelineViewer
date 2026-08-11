# -*- coding: utf-8 -*-
"""特定の動画が「埋め込み再生可能か」を YouTube Data API v3 で確認する。

再生画面が「この動画は再生できません（エラーコード 152-x）」になる原因が
  (A) 動画側で埋め込みが禁止されている  なのか
  (B) こちらのプレイヤー実装（origin/referrer など）の問題  なのか
を切り分けるために使う。

使い方:
    # タイトルの一部から探す（search は 100 units 消費する）
    python tools/check_video_embeddable.py --api-key-file <keyfile> --query "落とし穴"

    # 動画IDが分かっている場合（1 unit）
    python tools/check_video_embeddable.py --api-key-file <keyfile> --id dQw4w9WgXcQ
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


def show(ids: list[str], key: str) -> None:
    if not ids:
        print("対象の動画がありません")
        return
    res = get("videos", {"part": "status,snippet,contentDetails",
                         "id": ",".join(ids), "key": key})
    for v in res.get("items", []):
        st = v["status"]
        cd = v.get("contentDetails", {})
        print(f"\n  ID          : {v['id']}")
        print(f"  タイトル    : {v['snippet']['title'][:60]}")
        print(f"  公開日      : {v['snippet']['publishedAt']}")
        print(f"  embeddable  : {st.get('embeddable')}   <- False なら埋め込み禁止")
        print(f"  privacy     : {st.get('privacyStatus')}")
        print(f"  uploadStatus: {st.get('uploadStatus')}")
        print(f"  地域制限    : {cd.get('regionRestriction')}")
        print(f"  年齢制限    : {cd.get('contentRating', {}).get('ytRating')}")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--api-key-file", required=True, type=Path)
    p.add_argument("--id", action="append", default=[])
    p.add_argument("--query")
    p.add_argument("--channel-id")
    a = p.parse_args()

    key = a.api_key_file.read_text(encoding="utf-8").strip()
    ids = list(a.id)

    if a.query:
        params = {"part": "snippet", "q": a.query, "type": "video",
                  "maxResults": "5", "key": key}
        if a.channel_id:
            params["channelId"] = a.channel_id
        res = get("search", params)
        for item in res.get("items", []):
            ids.append(item["id"]["videoId"])
            print(f"見つかった: {item['snippet']['title'][:60]}")

    show(ids, key)


if __name__ == "__main__":
    sys.exit(main())
