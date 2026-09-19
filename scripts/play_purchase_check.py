# -*- coding: utf-8 -*-
"""Pro（pro_unlock）の購入が確認（acknowledge）されているかを Play に問い合わせる。**読み取り専用**。

確認（acknowledge）を3日以内にしないと、Google が自動で返金して購入を取り消す。
取り消された購入は `voidedpurchases` に載るので、直近30日（API の上限）の取り消しを取り、
1件ずつ `purchases.products.get` で「確認済みだったか」を調べる。

  - 取り消しが0件、または取り消されたものがすべて確認済み
    → 3〜30日前に成立した購入はすべて確認できている（確認漏れなら取り消されて載るはず）
  - 未確認のまま取り消されたものがある → 確認漏れによる自動返金の疑い

⚠️ このリポジトリは Public で、Actions のログは誰でも読める。
   購入トークンと注文IDは**絶対に出さない**（照合にだけ使う）。出すのは日付・理由・状態だけ。

前提:
  環境変数 GOOGLE_PLAY_SERVICE_ACCOUNT_JSON（play_publish.py と同じ）。
  サービスアカウントに Play Console の「財務データの表示」または「注文の管理」の権限が要る。
"""
from __future__ import annotations

import datetime as dt
import os
import sys
import time

from googleapiclient.errors import HttpError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from play_publish import PACKAGE_NAME, service  # noqa: E402

PRODUCT_ID = "pro_unlock"
# API が受け付ける最古の開始時刻は30日前。少し余裕を持たせる。
WINDOW_DAYS = 29

VOIDED_SOURCE = {0: "利用者", 1: "開発者", 2: "Google"}
VOIDED_REASON = {
    0: "その他", 1: "気が変わった", 2: "届かなかった", 3: "不具合", 4: "誤購入",
    5: "不正", 6: "友人・家族による不正", 7: "チャージバック", 8: "未確認（acknowledge 漏れ）",
}
ACK_STATE = {0: "未確認", 1: "確認済み"}
PURCHASE_STATE = {0: "購入済み", 1: "取り消し", 2: "保留"}


def day(millis) -> str:
    if not millis:
        return "-"
    return dt.datetime.fromtimestamp(int(millis) / 1000, dt.timezone.utc).strftime("%Y-%m-%d")


def label(table: dict, value) -> str:
    if value is None:
        return "-"
    return f"{table.get(int(value), '不明')}({value})"


def main() -> int:
    api = service()
    start_ms = int((time.time() - WINDOW_DAYS * 86400) * 1000)

    voided = []
    token = None
    try:
        while True:
            kwargs = dict(packageName=PACKAGE_NAME, startTime=start_ms, type=0, maxResults=1000)
            if token:
                kwargs["token"] = token
            page = api.purchases().voidedpurchases().list(**kwargs).execute()
            voided.extend(page.get("voidedPurchases", []))
            token = (page.get("tokenPagination") or {}).get("nextPageToken")
            if not token:
                break
    except HttpError as error:
        print(f"取り消し一覧を取れませんでした: HTTP {error.resp.status} {error._get_reason()}")
        if error.resp.status in (401, 403):
            print("サービスアカウントに「財務データの表示」または「注文の管理」の権限が要ります。")
        return 1

    print(f"対象: {PACKAGE_NAME} / 期間: 直近{WINDOW_DAYS}日 / アプリ内アイテムの取り消し {len(voided)} 件")

    unacked = 0
    other_product = 0
    for index, item in enumerate(voided, 1):
        line = (f"  #{index} 購入 {day(item.get('purchaseTimeMillis'))}"
                f" → 取り消し {day(item.get('voidedTimeMillis'))}"
                f" / 取り消した人 {label(VOIDED_SOURCE, item.get('voidedSource'))}"
                f" / 理由 {label(VOIDED_REASON, item.get('voidedReason'))}")
        try:
            purchase = api.purchases().products().get(
                packageName=PACKAGE_NAME, productId=PRODUCT_ID,
                token=item["purchaseToken"]).execute()
        except HttpError as error:
            # 別の商品の購入だと 400/404 になる（このアプリの商品は pro_unlock だけのはず）。
            other_product += 1
            print(f"{line} / 確認状態: 取れず(HTTP {error.resp.status})")
            continue
        ack = purchase.get("acknowledgementState")
        if ack is not None and int(ack) == 0:
            unacked += 1
        print(f"{line} / 確認状態: {label(ACK_STATE, ack)}"
              f" / 購入状態: {label(PURCHASE_STATE, purchase.get('purchaseState'))}"
              f" / テスト購入: {'はい' if purchase.get('purchaseType') == 0 else 'いいえ'}")

    print()
    if not voided:
        print("結論: 取り消しは0件。3〜29日前に成立した購入は、すべて確認（acknowledge）できている。")
        print("     （確認漏れなら3日後に自動返金され、ここに載るため）")
    elif unacked:
        print(f"結論: 未確認のまま取り消された購入が {unacked} 件ある。確認漏れによる自動返金の疑い。")
    else:
        print("結論: 取り消しはあるが、すべて確認済みだった（確認漏れによる返金ではない）。")
    if other_product:
        print(f"注意: {other_product} 件は確認状態を取れなかった。")
    print("補足: 直近3日以内の購入は、まだ自動返金の期限前なのでこの方法では判定できない。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
