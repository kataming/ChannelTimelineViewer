# -*- coding: utf-8 -*-
"""`pro_unlock` の割引特典（1回限りのアイテムのオファー）を Play へ作る。

背景: 購入試行は起きているのに実売が0件だったため、価格が壁になっていないかを試す
（2026-09-21・ユーザー判断）。対象は価格感度の高い新興国6か国・50%OFF・1か月。

⚠️ 割引が効くのは **Android 1.11 以降**を入れている人だけ。それ以前の版は
   オファーを読まないので通常価格のまま（`android/app/.../billing/OfferSelection.kt`）。

使い方:
  --mode show     いまの購入オプションとオファーを読むだけ（変更しない）
  --mode create   割引オファーを**下書き**で作る（まだ配信されない）
  --mode activate 下書きのオファーを有効にする（ここから実際に割引になる）
  --mode deactivate 有効なオファーを止める

前提: GOOGLE_PLAY_SERVICE_ACCOUNT_JSON（play_publish.py と同じ）。
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys

from googleapiclient.errors import HttpError

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from play_publish import PACKAGE_NAME, service  # noqa: E402

PRODUCT_ID = "pro_unlock"
OFFER_ID = "emerging-50off-2026-09"

# 価格感度の高い新興国（ユーザー選択・2026-09-21）。
# バングラデシュ / インド / パキスタン / ナイジェリア / フィリピン / ベトナム
REGIONS = ["BD", "IN", "PK", "NG", "PH", "VN"]

# 0 < x < 1。0.5 = 50%OFF。
RELATIVE_DISCOUNT = 0.5

# 期間（1か月）。開始は作成時刻の少し先にして、作った瞬間に始まらないようにする。
DURATION_DAYS = 30
START_DELAY_MINUTES = 30


def monetization(api):
    return api.monetization().onetimeproducts()


def purchase_options(api) -> list:
    product = monetization(api).get(
        packageName=PACKAGE_NAME, productId=PRODUCT_ID).execute()
    return product.get("purchaseOptions", []), product


def show(api) -> int:
    options, product = purchase_options(api)
    print(f"商品: {PRODUCT_ID} / 状態: {product.get('state')}")
    print(f"購入オプション: {len(options)} 件")
    for option in options:
        print(f"  - id={option.get('purchaseOptionId')} 状態={option.get('state')} "
              f"種別={'buy' if 'buyOption' in option else 'rent' if 'rentOption' in option else '?'}")

    for option in options:
        option_id = option.get("purchaseOptionId")
        offers = monetization(api).purchaseOptions().offers().list(
            packageName=PACKAGE_NAME, productId=PRODUCT_ID,
            purchaseOptionId=option_id).execute().get("oneTimeProductOffers", [])
        print(f"\n購入オプション {option_id} のオファー: {len(offers)} 件")
        for offer in offers:
            regions = [c.get("regionCode") for c in offer.get("regionalPricingAndAvailabilityConfigs", [])]
            discounted = offer.get("discountedOffer", {})
            print(f"  - id={offer.get('offerId')} 状態={offer.get('state')} "
                  f"地域={len(regions)}件{regions[:8]} "
                  f"期間={discounted.get('startTime')}〜{discounted.get('endTime')}")
    return 0


# 監査で必ず見る国（ここだけ価格を抜き出して出す）。
AUDIT_REGIONS = ["BD", "IN", "US", "JP"]


def raw(api) -> int:
    """商品とオファーの中身を読むだけ。価格は公開情報なのでそのまま出してよい。"""
    options, product = purchase_options(api)
    print("== 商品 ==")
    print(json.dumps({k: v for k, v in product.items() if k != "purchaseOptions"},
                     ensure_ascii=False, indent=2)[:2000])

    for option in options:
        option_id = option.get("purchaseOptionId")
        configs = option.get("regionalPricingAndAvailabilityConfigs", [])
        print("")
        print(f"== 購入オプション {option_id} ==")
        print(json.dumps({k: v for k, v in option.items()
                          if k != "regionalPricingAndAvailabilityConfigs"},
                         ensure_ascii=False, indent=2))
        print(f"  地域別の価格と提供状況: {len(configs)} 件")
        for config in configs:
            if config.get("regionCode") in AUDIT_REGIONS:
                print("   ", json.dumps(config, ensure_ascii=False))

        offers = monetization(api).purchaseOptions().offers().list(
            packageName=PACKAGE_NAME, productId=PRODUCT_ID,
            purchaseOptionId=option_id).execute().get("oneTimeProductOffers", [])
        for offer in offers:
            offer_configs = offer.get("regionalPricingAndAvailabilityConfigs", [])
            print("")
            print(f"== オファー {offer.get('offerId')} ==")
            print(json.dumps({k: v for k, v in offer.items()
                              if k != "regionalPricingAndAvailabilityConfigs"},
                             ensure_ascii=False, indent=2))
            print(f"  地域別: {len(offer_configs)} 件")
            for config in offer_configs:
                print("   ", json.dumps(config, ensure_ascii=False))
    return 0


def build_offer(option_id: str) -> dict:
    # Play は「分ちょうど」しか受け付けない（秒が入ると 400）。
    now = dt.datetime.now(dt.timezone.utc).replace(second=0, microsecond=0)
    start = now + dt.timedelta(minutes=START_DELAY_MINUTES)
    end = start + dt.timedelta(days=DURATION_DAYS)
    stamp = "%Y-%m-%dT%H:%M:%SZ"
    return {
        "packageName": PACKAGE_NAME,
        "productId": PRODUCT_ID,
        "purchaseOptionId": option_id,
        "offerId": OFFER_ID,
        "regionalPricingAndAvailabilityConfigs": [
            {
                "regionCode": region,
                "availability": "AVAILABLE",
                "relativeDiscount": RELATIVE_DISCOUNT,
            }
            for region in REGIONS
        ],
        "discountedOffer": {
            "startTime": start.strftime(stamp),
            "endTime": end.strftime(stamp),
        },
    }


def create(api, dry_run: bool) -> int:
    options, _ = purchase_options(api)
    buy = next((o for o in options if "buyOption" in o), None) or (options[0] if options else None)
    if buy is None:
        print("購入オプションが見つかりません（先に商品を作ってください）。")
        return 1
    option_id = buy.get("purchaseOptionId")
    offer = build_offer(option_id)

    print(f"購入オプション {option_id} に、割引オファー {OFFER_ID} を作ります。")
    print(f"  対象: {', '.join(REGIONS)} / {int(RELATIVE_DISCOUNT * 100)}%OFF")
    print(f"  期間: {offer['discountedOffer']['startTime']} 〜 {offer['discountedOffer']['endTime']}")
    if dry_run:
        print("  [dry-run] 送信しません。")
        print(json.dumps(offer, ensure_ascii=False, indent=2))
        return 0

    result = monetization(api).purchaseOptions().offers().batchUpdate(
        packageName=PACKAGE_NAME, productId=PRODUCT_ID, purchaseOptionId=option_id,
        body={
            "requests": [{
                "oneTimeProductOffer": offer,
                "updateMask": "regionalPricingAndAvailabilityConfigs,discountedOffer",
                "allowMissing": True,
                "regionsVersion": {"version": "2022/02"},
            }],
        },
    ).execute()
    for created in result.get("oneTimeProductOffers", []):
        print(f"  作成しました: {created.get('offerId')} / 状態 {created.get('state')}")
    print("※ 状態が DRAFT のあいだは配信されません。--mode activate で有効にします。")
    return 0


def set_state(api, activate: bool) -> int:
    options, _ = purchase_options(api)
    buy = next((o for o in options if "buyOption" in o), None) or (options[0] if options else None)
    if buy is None:
        print("購入オプションが見つかりません。")
        return 1
    option_id = buy.get("purchaseOptionId")
    offers = monetization(api).purchaseOptions().offers()
    call = offers.activate if activate else offers.deactivate
    result = call(
        packageName=PACKAGE_NAME, productId=PRODUCT_ID,
        purchaseOptionId=option_id, offerId=OFFER_ID, body={}).execute()
    print(f"{OFFER_ID} の状態: {result.get('state')}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["show", "raw", "create", "activate", "deactivate"],
                        default="show")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    api = service()
    try:
        if args.mode == "show":
            return show(api)
        if args.mode == "raw":
            return raw(api)
        if args.mode == "create":
            return create(api, args.dry_run)
        return set_state(api, activate=args.mode == "activate")
    except HttpError as error:
        detail = error.content.decode("utf-8", errors="replace") if error.content else str(error)
        print(f"[Play API エラー] {error.resp.status}\n{detail}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
