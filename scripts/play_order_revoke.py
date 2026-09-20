# -*- coding: utf-8 -*-
"""テスト購入を払い戻して取り消す（`pro_unlock` を買い直せる状態に戻すため）。

買い切り商品は1アカウントにつき1回しか買えないので、購入フローを実機で試し直すには
いったん**払い戻し＋取り消し（revoke）**が要る（Play の公式手順）。
Play Console の「注文管理」からでもできるが、画面が開けないときはこちらから実行する。

⚠️ これは**お金に関わる操作**で、元には戻せない。対象は1件だけで、注文IDは環境変数から取る。
⚠️ このリポジトリは Public で Actions のログは誰でも読める。**注文IDは伏せて表示する。**

前提:
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON  サービスアカウント（play_publish.py と同じ）
  PLAY_ORDER_ID                     払い戻す注文ID（GPA.xxxx-xxxx-xxxx-xxxxx）
  サービスアカウントに Play Console の「注文と定期購入の管理」権限が要る
  （「売上データの閲覧」だけでは払い戻しできない）。
"""
from __future__ import annotations

import os
import re
import sys

from googleapiclient.errors import HttpError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from play_publish import PACKAGE_NAME, service  # noqa: E402

ORDER_ID_RE = re.compile(r"^GPA\.[0-9-]{10,40}$")


def masked(order_id: str) -> str:
    """ログに出す用。末尾4桁だけ残す（どの注文かは分かるが、そのままは出さない）。"""
    return "GPA.****-****-****-" + order_id[-4:]


def main() -> int:
    order_id = os.environ.get("PLAY_ORDER_ID", "").strip()
    if not ORDER_ID_RE.match(order_id):
        print("PLAY_ORDER_ID が未設定か、形が違います（GPA. で始まる注文ID）。")
        return 1

    api = service()
    print(f"対象: {PACKAGE_NAME} / 注文 {masked(order_id)}")
    print("払い戻して、アイテムの所有も取り消します（revoke=true）。")

    try:
        api.orders().refund(
            packageName=PACKAGE_NAME, orderId=order_id, revoke=True).execute()
    except HttpError as error:
        print(f"できませんでした: HTTP {error.resp.status} {error._get_reason()}")
        if error.resp.status in (401, 403):
            print("サービスアカウントに「注文と定期購入の管理」権限が要ります。")
        elif error.resp.status == 404:
            print("その注文IDが見つかりません（別のアプリの注文か、入力違いの可能性）。")
        return 1

    print("完了しました。数分で端末側の Pro が外れます。")
    print("アプリを開き直すか、Pro 画面の「購入を復元」を押すと反映されます。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
