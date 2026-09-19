# -*- coding: utf-8 -*-
"""Cloud Run functions（第2世代 Cloud Functions）の入口。

Pub/Sub トピック ctv-play-billing-rtdn に届いた通知を Eventarc 経由で受け取り、
rtdn.handle_message に渡すだけ。中身の判断はすべて rtdn.py にある。
デプロイ手順は README.md。
"""
from __future__ import annotations

import functions_framework

from rtdn import handle_message, stdout_emit


def extract_data(event_data):
    """CloudEvent の data から Pub/Sub メッセージの data（Base64 文字列）を取り出す。"""
    if not isinstance(event_data, dict):
        return None
    message = event_data.get("message")
    if not isinstance(message, dict):
        return None
    return message.get("data")


@functions_framework.cloud_event
def on_play_rtdn(cloud_event):
    # 例外は投げない（投げると Pub/Sub が同じ通知を再送し続ける）。
    try:
        handle_message(extract_data(cloud_event.data))
    except Exception as error:  # noqa: BLE001 — 最後の蓋。文面は出さず種類だけ。
        stdout_emit("ERROR", "RTDN_HANDLER_ERROR", {"errorType": type(error).__name__})
