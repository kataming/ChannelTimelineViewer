# -*- coding: utf-8 -*-
"""Google Play のストア掲載情報・画像・AAB を API で流し込む。

Play Console の画面で7言語ぶんを手入力するのは事故のもとなので、原本
（`docs/PlayStore/metadata.json` と `docs/PlayStore/graphics|screenshots/`）から機械的に反映する。

できること:
  --mode status    いまの登録状況を読むだけ（変更しない）
  --mode listing   掲載情報（アプリ名・簡単な説明・詳しい説明）と画像を反映
  --mode details   ストアに公開される連絡先（メール・サイト）を反映
  --mode product   アプリ内アイテム（買い切りの Pro）を作成／更新
  --mode aab       署名済み AAB をアップロードして指定トラックに載せる
  --dry-run        送信せず、何をするかだけ表示する

できないこと（Play Console の画面でしか設定できない）:
  - データセーフティ / コンテンツのレーティング / 広告の有無 / 対象年齢
  - 価格（無料のまま）や国と地域の初期設定

前提:
  環境変数 GOOGLE_PLAY_SERVICE_ACCOUNT_JSON に、サービスアカウントの JSON（中身そのもの）。
  そのサービスアカウントが Play Console でこのアプリの権限を持っていること。
"""
from __future__ import annotations

import argparse
import io
import json
import os
import sys
from pathlib import Path

from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError
from googleapiclient.http import MediaFileUpload

ROOT = Path(__file__).resolve().parent.parent
METADATA = ROOT / "docs" / "PlayStore" / "metadata.json"
GRAPHICS_DIR = ROOT / "docs" / "PlayStore" / "graphics"
SCREENSHOT_DIR = ROOT / "docs" / "PlayStore" / "screenshots"
PACKAGE_NAME = "com.deskflowlabs.channeltimelineviewer"
SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def service():
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    if not raw:
        raise SystemExit("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON が未設定です。")
    info = json.loads(raw)
    credentials = service_account.Credentials.from_service_account_info(info, scopes=[SCOPE])
    return build("androidpublisher", "v3", credentials=credentials, cache_discovery=False)


def load_metadata() -> dict:
    return json.loads(io.open(METADATA, encoding="utf-8").read())


def show_status(api) -> int:
    edits = api.edits()
    edit = edits.insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]
    try:
        listings = edits.listings().list(
            packageName=PACKAGE_NAME, editId=edit_id).execute().get("listings", [])
        print(f"掲載情報が入っている言語: {len(listings)} 件")
        for listing in sorted(listings, key=lambda item: item["language"]):
            title = listing.get("title", "")
            short = len(listing.get("shortDescription", ""))
            full = len(listing.get("fullDescription", ""))
            print(f"  - {listing['language']}: 名前 {title!r} / 簡単な説明 {short}字 / 詳しい説明 {full}字")

        tracks = edits.tracks().list(packageName=PACKAGE_NAME, editId=edit_id).execute()
        print("\nトラック:")
        for track in tracks.get("tracks", []):
            releases = track.get("releases", [])
            summary = ", ".join(
                f"{release.get('status')} {release.get('name') or ''}"
                f"({','.join(release.get('versionCodes', []) or [])})"
                for release in releases) or "リリースなし"
            print(f"  - {track['track']}: {summary}")
    finally:
        edits.delete(packageName=PACKAGE_NAME, editId=edit_id).execute()
    return 0


def push_listing(api, dry_run: bool) -> int:
    data = load_metadata()
    locales = list(data["_locales"])

    if dry_run:
        for locale in locales:
            shots = sorted((SCREENSHOT_DIR / locale).glob("*.png"))
            print(f"  [dry-run] {locale}: テキスト3項目 / スクリーンショット {len(shots)} 枚")
        print(f"  [dry-run] アイコンとフィーチャーグラフィックも入れ替えます")
        return 0

    edits = api.edits()
    edit = edits.insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]

    for locale in locales:
        edits.listings().update(
            packageName=PACKAGE_NAME,
            editId=edit_id,
            language=locale,
            body={
                "language": locale,
                "title": data["title"][locale],
                "shortDescription": data["shortDescription"][locale],
                "fullDescription": data["fullDescription"][locale],
            },
        ).execute()
        print(f"  {locale}: テキストを反映")

        # 画像は「全消し → 入れ直し」にする（差分管理をしないぶん結果が読みやすい）。
        for image_type, files in image_sets(locale).items():
            if not files:
                continue
            edits.images().deleteall(
                packageName=PACKAGE_NAME, editId=edit_id,
                language=locale, imageType=image_type).execute()
            for path in files:
                edits.images().upload(
                    packageName=PACKAGE_NAME, editId=edit_id,
                    language=locale, imageType=image_type,
                    media_body=MediaFileUpload(str(path), mimetype="image/png"),
                ).execute()
            print(f"    {image_type}: {len(files)} 枚")

    edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print("\n反映しました（Play Console に「変更を確認」が出ます）。")
    return 0


def push_details(api, dry_run: bool) -> int:
    """ストアの掲載情報に表示される連絡先。電話番号は公開されるので入れない。"""
    body = {
        "contactEmail": "support@jewelrysunflower.com",
        "contactWebsite": "https://channeltimeline.jewelrysunflower.com/",
    }
    if dry_run:
        print(f"  [dry-run] 連絡先を反映: {body}")
        return 0

    edits = api.edits()
    edit_id = edits.insert(body={}, packageName=PACKAGE_NAME).execute()["id"]
    # patch にして、既存の defaultLanguage などを消さないようにする。
    edits.details().patch(packageName=PACKAGE_NAME, editId=edit_id, body=body).execute()
    edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print(f"  連絡先を反映しました: {body['contactEmail']} / {body['contactWebsite']}")
    return 0


def image_sets(locale: str) -> dict[str, list[Path]]:
    """言語ごとに入れる画像。アイコンとフィーチャーグラフィックは全言語共通のものを使う。"""
    screenshots = sorted(
        path for path in (SCREENSHOT_DIR / locale).glob("*.png")
        if not path.name.startswith(("00-", "ERROR"))
    ) if (SCREENSHOT_DIR / locale).is_dir() else []
    return {
        "icon": [GRAPHICS_DIR / "icon-512.png"],
        "featureGraphic": [GRAPHICS_DIR / "feature-1024x500.png"],
        "phoneScreenshots": screenshots,
    }


# 買い切り Pro のアプリ内アイテム。商品IDはアプリのコード（ProBillingManager）と一致させる。
PRO_PRODUCT_ID = "pro_unlock"
PRO_PURCHASE_OPTION_ID = "pro-unlock"
# ローンチ価格 $4.99。他国は Play に換算させる（値上げは Play Console から行える）。
PRO_PRICE_USD = {"currencyCode": "USD", "units": "4", "nanos": 990000000}

PRO_LISTINGS = {
    "ja-JP": ("Channel Timeline Viewer Pro",
              "買い切りで複数チャンネル保存を解放します。サブスクリプションではありません。"),
    "en-US": ("Channel Timeline Viewer Pro",
              "A one-time purchase that unlocks saving multiple channels. Not a subscription."),
    "zh-CN": ("Channel Timeline Viewer Pro",
              "一次性买断，解锁保存多个频道。这不是订阅服务。"),
    "es-ES": ("Channel Timeline Viewer Pro",
              "Una compra única que desbloquea guardar varios canales. No es una suscripción."),
    "de-DE": ("Channel Timeline Viewer Pro",
              "Ein einmaliger Kauf, der das Speichern mehrerer Kanäle freischaltet. Kein Abo."),
    "fr-FR": ("Channel Timeline Viewer Pro",
              "Un achat unique qui débloque l’enregistrement de plusieurs chaînes. Pas un abonnement."),
    "ko-KR": ("Channel Timeline Viewer Pro",
              "한 번만 구매하면 여러 채널 저장이 열립니다. 구독이 아닙니다."),
}


def upsert_product(api, dry_run: bool) -> int:
    """買い切りの Pro を作る（既にあれば更新する）。

    旧 `inappproducts` API は 2026 現在使えない（"Please migrate to the new publishing API."）ので、
    `monetization.onetimeproducts` を使う。各国の価格は `convertRegionPrices` に換算させる。
    """
    monetization = api.monetization()
    converted = monetization.convertRegionPrices(
        packageName=PACKAGE_NAME, body={"price": PRO_PRICE_USD}).execute()
    region_prices = converted.get("convertedRegionPrices", {})
    other_regions = converted.get("convertedOtherRegionsPrice", {})
    regions_version = converted.get("regionVersion", {}).get("version", "2022/02")

    configs = [
        {"regionCode": code, "availability": "AVAILABLE", "price": info["price"]}
        for code, info in sorted(region_prices.items())
        if "price" in info
    ]
    print(f"  価格を換算: {len(configs)} の国と地域 / 地域バージョン {regions_version}")

    purchase_option = {
        "purchaseOptionId": PRO_PURCHASE_OPTION_ID,
        # legacyCompatible=True にしないと、従来の購入フロー（本アプリの実装）から買えない。
        "buyOption": {"legacyCompatible": True, "multiQuantityEnabled": False},
        "regionalPricingAndAvailabilityConfigs": configs,
        # EU のデジタルコンテンツ（クーリングオフの扱い）を申告する。
        "taxAndComplianceSettings": {"withdrawalRightType": "WITHDRAWAL_RIGHT_DIGITAL_CONTENT"},
    }
    if other_regions.get("usdPrice") and other_regions.get("eurPrice"):
        purchase_option["newRegionsConfig"] = {
            "availability": "AVAILABLE",
            "usdPrice": other_regions["usdPrice"],
            "eurPrice": other_regions["eurPrice"],
        }

    body = {
        "packageName": PACKAGE_NAME,
        "productId": PRO_PRODUCT_ID,
        "listings": [
            {"languageCode": locale, "title": title, "description": description}
            for locale, (title, description) in PRO_LISTINGS.items()
        ],
        "purchaseOptions": [purchase_option],
    }

    if dry_run:
        print(f"  [dry-run] {PRO_PRODUCT_ID} を作成/更新して有効化する")
        return 0

    products = monetization.onetimeproducts()
    products.patch(
        packageName=PACKAGE_NAME,
        productId=PRO_PRODUCT_ID,
        allowMissing=True,
        # 新規作成でも update_mask が要るので、こちらで書き換える項目を明示する。
        updateMask="listings,purchaseOptions",
        **{"regionsVersion_version": regions_version},
        body=body,
    ).execute()
    print(f"  作成/更新しました: {PRO_PRODUCT_ID}")

    # 作っただけでは「有効」にならないので、購入オプションを有効化する。
    products.purchaseOptions().batchUpdateStates(
        packageName=PACKAGE_NAME,
        productId=PRO_PRODUCT_ID,
        body={"requests": [{
            "activatePurchaseOptionRequest": {
                "packageName": PACKAGE_NAME,
                "productId": PRO_PRODUCT_ID,
                "purchaseOptionId": PRO_PURCHASE_OPTION_ID,
            }
        }]},
    ).execute()

    current = products.get(packageName=PACKAGE_NAME, productId=PRO_PRODUCT_ID).execute()
    for option in current.get("purchaseOptions", []):
        print(f"  購入オプション {option.get('purchaseOptionId')}: {option.get('state')} / "
              f"価格を持つ国 {len(option.get('regionalPricingAndAvailabilityConfigs', []))}")
    return 0


def upload_aab(api, aab_path: Path, track: str, release_name: str, dry_run: bool) -> int:
    if not aab_path.exists():
        raise SystemExit(f"AAB がありません: {aab_path}")
    if dry_run:
        print(f"  [dry-run] {aab_path.name} を {track} トラックへ（下書きとして）アップロード")
        return 0

    edits = api.edits()
    edit = edits.insert(body={}, packageName=PACKAGE_NAME).execute()
    edit_id = edit["id"]

    bundle = edits.bundles().upload(
        packageName=PACKAGE_NAME, editId=edit_id,
        media_body=MediaFileUpload(str(aab_path), mimetype="application/octet-stream"),
        media_mime_type="application/octet-stream",
    ).execute()
    version_code = bundle["versionCode"]
    print(f"  アップロード完了: versionCode {version_code}")

    edits.tracks().update(
        packageName=PACKAGE_NAME, editId=edit_id, track=track,
        body={
            "track": track,
            "releases": [{
                "name": release_name,
                "versionCodes": [str(version_code)],
                # 事故防止のため下書きで置く。公開はコンソールで確認してから行う。
                "status": "draft",
            }],
        },
    ).execute()
    edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
    print(f"  {track} トラックに**下書き**として置きました。公開は Play Console で確認してから行ってください。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=["status", "listing", "details", "product", "aab"], default="status")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--aab", default="", help="--mode aab のときに使う AAB のパス")
    parser.add_argument("--track", default="internal", help="internal / alpha / beta / production")
    parser.add_argument("--release-name", default="1.0")
    args = parser.parse_args()

    api = service()
    try:
        if args.mode == "status":
            return show_status(api)
        if args.mode == "listing":
            return push_listing(api, args.dry_run)
        if args.mode == "details":
            return push_details(api, args.dry_run)
        if args.mode == "product":
            return upsert_product(api, args.dry_run)
        return upload_aab(api, Path(args.aab), args.track, args.release_name, args.dry_run)
    except HttpError as error:
        detail = error.content.decode("utf-8", errors="replace") if error.content else str(error)
        raise SystemExit(f"[Play API エラー] {error.resp.status}\n{detail}") from None


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
