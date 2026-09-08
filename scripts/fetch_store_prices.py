# -*- coding: utf-8 -*-
"""Pro（`pro_unlock`）の**現在の価格**をストアから読み、公式サイト用のデータを作る。

価格は App Store Connect / Google Play 側で変えるもので、コードには持たない方針
（CLAUDE.md「収益化の方針」）。サイトに載せる金額もここで**ストアから取得**して
`site/src/i18n/prices.js` を作り直す。手で書き換えないこと。

    python scripts/fetch_store_prices.py            # 両ストアから取得して書き出す
    python scripts/fetch_store_prices.py --print    # 取得して表示するだけ（書き出さない）

必要な認証:
  Google Play  … GOOGLE_PLAY_SERVICE_ACCOUNT_JSON（中身そのもの）
                 または PLAY_SERVICE_ACCOUNT_FILE（JSON のパス）
  App Store    … ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY
                 （ASC_PRIVATE_KEY_FILE に .p8 のパスでも可）
                 **認証が無いときは、App Store の商品ページに実際に表示されている
                 価格を各国ぶん読む**（お客さんに見えている金額そのもの）。

⚠️ Apple と Google で金額が違うことがある（2026-09-08 時点で EU は 5,99€ と 4,99€、
   韓国は ₩7,700 と ₩7,500）。片方だけを載せると間違いになるので、
   違うときはストア名を添えて両方出す。同じならひとつだけ出す。
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "site" / "src" / "i18n" / "prices.js"

PACKAGE_NAME = "com.deskflowlabs.channeltimelineviewer"
BUNDLE_ID = "com.deskflowlabs.channeltimelineviewer"
PRODUCT_ID = "pro_unlock"
# App Store の商品ページで課金アイテムを見分けるための表示名。
PRODUCT_NAME = "Channel Timeline Viewer Pro"
PLAY_SCOPE = "https://www.googleapis.com/auth/androidpublisher"

# サイトの言語 → どの国の価格を出すか。
#   apple … App Store Connect の territory（3文字）
#   play  … Google Play の regionCode（2文字）
# 中国本土は Google Play が提供されていないため play は None。
LANGUAGE_TERRITORIES = {
    "en": {"apple": "USA", "play": "US"},
    "ja": {"apple": "JPN", "play": "JP"},
    "zh": {"apple": "CHN", "play": None},
    "es": {"apple": "ESP", "play": "ES"},
    "de": {"apple": "DEU", "play": "DE"},
    "fr": {"apple": "FRA", "play": "FR"},
    "ko": {"apple": "KOR", "play": "KR"},
}


# ---------------------------------------------------------------- Google Play

def play_prices() -> dict:
    """{regionCode: {"currency": "JPY", "amount": 800.0}} を返す。"""
    raw = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "").strip()
    path = os.environ.get("PLAY_SERVICE_ACCOUNT_FILE", "").strip()
    if not raw and path:
        raw = io.open(path, encoding="utf-8").read()
    if not raw:
        print("  Google Play: 認証が無いので読み飛ばします")
        return {}

    from google.oauth2 import service_account
    from googleapiclient.discovery import build

    info = json.loads(raw)
    creds = service_account.Credentials.from_service_account_info(info, scopes=[PLAY_SCOPE])
    api = build("androidpublisher", "v3", credentials=creds, cache_discovery=False)

    res = api.monetization().onetimeproducts().list(packageName=PACKAGE_NAME).execute()
    product = next((p for p in res.get("oneTimeProducts", [])
                    if p.get("productId") == PRODUCT_ID), None)
    if product is None:
        raise SystemExit(f"Google Play に {PRODUCT_ID} が見つかりません。")

    options = product.get("purchaseOptions") or []
    active = next((o for o in options if o.get("state") == "ACTIVE"), options[0] if options else None)
    if active is None:
        raise SystemExit("Google Play の購入オプションがありません。")

    out = {}
    for config in active.get("regionalPricingAndAvailabilityConfigs", []):
        price = config.get("price") or {}
        code = config.get("regionCode")
        if not code or not price.get("currencyCode"):
            continue
        units = int(price.get("units") or 0)
        nanos = int(price.get("nanos") or 0)
        out[code] = {"currency": price["currencyCode"], "amount": units + nanos / 1_000_000_000}
    print(f"  Google Play: {len(out)} 地域の価格を取得")
    return out


# ---------------------------------------------------------------- App Store

# App Store の商品ページを読むときの、国コードと通貨の対応。
# 記号だけでは判別できない（日本と中国はどちらも ¥）ので、国から決める。
APPLE_STOREFRONTS = {
    "USA": ("us", "USD"),
    "JPN": ("jp", "JPY"),
    "CHN": ("cn", "CNY"),
    "ESP": ("es", "EUR"),
    "DEU": ("de", "EUR"),
    "FRA": ("fr", "EUR"),
    "KOR": ("kr", "KRW"),
}

APP_ID = "6792964082"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120 Safari/537.36")
PAIR_RE = re.compile(r'"\$kind":"textPair","leadingText":"([^"]+)","trailingText":"([^"]+)"')


def parse_amount(text: str) -> float | None:
    """「5,99 €」「￦7,700」「¥38.00」などから数値を取り出す。

    小数点かどうかは「最後の区切りのあとが1〜2桁か」で決める
    （7,700 は桁区切り、5,99 は小数点）。
    """
    digits = re.sub(r"[^0-9.,]", "", text)
    if not digits:
        return None
    match = re.search(r"[.,](\d{1,2})$", digits)
    if match:
        head = digits[: match.start()].replace(",", "").replace(".", "")
        return float(f"{head}.{match.group(1)}")
    return float(digits.replace(",", "").replace(".", ""))


def apple_prices_from_store_pages(territories: list[str]) -> dict:
    """App Store の商品ページに出ている金額を読む（認証なしで使える経路）。"""
    out = {}
    for territory in territories:
        where = APPLE_STOREFRONTS.get(territory)
        if not where:
            print(f"    {territory}: 対応表に無いので読み飛ばします")
            continue
        country, currency = where
        url = f"https://apps.apple.com/{country}/app/id{APP_ID}"
        request = urllib.request.Request(url, headers={"User-Agent": UA})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                html = response.read().decode("utf-8", "ignore")
        except Exception as error:  # noqa: BLE001
            print(f"    {territory}: ページを取得できませんでした（{type(error).__name__}）")
            continue
        pairs = [pair for pair in PAIR_RE.findall(html) if PRODUCT_NAME in pair[0]]
        if not pairs:
            print(f"    {territory}: アプリ内課金の価格が見つかりません（未配信か表示が変わった）")
            continue
        amount = parse_amount(pairs[0][1])
        if amount is None:
            print(f"    {territory}: 金額を読み取れません（{pairs[0][1]}）")
            continue
        out[territory] = {"currency": currency, "amount": amount}
    print(f"  App Store（商品ページ）: {len(out)} か国の価格を取得")
    return out


def apple_prices(territories: list[str]) -> dict:
    """{territory: {"currency": "JPY", "amount": 800.0}} を返す。"""
    if not (os.environ.get("ASC_KEY_ID") and os.environ.get("ASC_ISSUER_ID")
            and (os.environ.get("ASC_PRIVATE_KEY") or os.environ.get("ASC_PRIVATE_KEY_FILE"))):
        print("  App Store: API の認証が無いので、商品ページに出ている金額を読みます")
        return apple_prices_from_store_pages(territories)

    sys.path.insert(0, str(ROOT / "scripts"))
    if os.environ.get("ASC_PRIVATE_KEY_FILE") and not os.environ.get("ASC_PRIVATE_KEY"):
        os.environ["ASC_PRIVATE_KEY"] = io.open(
            os.environ["ASC_PRIVATE_KEY_FILE"], encoding="utf-8").read()

    from asc_appstore_metadata import Client, find_app, make_token  # noqa: E402

    client = Client(make_token())
    app = find_app(client, BUNDLE_ID)
    iap = None
    path = (f"/v1/apps/{app['id']}/inAppPurchasesV2"
            f"?filter[productId]={PRODUCT_ID}&limit=10")
    for item in client.get(path).get("data", []):
        if item.get("attributes", {}).get("productId") == PRODUCT_ID:
            iap = item
            break
    if iap is None:
        raise SystemExit(f"App Store Connect に {PRODUCT_ID} が見つかりません。")

    out = {}
    for territory in territories:
        # 価格表は「基準の国から自動計算された各国価格」。territory で絞って1件だけ読む。
        query = (f"/v1/inAppPurchasePriceSchedules/{iap['id']}/automaticPrices"
                 f"?filter[territory]={territory}"
                 f"&include=inAppPurchasePricePoint,territory&limit=1")
        try:
            data = client.get(query)
        except Exception as error:  # noqa: BLE001
            print(f"    {territory}: 取得できませんでした（{error}）")
            continue
        point = next((item for item in data.get("included", [])
                      if item.get("type") == "inAppPurchasePricePoints"), None)
        terr = next((item for item in data.get("included", [])
                     if item.get("type") == "territories"), None)
        if not point or not terr:
            print(f"    {territory}: 価格が登録されていません")
            continue
        customer_price = point.get("attributes", {}).get("customerPrice")
        currency = terr.get("attributes", {}).get("currency")
        if customer_price is None or not currency:
            continue
        out[territory] = {"currency": currency, "amount": float(customer_price)}
    print(f"  App Store: {len(out)} か国の価格を取得")
    return out


# ---------------------------------------------------------------- 書き出し

def build_table(apple: dict, play: dict) -> dict:
    table = {}
    for lang, where in LANGUAGE_TERRITORIES.items():
        entry = {}
        a = apple.get(where["apple"]) if where["apple"] else None
        p = play.get(where["play"]) if where["play"] else None
        if a:
            entry["ios"] = a
        if p:
            entry["android"] = p
        if entry:
            table[lang] = entry
    return table


def render(table: dict) -> str:
    lines = [
        "// Pro（買い切り）の各国の価格。**自動生成なので手で書かない。**",
        "//   python scripts/fetch_store_prices.py",
        "// で App Store Connect / Google Play の現在の価格を読み直して作り直す。",
        "//",
        "// 形は { 言語: { ios: {currency, amount}, android: {currency, amount} } }。",
        "// 金額の書式は表示側（Intl.NumberFormat）で各言語に合わせて作る。",
        "// 中国本土は Google Play が提供されていないため、zh には android が入らない。",
        "",
        "export const proPrices = " + json.dumps(table, ensure_ascii=False, indent=2) + ";",
        "",
        "/** その言語で出す価格。両ストアが同じ金額なら1つ、違えば両方返す。 */",
        "export function priceFor(code) {",
        "  // その言語の国の価格が無ければ何も出さない（別の国の金額は出さない）。",
        "  const entry = proPrices[code];",
        "  if (!entry) return null;",
        "  const { ios, android } = entry;",
        "  if (ios && android && ios.currency === android.currency && ios.amount === android.amount) {",
        "    return { same: ios };",
        "  }",
        "  return { ios: ios || null, android: android || null };",
        "}",
        "",
        "export default proPrices;",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--print", dest="only_print", action="store_true",
                        help="取得した価格を表示するだけ（ファイルを書き換えない）")
    args = parser.parse_args()

    print("Pro の現在価格を取得します。")
    play = play_prices()
    apple = apple_prices([w["apple"] for w in LANGUAGE_TERRITORIES.values() if w["apple"]])

    table = build_table(apple, play)
    if not table:
        raise SystemExit("価格を1件も取得できませんでした。認証を確認してください。")

    print("\n言語ごとの価格:")
    for lang, entry in table.items():
        parts = []
        for store, label in (("ios", "App Store"), ("android", "Google Play")):
            value = entry.get(store)
            if value:
                parts.append(f"{label} {value['currency']} {value['amount']:g}")
        print(f"  {lang}: {' / '.join(parts) if parts else '（取得できず）'}")

    missing = [lang for lang in LANGUAGE_TERRITORIES if lang not in table]
    if missing:
        print(f"\n⚠️ 価格を取得できなかった言語: {', '.join(missing)}")

    if args.only_print:
        print("\n--print なのでファイルは書き換えていません。")
        return 0

    OUT.write_text(render(table), encoding="utf-8")
    print(f"\n書き出しました: {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
