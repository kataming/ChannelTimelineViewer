# -*- coding: utf-8 -*-
"""rtdn.py / main.py のテスト。標準ライブラリだけで動く。

    python cloud/play-rtdn/tests/test_rtdn.py -v
"""
from __future__ import annotations

import base64
import contextlib
import io
import json
import os
import sys
import types
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import rtdn  # noqa: E402

PACKAGE = "com.deskflowlabs.channeltimelineviewer"
# 本物に似せた、ログに出てはいけない値。
TOKEN = "SECRET-TOKEN-opaque.AO-J1Oxyz_purchase_token_must_never_be_logged"


def encode(payload) -> str:
    raw = payload if isinstance(payload, (bytes, str)) else json.dumps(payload)
    if isinstance(raw, str):
        raw = raw.encode("utf-8")
    return base64.b64encode(raw).decode("ascii")


def one_time(notification_type, sku="pro_unlock", package=PACKAGE):
    return {
        "version": "1.0",
        "packageName": package,
        "eventTimeMillis": "1758261600000",
        "oneTimeProductNotification": {
            "version": "1.0",
            "notificationType": notification_type,
            "purchaseToken": TOKEN,
            "sku": sku,
        },
    }


class Recorder:
    def __init__(self):
        self.records = []

    def __call__(self, severity, message, fields):
        self.records.append((severity, message, dict(fields)))

    def dump(self) -> str:
        return json.dumps(self.records, ensure_ascii=False)


def run(data):
    recorder = Recorder()
    label = rtdn.handle_message(data, emit=recorder)
    return label, recorder


class RtdnTest(unittest.TestCase):

    def test_test_notification_logs_fixed_label_only(self):
        label, rec = run(encode({
            "version": "1.0", "packageName": PACKAGE, "eventTimeMillis": "1",
            "testNotification": {"version": "1.0"},
        }))
        self.assertEqual(label, "RTDN_TEST_RECEIVED")
        self.assertEqual(rec.records, [("INFO", "RTDN_TEST_RECEIVED", {})])

    def test_pro_unlock_purchased(self):
        label, rec = run(encode(one_time(1)))
        self.assertEqual(label, "ONE_TIME_PRODUCT_PURCHASED")
        severity, message, fields = rec.records[0]
        self.assertEqual((severity, message), ("INFO", "ONE_TIME_PRODUCT_PURCHASED"))
        self.assertEqual(fields, {
            "packageName": PACKAGE,
            "eventTimeMillis": "1758261600000",
            "sku": "pro_unlock",
            "isProUnlock": True,
            "notificationType": 1,
        })

    def test_pro_unlock_canceled(self):
        label, rec = run(encode(one_time(2)))
        self.assertEqual(label, "ONE_TIME_PRODUCT_CANCELED")
        self.assertEqual(rec.records[0][1], "ONE_TIME_PRODUCT_CANCELED")
        self.assertEqual(rec.records[0][2]["notificationType"], 2)
        self.assertTrue(rec.records[0][2]["isProUnlock"])

    def test_other_sku_is_identifiable(self):
        label, rec = run(encode(one_time(1, sku="something_else")))
        self.assertEqual(label, "ONE_TIME_PRODUCT_PURCHASED")
        self.assertFalse(rec.records[0][2]["isProUnlock"])
        self.assertEqual(rec.records[0][2]["sku"], "something_else")

    def test_wrong_package_is_warned_and_not_processed(self):
        label, rec = run(encode(one_time(1, package="com.example.other")))
        self.assertEqual(label, "RTDN_WRONG_PACKAGE")
        self.assertEqual(rec.records, [("WARNING", "RTDN_WRONG_PACKAGE", {"packageName": "com.example.other"})])

    def test_wrong_package_with_odd_characters_is_not_echoed(self):
        label, rec = run(encode(one_time(1, package="evil\n" + TOKEN)))
        self.assertEqual(label, "RTDN_WRONG_PACKAGE")
        self.assertEqual(rec.records[0][2], {"packageName": None})

    def test_unknown_one_time_type(self):
        label, rec = run(encode(one_time(99)))
        self.assertEqual(label, "RTDN_UNKNOWN_ONE_TIME_TYPE")
        self.assertEqual(rec.records[0][0], "WARNING")
        self.assertEqual(rec.records[0][2]["notificationType"], 99)

    def test_subscription_and_voided_are_labelled_only(self):
        label, rec = run(encode({
            "packageName": PACKAGE, "eventTimeMillis": "1",
            "voidedPurchaseNotification": {"purchaseToken": TOKEN, "orderId": "GPA.1234"},
        }))
        self.assertEqual(label, "RTDN_UNHANDLED_KIND")
        self.assertEqual(rec.records[0][2]["kind"], "voidedPurchaseNotification")

    def test_malformed_payloads(self):
        cases = {
            "not base64 !!!": "RTDN_DECODE_ERROR",
            encode(b"\xff\xfe\x00bad"): "RTDN_DECODE_ERROR",
            encode("{not json " + TOKEN): "RTDN_MALFORMED_JSON",
            encode("[1, 2, 3]"): "RTDN_MALFORMED_JSON",
            encode({"packageName": PACKAGE, "oneTimeProductNotification": "x"}): "RTDN_MALFORMED_JSON",
            "": "RTDN_DECODE_ERROR",
            None: "RTDN_DECODE_ERROR",
            "A" * (rtdn.MAX_DATA_CHARS + 4): "RTDN_DECODE_ERROR",
        }
        for data, expected in cases.items():
            with self.subTest(data=str(data)[:30]):
                label, rec = run(data)
                self.assertEqual(label, expected)
                self.assertEqual(rec.records[0][0], "ERROR")
                # 出すのは例外の種類だけ。
                self.assertEqual(set(rec.records[0][2]), {"errorType"})
                self.assertNotIn(TOKEN, rec.dump())

    def test_purchase_token_never_reaches_logs(self):
        payloads = [
            one_time(1), one_time(2), one_time(99), one_time(1, sku="x"),
            one_time(1, package="com.example.other"),
            {"packageName": PACKAGE, "voidedPurchaseNotification": {"purchaseToken": TOKEN}},
            {"packageName": PACKAGE, "subscriptionNotification": {"purchaseToken": TOKEN}},
            {"packageName": PACKAGE, "whatever": {"purchaseToken": TOKEN}},
        ]
        for payload in payloads:
            data = encode(payload)
            # 実際の標準出力（Cloud Logging に行くもの）で確かめる。
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                rtdn.handle_message(data)
            text = out.getvalue()
            self.assertTrue(text.strip(), "何かしらのログは出る")
            self.assertNotIn(TOKEN, text)
            self.assertNotIn("purchaseToken", text)
            # 生のメッセージ（Base64）も出さない。
            self.assertNotIn(data, text)
            for line in text.splitlines():
                json.loads(line)  # 1行1 JSON（Cloud Logging の構造化ログ）


class MainEntryTest(unittest.TestCase):
    """main.py の入口。functions_framework は入れずに、飾りだけ差し替えて試す。"""

    @classmethod
    def setUpClass(cls):
        fake = types.ModuleType("functions_framework")
        fake.cloud_event = lambda fn: fn
        sys.modules.setdefault("functions_framework", fake)
        import main  # noqa: E402
        cls.main = main

    def call(self, event_data):
        event = types.SimpleNamespace(data=event_data)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.main.on_play_rtdn(event)
        return [json.loads(line) for line in out.getvalue().splitlines()]

    def test_purchased_via_cloud_event(self):
        records = self.call({"message": {"data": encode(one_time(1)), "messageId": "1"},
                             "subscription": "projects/x/subscriptions/y"})
        self.assertEqual(records[0]["message"], "ONE_TIME_PRODUCT_PURCHASED")
        self.assertEqual(records[0]["severity"], "INFO")
        self.assertNotIn(TOKEN, json.dumps(records))

    def test_missing_message_is_safe(self):
        for event_data in (None, {}, {"message": "x"}, {"message": {}}):
            with self.subTest(event_data=event_data):
                records = self.call(event_data)
                self.assertEqual(records[0]["message"], "RTDN_DECODE_ERROR")


if __name__ == "__main__":
    unittest.main()
