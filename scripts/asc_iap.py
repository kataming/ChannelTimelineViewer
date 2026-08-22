# -*- coding: utf-8 -*-
"""App Store Connect の「App 内課金」を API で作る／確認する。

画面で手入力する代わりに、買い切りの Pro（`pro_unlock`）をここから登録する。
7言語の表示名・説明もまとめて入れる。

できること:
  --mode status   いまの登録状況を読むだけ（変更しない）
  --mode create   商品を作る（既にあれば表示名・説明・価格だけ更新する）
  --mode screenshot --image <png>  審査用スクリーンショットを添付する
  --mode app-price [--price 0.00]  アプリ本体の価格を設定する（0.00 で無料）
  --mode export-compliance --build <番号>  輸出コンプライアンスに「非対象」と回答する
  --mode review    審査に出している中身（バージョン・課金アイテム）を一覧する
  --mode submit-iap  審査中の提出物に課金アイテムを追加する
  --dry-run       送信せず、何をするかだけ表示する

できないこと（App Store Connect の画面でしか行えない）:
  - バージョンへの紐づけと審査提出

必要な環境変数: ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from asc_appstore_metadata import (  # noqa: E402
    ASCError, Client, find_app, make_token, upload_binary)

BUNDLE_ID = "com.deskflowlabs.channeltimelineviewer"

PRODUCT_ID = "pro_unlock"
# App Store Connect の参照名（30字まで）。ストアには出ない管理用の名前。
REFERENCE_NAME = "Channel Timeline Viewer Pro"
# 買い切り＝非消費型。サブスクリプションにはしない。
PRODUCT_TYPE = "NON_CONSUMABLE"
# ローンチ価格。$4.99 の価格ポイントを基準に、他国は Apple の対応表で決まる。
BASE_TERRITORY = "USA"
BASE_PRICE = "4.99"

REVIEW_NOTE = (
    "Non-consumable one-time purchase. Unlocks saving multiple YouTube channels and keeping "
    "watched history, progress and notes for each of them. This is not a subscription. "
    "The app itself is free and fully usable with one saved channel."
)

# 表示名は30字まで、説明は45字まで（App Store Connect の制限）。
LOCALIZATIONS = {
    "ja": ("Channel Timeline Viewer Pro", "買い切りで複数チャンネル保存を解放します"),
    "en-US": ("Channel Timeline Viewer Pro", "One-time purchase. Save multiple channels."),
    "zh-Hans": ("Channel Timeline Viewer Pro", "一次性买断，解锁保存多个频道"),
    "es-ES": ("Channel Timeline Viewer Pro", "Compra única. Guarda varios canales."),
    "de-DE": ("Channel Timeline Viewer Pro", "Einmaliger Kauf. Mehrere Kanäle speichern."),
    "fr-FR": ("Channel Timeline Viewer Pro", "Achat unique. Enregistrez plusieurs chaînes."),
    "ko": ("Channel Timeline Viewer Pro", "1회 구매로 여러 채널 저장을 해제합니다"),
}


def find_iap(client: Client, app_id: str) -> dict | None:
    path = (f"/v1/apps/{app_id}/inAppPurchasesV2"
            f"?filter[productId]={PRODUCT_ID}&limit=10")
    for item in client.get(path).get("data", []):
        if item.get("attributes", {}).get("productId") == PRODUCT_ID:
            return item
    return None


def show_status(client: Client) -> int:
    app = find_app(client, BUNDLE_ID)
    show_app_price(client, app["id"])
    iap = find_iap(client, app["id"])
    if iap is None:
        print(f"App 内課金 {PRODUCT_ID} は未登録です。")
        return 0

    attributes = iap.get("attributes", {})
    print(f"App 内課金 {PRODUCT_ID}")
    print(f"  参照名: {attributes.get('name')}")
    print(f"  種別:   {attributes.get('inAppPurchaseType')}")
    print(f"  状態:   {attributes.get('state')}")

    locales = client.get(
        f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations?limit=50")
    names = [item["attributes"]["locale"] for item in locales.get("data", [])]
    print(f"  表示名の言語: {len(names)} 件 {sorted(names)}")

    schedule = client.get(f"/v2/inAppPurchases/{iap['id']}/iapPriceSchedule"
                          "?include=manualPrices&limit=1")
    prices = [item for item in schedule.get("included", [])
              if item.get("type") == "inAppPurchasePrices"]
    print(f"  価格スケジュール: {'あり' if schedule.get('data') else 'なし'}"
          f"（価格 {len(prices)} 件）")
    return 0


def create_or_update(client: Client, dry_run: bool) -> int:
    app = find_app(client, BUNDLE_ID)
    iap = find_iap(client, app["id"])

    if iap is None:
        if dry_run:
            print(f"  [dry-run] {PRODUCT_ID} を {PRODUCT_TYPE} として作成する")
            return 0
        created = client.write("POST", "/v2/inAppPurchases", {
            "data": {
                "type": "inAppPurchases",
                "attributes": {
                    "name": REFERENCE_NAME,
                    "productId": PRODUCT_ID,
                    "inAppPurchaseType": PRODUCT_TYPE,
                    "reviewNote": REVIEW_NOTE,
                    # 買い切りをファミリー共有にはしない（1人分の権利として売る）。
                    "familySharable": False,
                },
                "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}},
            }
        })
        iap = created["data"]
        print(f"  作成しました: {PRODUCT_ID}（id {iap['id']}）")
    else:
        print(f"  既にあります: {PRODUCT_ID}（id {iap['id']}）")

    push_availability(client, iap["id"], dry_run)
    push_localizations(client, iap["id"], dry_run)
    push_price(client, iap["id"], dry_run)

    print("\n残りは App Store Connect の画面で行ってください:")
    print("  - 審査用スクリーンショット（Pro 画面）の添付")
    print("  - バージョンへの紐づけと審査提出")
    return 0


def push_availability(client: Client, iap_id: str, dry_run: bool) -> None:
    """配信する国と地域。全世界＋今後増える国も自動で対象にする。"""
    if dry_run:
        print("  [dry-run] 全世界で配信する設定にする")
        return

    try:
        current = client.get(f"/v2/inAppPurchases/{iap_id}/iapAvailability?limit=1")
        if current.get("data"):
            print("  配信地域: すでに設定済みのため変更しません")
            return
    except ASCError:
        pass

    territories = []
    path = "/v1/territories?limit=200"
    while path:
        page = client.get(path)
        territories += [{"type": "territories", "id": item["id"]} for item in page.get("data", [])]
        path = page.get("links", {}).get("next", "")

    client.write("POST", "/v1/inAppPurchaseAvailabilities", {
        "data": {
            "type": "inAppPurchaseAvailabilities",
            "attributes": {"availableInNewTerritories": True},
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "availableTerritories": {"data": territories},
            },
        }
    })
    print(f"  配信地域: {len(territories)} の国と地域で配信する設定にしました")


def push_localizations(client: Client, iap_id: str, dry_run: bool) -> None:
    existing = {}
    if not dry_run:
        found = client.get(f"/v2/inAppPurchases/{iap_id}/inAppPurchaseLocalizations?limit=50")
        existing = {item["attributes"]["locale"]: item["id"] for item in found.get("data", [])}

    for locale, (name, description) in LOCALIZATIONS.items():
        if dry_run:
            print(f"  [dry-run] {locale}: {name} / {description}")
            continue
        attributes = {"name": name, "description": description}
        if locale in existing:
            client.write("PATCH", f"/v1/inAppPurchaseLocalizations/{existing[locale]}", {
                "data": {"type": "inAppPurchaseLocalizations",
                         "id": existing[locale], "attributes": attributes}
            })
            print(f"  {locale}: 更新")
        else:
            client.write("POST", "/v1/inAppPurchaseLocalizations", {
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {"inAppPurchaseV2": {
                        "data": {"type": "inAppPurchases", "id": iap_id}}},
                }
            })
            print(f"  {locale}: 追加")


def push_price(client: Client, iap_id: str, dry_run: bool) -> None:
    if dry_run:
        print(f"  [dry-run] 基準価格 {BASE_PRICE} USD（{BASE_TERRITORY}）を設定する")
        return

    # 既に価格が付いていれば触らない（値上げは意図した操作のときだけ行う）。
    try:
        schedule = client.get(f"/v2/inAppPurchases/{iap_id}/iapPriceSchedule?limit=1")
        if schedule.get("data"):
            print("  価格: すでに設定済みのため変更しません")
            return
    except ASCError:
        pass

    point_id = find_price_point(client, iap_id)
    if point_id is None:
        print(f"  価格: {BASE_PRICE} USD の価格ポイントが見つかりませんでした（画面で設定してください）")
        return

    client.write("POST", "/v1/inAppPurchasePriceSchedules", {
        "data": {
            "type": "inAppPurchasePriceSchedules",
            "relationships": {
                "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price1}"}]},
            },
        },
        "included": [{
            "type": "inAppPurchasePrices",
            "id": "${price1}",
            # startDate を入れないと「いますぐ」の意味になる。
            "attributes": {"startDate": None, "endDate": None},
            "relationships": {
                "inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}},
                "inAppPurchasePricePoint": {
                    "data": {"type": "inAppPurchasePricePoints", "id": point_id}},
            },
        }],
    })
    print(f"  価格: {BASE_PRICE} USD（{BASE_TERRITORY} 基準）で設定しました")


def find_price_point(client: Client, iap_id: str) -> str | None:
    """$4.99 に当たる価格ポイントを探す。他国の価格は Apple がこれを基準に決める。"""
    path = (f"/v2/inAppPurchases/{iap_id}/pricePoints"
            f"?filter[territory]={BASE_TERRITORY}&limit=200")
    while path:
        page = client.get(path)
        for item in page.get("data", []):
            if item.get("attributes", {}).get("customerPrice") == BASE_PRICE:
                return item["id"]
        path = page.get("links", {}).get("next", "")
    return None


def push_screenshot(client: Client, image: Path, dry_run: bool) -> int:
    """審査用スクリーンショットを添付する。

    Apple は「その課金がアプリのどこで提供されるか」が分かる画像を1枚求める。
    受け付ける寸法が決まっているので、撮影側（ワークフロー）で 1242x2688 に揃えてから渡す。
    """
    if not image.exists():
        raise SystemExit(f"画像がありません: {image}")

    app = find_app(client, BUNDLE_ID)
    iap = find_iap(client, app["id"])
    if iap is None:
        raise SystemExit(f"{PRODUCT_ID} が未登録です。先に --mode create を実行してください。")

    data = image.read_bytes()
    print(f"  添付する画像: {image.name}（{len(data) // 1024} KB）")
    if dry_run:
        return 0

    # 既に付いていれば外す（付いたまま POST すると 409 "Screenshot already exists" になる）。
    for screenshot_id in existing_screenshot_ids(client, iap["id"]):
        client.write("DELETE",
                     f"/v1/inAppPurchaseAppStoreReviewScreenshots/{screenshot_id}", {})
        print("  既存のスクリーンショットを外しました")

    reserved = client.write("POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "attributes": {"fileSize": len(data), "fileName": image.name},
            "relationships": {"inAppPurchaseV2": {
                "data": {"type": "inAppPurchases", "id": iap["id"]}}},
        }
    })["data"]

    for operation in reserved["attributes"].get("uploadOperations", []):
        start = operation["offset"]
        upload_binary(operation["url"], operation["method"],
                      operation.get("requestHeaders", []),
                      data[start:start + operation["length"]])

    client.write("PATCH", f"/v1/inAppPurchaseAppStoreReviewScreenshots/{reserved['id']}", {
        "data": {
            "type": "inAppPurchaseAppStoreReviewScreenshots",
            "id": reserved["id"],
            "attributes": {"uploaded": True,
                           "sourceFileChecksum": hashlib.md5(data).hexdigest()},
        }
    })
    print("  添付しました。App Store Connect で確認できます。")
    return 0


def existing_screenshot_ids(client: Client, iap_id: str) -> list[str]:
    """付いている審査用スクリーンショットのID。関係名の綴りが版で違うので複数試す。"""
    try:
        detail = client.get(
            f"/v2/inAppPurchases/{iap_id}?include=appStoreReviewScreenshot")
        return [item["id"] for item in detail.get("included", [])
                if item.get("type") == "inAppPurchaseAppStoreReviewScreenshots"]
    except ASCError:
        return []


def show_app_price(client: Client, app_id: str) -> None:
    """いまのアプリ本体価格（基準国の表示価格）を出す。"""
    try:
        schedule = client.get(
            f"/v1/apps/{app_id}/appPriceSchedule"
            "?include=baseTerritory,manualPrices&limit=50")
    except ASCError:
        print("  本体価格: 未設定")
        return

    base = next((item["id"] for item in schedule.get("included", [])
                 if item.get("type") == "territories"), "?")
    prices = [item for item in schedule.get("included", [])
              if item.get("type") == "appPrices"]
    print(f"  本体価格: 基準の国 {base} / 価格の登録 {len(prices)} 件")


def set_app_price(client: Client, price: str, dry_run: bool) -> int:
    """アプリ本体の価格を設定する。`0.00` を渡すと無料になる。

    App 内課金と同じで、基準の国（USA）の価格ポイントを1つ選べば、
    他の国は Apple の対応表で決まる。
    """
    app = find_app(client, BUNDLE_ID)
    show_app_price(client, app["id"])

    print(f"  設定する価格: {price} USD（{BASE_TERRITORY} 基準）"
          + ("＝無料" if price == "0.00" else ""))
    if dry_run:
        return 0

    point_id = find_app_price_point(client, app["id"], price)
    if point_id is None:
        raise SystemExit(f"{price} USD の価格ポイントが見つかりませんでした。")

    client.write("POST", "/v1/appPriceSchedules", {
        "data": {
            "type": "appPriceSchedules",
            "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}},
                "baseTerritory": {"data": {"type": "territories", "id": BASE_TERRITORY}},
                "manualPrices": {"data": [{"type": "appPrices", "id": "${price1}"}]},
            },
        },
        "included": [{
            "type": "appPrices",
            "id": "${price1}",
            # startDate を入れないと「いますぐ」の意味になる。
            "attributes": {"startDate": None, "endDate": None},
            "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}},
                "appPricePoint": {"data": {"type": "appPricePoints", "id": point_id}},
            },
        }],
    })
    print("  設定しました。")
    show_app_price(client, app["id"])
    return 0


def find_app_price_point(client: Client, app_id: str, price: str) -> str | None:
    path = (f"/v2/apps/{app_id}/appPricePoints"
            f"?filter[territory]={BASE_TERRITORY}&limit=200")
    while path:
        page = client.get(path)
        for item in page.get("data", []):
            if item.get("attributes", {}).get("customerPrice") == price:
                return item["id"]
        path = page.get("links", {}).get("next", "")
    return None


def answer_export_compliance(client: Client, build_number: str, dry_run: bool) -> int:
    """輸出コンプライアンスに「非対象」と回答する。

    このアプリは独自の暗号化を実装しておらず、通信は OS 標準の HTTPS のみ。
    回答しないと「このビルドには、輸出コンプライアンス情報が存在しません」で審査に出せない。
    """
    app = find_app(client, BUNDLE_ID)
    path = (f"/v1/builds?filter[app]={app['id']}"
            f"&filter[version]={build_number}&limit=1")
    builds = client.get(path).get("data", [])
    if not builds:
        raise SystemExit(f"build {build_number} が見つかりません。")

    build = builds[0]
    current = build.get("attributes", {}).get("usesNonExemptEncryption")
    print(f"  build {build_number}（id {build['id']}）: いまの回答 {current}")
    if current is False:
        print("  すでに「非対象」と回答済みです。")
        return 0
    if dry_run:
        print("  [dry-run] 「非対象（usesNonExemptEncryption=false）」と回答する")
        return 0

    client.write("PATCH", f"/v1/builds/{build['id']}", {
        "data": {"type": "builds", "id": build["id"],
                 "attributes": {"usesNonExemptEncryption": False}}
    })
    print("  「非対象」と回答しました。")
    return 0


REVIEW_STATES = ["READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW",
                 "UNRESOLVED_ISSUES", "COMPLETING"]


def review_submissions(client: Client, app_id: str) -> list[dict]:
    """審査に出している（または出そうとしている）提出物。"""
    path = (f"/v1/reviewSubmissions?filter[app]={app_id}"
            f"&filter[state]={','.join(REVIEW_STATES)}&include=items&limit=10")
    return client.get(path)


def show_review(client: Client) -> int:
    """審査の提出物に何が入っているかを出す。

    Apple から「IAP が審査に提出されていない」と指摘されたときは、ここで実際の中身を見る。
    """
    app = find_app(client, BUNDLE_ID)
    result = review_submissions(client, app["id"])
    submissions = result.get("data", [])
    if not submissions:
        print("審査中の提出物はありません（却下後に作り直す必要があります）。")
        return 0

    included = {item["id"]: item for item in result.get("included", [])}
    for submission in submissions:
        state = submission["attributes"].get("state")
        print(f"提出物 {submission['id']}: 状態 {state}")
        items = submission.get("relationships", {}).get("items", {}).get("data", [])
        if not items:
            print("  中身: なし")
        for ref in items:
            item = included.get(ref["id"], {})
            relationships = item.get("relationships", {})
            kinds = [name for name, value in relationships.items()
                     if (value or {}).get("data")]
            detail = ", ".join(
                f"{name}={relationships[name]['data'].get('id')}" for name in kinds)
            print(f"  中身: {detail or '（不明）'}")
    return 0


def submit_iap(client: Client, dry_run: bool) -> int:
    """審査中の提出物に課金アイテムを足す。

    初回リリースでは、課金アイテムをアプリのバージョンと**一緒に**審査へ出す必要がある。
    """
    app = find_app(client, BUNDLE_ID)
    iap = find_iap(client, app["id"])
    if iap is None:
        raise SystemExit(f"{PRODUCT_ID} が未登録です。")

    result = review_submissions(client, app["id"])
    submissions = result.get("data", [])
    if not submissions:
        raise SystemExit("審査中の提出物がありません。先に App Store Connect で提出を作ってください。")

    submission = submissions[0]
    included = {item["id"]: item for item in result.get("included", [])}
    for ref in submission.get("relationships", {}).get("items", {}).get("data", []):
        target = (included.get(ref["id"], {}).get("relationships", {})
                  .get("inAppPurchaseV2", {}).get("data") or {})
        if target.get("id") == iap["id"]:
            print("  課金アイテムはすでに提出物に入っています。")
            return 0

    print(f"  提出物 {submission['id']} に {PRODUCT_ID} を追加します")
    if dry_run:
        return 0

    client.write("POST", "/v1/reviewSubmissionItems", {
        "data": {
            "type": "reviewSubmissionItems",
            "relationships": {
                "reviewSubmission": {
                    "data": {"type": "reviewSubmissions", "id": submission["id"]}},
                "inAppPurchaseV2": {
                    "data": {"type": "inAppPurchases", "id": iap["id"]}},
            },
        }
    })
    print("  追加しました。")
    return show_review(client)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode",
                        choices=["status", "create", "screenshot", "app-price",
                                 "export-compliance", "review", "submit-iap"],
                        default="status")
    parser.add_argument("--build", default="", help="--mode export-compliance の対象ビルド番号")
    parser.add_argument("--price", default="0.00",
                        help="--mode app-price で設定する USD 価格（0.00 で無料）")
    parser.add_argument("--image", default="", help="--mode screenshot で添付する PNG")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--key-id", default=os.environ.get("ASC_KEY_ID", ""))
    parser.add_argument("--issuer-id", default=os.environ.get("ASC_ISSUER_ID", ""))
    parser.add_argument("--private-key", default=os.environ.get("ASC_PRIVATE_KEY", ""))
    args = parser.parse_args()

    if not (args.key_id and args.issuer_id and args.private_key):
        raise SystemExit("ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY が必要です。")

    client = Client(make_token(args.key_id, args.issuer_id, args.private_key),
                    dry_run=args.dry_run)
    try:
        if args.mode == "status":
            return show_status(client)
        if args.mode == "screenshot":
            return push_screenshot(client, Path(args.image), args.dry_run)
        if args.mode == "app-price":
            return set_app_price(client, args.price, args.dry_run)
        if args.mode == "export-compliance":
            return answer_export_compliance(client, args.build, args.dry_run)
        if args.mode == "review":
            return show_review(client)
        if args.mode == "submit-iap":
            return submit_iap(client, args.dry_run)
        return create_or_update(client, args.dry_run)
    except ASCError as error:
        print(f"[App Store Connect エラー] {error}")
        return 1


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
