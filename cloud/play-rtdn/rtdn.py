# -*- coding: utf-8 -*-
"""Google Play RTDN（リアルタイム デベロッパー通知）を読んで、ログに1行残すだけの処理。

目的は**診断**。Firebase Analytics の in_app_purchase とは別の経路で、
「Play 側で pro_unlock の購入成功（ONE_TIME_PRODUCT_PURCHASED）が本当に起きているか」を確かめる。

⚠️ ログに出してよいのは次だけ（それ以外は何があっても出さない）:
   packageName / eventTimeMillis / sku / notificationType / 固定ラベル
   - purchaseToken は受け取っても**絶対に出さない**（購入の鍵そのもの）
   - Pub/Sub の生メッセージや RTDN の JSON 全文も出さない
   - 失敗時も例外の「種類」だけを出し、例外の文面（中身の断片が混ざりうる）は出さない

重複について: Play と Pub/Sub はどちらも「少なくとも1回」届ける設計なので、同じ通知が
何度も来ることがある。いまは診断用なので数えるときに気をつけるだけにして、重複排除はしない。

このファイルは標準ライブラリだけで書く（テストを外部依存なしで回すため）。
Cloud Functions の入口は main.py。
"""
from __future__ import annotations

import base64
import binascii
import json
import re
import sys
from typing import Any, Callable, Dict, Optional

EXPECTED_PACKAGE = "com.deskflowlabs.channeltimelineviewer"
PRO_SKU = "pro_unlock"

# oneTimeProductNotification.notificationType
ONE_TIME_TYPES = {
    1: "ONE_TIME_PRODUCT_PURCHASED",
    2: "ONE_TIME_PRODUCT_CANCELED",
}

# RTDN が持ちうる通知の種類。今回扱うのは test と oneTimeProduct だけで、
# 残りは「来たこと」だけを固定ラベルで残す。
OTHER_KINDS = (
    "subscriptionNotification",
    "voidedPurchaseNotification",
)

# ログに出す値は、形が決まっているものだけを通す。
# 受け取った値は外から来たものなので、長さと文字種を絞ってから出す。
_PACKAGE_RE = re.compile(r"^[A-Za-z0-9_.]{1,150}$")
_SKU_RE = re.compile(r"^[A-Za-z0-9_.]{1,150}$")
_DIGITS_RE = re.compile(r"^[0-9]{1,20}$")

# Pub/Sub のメッセージ本体の上限は 10MB。RTDN は数百バイトなので、大きすぎるものは読まない。
MAX_DATA_CHARS = 64 * 1024

Emit = Callable[[str, str, Dict[str, Any]], None]


def stdout_emit(severity: str, message: str, fields: Dict[str, Any]) -> None:
    """Cloud Logging が構造化ログとして読める形（1行の JSON）で標準出力へ書く。"""
    record = {"severity": severity, "message": message}
    record.update(fields)
    sys.stdout.write(json.dumps(record, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def _safe(value: Any, pattern: re.Pattern) -> Optional[str]:
    """決まった形の文字列だけを返す。それ以外は None（＝ログに出さない）。"""
    if isinstance(value, int) and not isinstance(value, bool):
        value = str(value)
    if isinstance(value, str) and pattern.match(value):
        return value
    return None


def _decode(data: Any) -> Any:
    """Pub/Sub の data（Base64）→ JSON。失敗したら ValueError の仲間を投げる。"""
    if isinstance(data, (bytes, bytearray)):
        data = bytes(data).decode("ascii")
    if not isinstance(data, str) or not data:
        raise ValueError("empty")
    if len(data) > MAX_DATA_CHARS:
        raise ValueError("too large")
    raw = base64.b64decode(data, validate=True)
    return json.loads(raw.decode("utf-8"))


def handle_message(data: Any, emit: Emit = stdout_emit) -> str:
    """Pub/Sub メッセージの data を1件処理し、残したログの見出し（固定ラベル）を返す。

    例外は外へ投げない。投げると Pub/Sub が同じ壊れた通知を再送し続けるため、
    読めないものは「読めなかった」と記録して受け取り済みにする。
    """
    try:
        payload = _decode(data)
    except (ValueError, UnicodeDecodeError, binascii.Error) as error:
        # json.JSONDecodeError も ValueError の仲間。文面は出さず、種類だけ。
        label = "RTDN_MALFORMED_JSON" if isinstance(error, json.JSONDecodeError) else "RTDN_DECODE_ERROR"
        emit("ERROR", label, {"errorType": type(error).__name__})
        return label

    if not isinstance(payload, dict):
        emit("ERROR", "RTDN_MALFORMED_JSON", {"errorType": "NotAnObject"})
        return "RTDN_MALFORMED_JSON"

    package = _safe(payload.get("packageName"), _PACKAGE_RE)
    event_time = _safe(payload.get("eventTimeMillis"), _DIGITS_RE)

    if package != EXPECTED_PACKAGE:
        # 形の崩れた packageName はそのまま出さない（None として出る）。
        emit("WARNING", "RTDN_WRONG_PACKAGE", {"packageName": package})
        return "RTDN_WRONG_PACKAGE"

    if "testNotification" in payload:
        emit("INFO", "RTDN_TEST_RECEIVED", {})
        return "RTDN_TEST_RECEIVED"

    notification = payload.get("oneTimeProductNotification")
    if notification is not None:
        if not isinstance(notification, dict):
            emit("ERROR", "RTDN_MALFORMED_JSON", {"errorType": "BadOneTimeProduct"})
            return "RTDN_MALFORMED_JSON"
        raw_type = notification.get("notificationType")
        notification_type = raw_type if isinstance(raw_type, int) and not isinstance(raw_type, bool) else None
        sku = _safe(notification.get("sku"), _SKU_RE)
        fields = {
            "packageName": package,
            "eventTimeMillis": event_time,
            "sku": sku,
            "isProUnlock": sku == PRO_SKU,
            "notificationType": notification_type,
        }
        # purchaseToken はここで一切触らない（次フェーズの Developer API 検証で使う）。
        label = ONE_TIME_TYPES.get(notification_type)
        if label is None:
            emit("WARNING", "RTDN_UNKNOWN_ONE_TIME_TYPE", fields)
            return "RTDN_UNKNOWN_ONE_TIME_TYPE"
        emit("INFO", label, fields)
        return label

    for kind in OTHER_KINDS:
        if kind in payload:
            emit("INFO", "RTDN_UNHANDLED_KIND",
                 {"packageName": package, "eventTimeMillis": event_time, "kind": kind})
            return "RTDN_UNHANDLED_KIND"

    emit("WARNING", "RTDN_UNKNOWN_KIND", {"packageName": package, "eventTimeMillis": event_time})
    return "RTDN_UNKNOWN_KIND"
