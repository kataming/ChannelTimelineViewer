# -*- coding: utf-8 -*-
"""App Store Connect のアプリ情報（7言語のメタデータ）を API で確認・反映する。

App Store Connect の画面は人がログインしないと触れないが、**メタデータの入力**は
App Store Connect API で流し込める。7言語ぶんを手で貼り付けるのは事故のもとなので、
原本（`docs/AppStore/metadata.json`）から機械的に反映する。

やること:
  - `--mode status`: いまの登録状況を読み取って表示する（変更しない）
      アプリ / バージョン / 言語ごとの入力有無 / スクリーンショット / 審査に必要な項目
  - `--mode push`  : 原本のメタデータを反映する
      - App 情報（言語ごとの App 名・サブタイトル・プライバシーポリシーURL）
      - バージョン情報（説明・キーワード・プロモーション文・新機能・サポート/マーケティングURL）
      - `--dry-run` を付けると、何を変えるかだけ表示して実際には送らない

前提:
  ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY（.p8 の中身）を環境変数か引数で渡す。
  GitHub Actions の `appstore-metadata.yml` から使うことを想定している（鍵は Secrets）。

秘密情報の扱い:
  .p8 の中身は表示しない。エラー時も本文だけを出す。

使い方:
    python scripts/asc_appstore_metadata.py --mode status
    python scripts/asc_appstore_metadata.py --mode push --dry-run
    python scripts/asc_appstore_metadata.py --mode push --version 1.0
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt

API_BASE = "https://api.appstoreconnect.apple.com"
REPO_ROOT = Path(__file__).resolve().parent.parent
METADATA = REPO_ROOT / "docs" / "AppStore" / "metadata.json"
REVIEW_NOTES = REPO_ROOT / "docs" / "AppStore" / "review-notes-en.md"
DEFAULT_BUNDLE_ID = "com.deskflowlabs.channeltimelineviewer"

# 原本の言語キー → App Store Connect のロケール。
LOCALE_MAP = {
    "ja": "ja",
    "en": "en-US",
    "zh-Hans": "zh-Hans",
    "es": "es-ES",
    "de": "de-DE",
    "fr": "fr-FR",
    "ko": "ko",
}

class ASCError(RuntimeError):
    """App Store Connect API がエラーを返したとき。呼び出し側で内容を見て分岐できるようにする。"""

    def __init__(self, method: str, path: str, code: int, detail: str):
        super().__init__(f"[ASC API エラー] {method} {path} -> HTTP {code}\n{detail}")
        self.code = code
        self.detail = detail


# すでに公開したことがある（＝更新版なら「新機能」を書ける）状態。
RELEASED_STATES = {
    "READY_FOR_SALE",
    "PENDING_DEVELOPER_RELEASE",
    "PROCESSING_FOR_APP_STORE",
    "REPLACED_WITH_NEW_VERSION",
    "REMOVED_FROM_SALE",
}

# 編集できる（＝これから提出する）バージョンの状態。
EDITABLE_STATES = {
    "PREPARE_FOR_SUBMISSION",
    "DEVELOPER_REJECTED",
    "REJECTED",
    "METADATA_REJECTED",
    "INVALID_BINARY",
    "WAITING_FOR_REVIEW",
}


# --- ASC API -----------------------------------------------------------------
def make_token(key_id: str, issuer_id: str, private_key: str) -> str:
    now = int(time.time())
    payload = {"iss": issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, private_key, algorithm="ES256",
                      headers={"kid": key_id, "typ": "JWT"})


class Client:
    def __init__(self, token: str, dry_run: bool = False):
        self.token = token
        self.dry_run = dry_run

    def request(self, method: str, path: str, body: dict | None = None) -> dict:
        url = path if path.startswith("http") else f"{API_BASE}{path}"
        data = json.dumps(body).encode("utf-8") if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")
            raise ASCError(method, path, e.code, detail) from None

    def get(self, path: str) -> dict:
        return self.request("GET", path)

    def write(self, method: str, path: str, body: dict) -> dict:
        """書き込み。--dry-run のときは送らずに内容だけ表示する。"""
        if self.dry_run:
            kind = body.get("data", {}).get("type")
            attrs = sorted(body.get("data", {}).get("attributes", {}).keys())
            print(f"    [dry-run] {method} {path} ({kind}: {', '.join(attrs)})")
            return {}
        try:
            return self.request(method, path, body)
        except ASCError as error:
            # 初回リリース等で編集できない項目があれば、その項目を外して一度だけやり直す。
            blocked = [name for name in ("whatsNew", "promotionalText")
                       if f"'{name}'" in error.detail]
            attributes = body.get("data", {}).get("attributes", {})
            if error.code != 409 or not blocked or not any(n in attributes for n in blocked):
                raise
            for name in blocked:
                attributes.pop(name, None)
            print(f"    （{', '.join(blocked)} は編集できないため外して再送します）")
            return self.request(method, path, body)


# --- 取得 ---------------------------------------------------------------------
def find_app(client: Client, bundle_id: str) -> dict:
    res = client.get(f"/v1/apps?filter[bundleId]={bundle_id}&limit=1")
    items = res.get("data", [])
    if not items:
        raise SystemExit(
            f"Bundle ID {bundle_id} のアプリが App Store Connect に見つかりません。\n"
            "先に App Store Connect でアプリを登録してください。"
        )
    return items[0]


def editable_version(client: Client, app_id: str) -> dict | None:
    res = client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=20")
    for version in res.get("data", []):
        if version["attributes"].get("appStoreState") in EDITABLE_STATES:
            return version
    return None


def editable_app_info(client: Client, app_id: str) -> dict | None:
    res = client.get(f"/v1/apps/{app_id}/appInfos?limit=10")
    for info in res.get("data", []):
        state = info["attributes"].get("appStoreState") or info["attributes"].get("state")
        if state in EDITABLE_STATES or state is None:
            return info
    data = res.get("data", [])
    return data[0] if data else None


def localizations(client: Client, path: str) -> dict[str, dict]:
    """ロケール → localization リソース の辞書。"""
    res = client.get(f"{path}?limit=50")
    return {item["attributes"]["locale"]: item for item in res.get("data", [])}


# --- 表示 ---------------------------------------------------------------------
def show_status(client: Client, bundle_id: str) -> int:
    app = find_app(client, bundle_id)
    app_id = app["id"]
    attrs = app["attributes"]
    print(f"アプリ: {attrs.get('name')} / SKU {attrs.get('sku')} / 主要言語 {attrs.get('primaryLocale')}")
    print(f"  Bundle ID: {attrs.get('bundleId')}  (id={app_id})")

    versions = client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=10").get("data", [])
    if not versions:
        print("  バージョン: まだありません（push すると作成します）")
    for v in versions:
        va = v["attributes"]
        print(f"  バージョン {va.get('versionString')}: 状態 {va.get('appStoreState')} "
              f"/ リリース {va.get('releaseType')}")

    version = editable_version(client, app_id)
    if version:
        loc = localizations(client, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
        print(f"\n  編集できるバージョン {version['attributes']['versionString']} の言語:")
        for locale, item in sorted(loc.items()):
            a = item["attributes"]
            filled = [name for name in ("description", "keywords", "promotionalText", "whatsNew")
                      if a.get(name)]
            shots = client.get(
                f"/v1/appStoreVersionLocalizations/{item['id']}/appScreenshotSets?limit=10"
            ).get("data", [])
            print(f"    - {locale}: 入力済み {', '.join(filled) if filled else 'なし'}"
                  f" / スクリーンショットのセット {len(shots)} 件")
        missing = sorted(set(LOCALE_MAP.values()) - set(loc))
        if missing:
            print(f"    未作成の言語: {', '.join(missing)}")

        # 審査に必要な付随情報
        build = client.get(f"/v1/appStoreVersions/{version['id']}/build").get("data")
        print(f"\n  紐づいたビルド: {build['attributes']['version'] if build else '未選択'}")

        builds = client.get(
            f"/v1/builds?filter[app]={app_id}&sort=-version&limit=5").get("data", [])
        print("  TestFlight のビルド（新しい順）:")
        for b in builds:
            ba = b["attributes"]
            print(f"    - build {ba.get('version')}: 処理 {ba.get('processingState')}"
                  f" / 期限切れ {ba.get('expired')}")
        try:
            review = client.get(
                f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
            print(f"  審査メモ: {'入力済み' if review else '未入力'}")
        except ASCError:
            print("  審査メモ: 取得できませんでした")

    info = editable_app_info(client, app_id)
    if info:
        loc = localizations(client, f"/v1/appInfos/{info['id']}/appInfoLocalizations")
        print(f"\n  App 情報（名前・サブタイトル・プライバシーポリシーURL）の言語:")
        for locale, item in sorted(loc.items()):
            a = item["attributes"]
            print(f"    - {locale}: 名前 {a.get('name')!r} / サブタイトル {a.get('subtitle')!r}"
                  f" / プライバシーURL {'あり' if a.get('privacyPolicyUrl') else 'なし'}")
        missing = sorted(set(LOCALE_MAP.values()) - set(loc))
        if missing:
            print(f"    未作成の言語: {', '.join(missing)}")
        ia = info["attributes"]
        print(f"  年齢制限: {ia.get('appStoreAgeRating')}")
        for name in ("primaryCategory", "secondaryCategory"):
            try:
                category = client.get(f"/v1/appInfos/{info['id']}/{name}").get("data")
            except ASCError:
                category = None
            print(f"  {name}: {category['id'] if category else '未設定'}")

    # 価格（無料なら価格表の設定が要る）
    try:
        prices = client.get(
            f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices&limit=5")
        included = prices.get("included", [])
        print(f"\n  価格スケジュール: {'設定済み' if included or prices.get('data') else '未設定'}")
    except ASCError:
        print("\n  価格スケジュール: 取得できませんでした（App Store Connect で確認してください）")

    print("\n  ※ App のプライバシー（データ収集の申告）は API では設定できないため、"
          "App Store Connect の画面で行ってください。")
    return 0


# --- 反映 ---------------------------------------------------------------------
def localized_url(base: str, locale: str) -> str:
    """公式サイトの言語別URL。ロケールに対応するページが無ければ英語にする。"""
    slug = {"ja": "ja", "en-US": "en", "zh-Hans": "zh", "es-ES": "es",
            "de-DE": "de", "fr-FR": "fr", "ko": "ko"}.get(locale, "en")
    return base.replace("/{lang}/", f"/{slug}/")


def push(client: Client, bundle_id: str, version_string: str) -> int:
    data = json.loads(io.open(METADATA, encoding="utf-8").read())
    app = find_app(client, bundle_id)
    app_id = app["id"]
    print(f"アプリ: {app['attributes'].get('name')} (id={app_id})")

    # --- バージョン ---
    # 一度も公開していないアプリの初回バージョンには「このバージョンの新機能」を書けない。
    all_versions = client.get(f"/v1/apps/{app_id}/appStoreVersions?limit=50").get("data", [])
    is_first_release = not any(
        v["attributes"].get("appStoreState") in RELEASED_STATES for v in all_versions
    )
    if is_first_release:
        print("初回リリースのため「このバージョンの新機能」は送りません（Apple 側で編集不可）")

    version = editable_version(client, app_id)
    if version is None:
        print(f"編集できるバージョンが無いので {version_string} を作成します")
        created = client.write("POST", "/v1/appStoreVersions", {
            "data": {
                "type": "appStoreVersions",
                "attributes": {"platform": "IOS", "versionString": version_string},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        })
        version = created.get("data")
        if version is None:
            print("  （dry-run のためバージョンは作成していません。以降の言語反映は省略します）")
            return 0
    version_id = version["id"]
    print(f"バージョン {version['attributes']['versionString']} "
          f"（{version['attributes'].get('appStoreState')}）に反映します")

    existing = localizations(client, f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    for lang, locale in LOCALE_MAP.items():
        attributes = {
            "description": data["description"][lang],
            "keywords": data["keywords"][lang],
            "promotionalText": data["promotionalText"][lang],
            "supportUrl": localized_url(data["supportURL"], locale),
            "marketingUrl": localized_url(data["marketingURL"], locale),
        }
        if not is_first_release:
            attributes["whatsNew"] = data["whatsNew"][lang]
        if locale in existing:
            print(f"  更新: {locale}")
            client.write("PATCH", f"/v1/appStoreVersionLocalizations/{existing[locale]['id']}", {
                "data": {"type": "appStoreVersionLocalizations",
                         "id": existing[locale]["id"], "attributes": attributes}
            })
        else:
            print(f"  作成: {locale}")
            client.write("POST", "/v1/appStoreVersionLocalizations", {
                "data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {
                        "appStoreVersion": {
                            "data": {"type": "appStoreVersions", "id": version_id}
                        }
                    },
                }
            })

    # --- App 情報（名前・サブタイトル・プライバシーポリシーURL） ---
    info = editable_app_info(client, app_id)
    if info is None:
        print("App 情報が取得できませんでした（名前・サブタイトルは手動で確認してください）")
        return 0
    info_id = info["id"]
    existing_info = localizations(client, f"/v1/appInfos/{info_id}/appInfoLocalizations")
    print("App 情報（名前・サブタイトル・プライバシーポリシーURL）を反映します")
    for lang, locale in LOCALE_MAP.items():
        attributes = {
            "name": data["name"][lang],
            "subtitle": data["subtitle"][lang],
            "privacyPolicyUrl": localized_url(data["privacyPolicyURL"], locale),
        }
        if locale in existing_info:
            print(f"  更新: {locale}")
            client.write("PATCH", f"/v1/appInfoLocalizations/{existing_info[locale]['id']}", {
                "data": {"type": "appInfoLocalizations",
                         "id": existing_info[locale]["id"], "attributes": attributes}
            })
        else:
            print(f"  作成: {locale}")
            client.write("POST", "/v1/appInfoLocalizations", {
                "data": {
                    "type": "appInfoLocalizations",
                    "attributes": {**attributes, "locale": locale},
                    "relationships": {
                        "appInfo": {"data": {"type": "appInfos", "id": info_id}}
                    },
                }
            })

    print("\n完了しました。スクリーンショット・年齢制限・価格・審査メモは App Store Connect で確認してください。")
    return 0


def attach_build(client: Client, bundle_id: str, build_version: str | None) -> int:
    """TestFlight のビルドを、提出予定のバージョンに紐づける。

    処理が終わっていない（PROCESSING）ビルドは選べないので、VALID のものから選ぶ。
    """
    app = find_app(client, bundle_id)
    app_id = app["id"]
    version = editable_version(client, app_id)
    if version is None:
        raise SystemExit("編集できるバージョンがありません。先に push でバージョンを作ってください。")

    builds = client.get(f"/v1/builds?filter[app]={app_id}&sort=-version&limit=20").get("data", [])
    usable = [b for b in builds
              if b["attributes"].get("processingState") == "VALID"
              and not b["attributes"].get("expired")]
    if build_version:
        usable = [b for b in usable if b["attributes"].get("version") == build_version]
    if not usable:
        states = ", ".join(
            f"{b['attributes'].get('version')}({b['attributes'].get('processingState')})"
            for b in builds[:5]) or "なし"
        raise SystemExit(f"使えるビルドがありません。いまの状態: {states}")

    build = usable[0]
    print(f"バージョン {version['attributes']['versionString']} に "
          f"build {build['attributes']['version']} を紐づけます")
    client.write("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build",
                 {"data": {"type": "builds", "id": build["id"]}})
    print("完了しました。")
    return 0


def set_category(client: Client, bundle_id: str, primary: str, secondary: str | None) -> int:
    """主要カテゴリ（必要なら副カテゴリ）を設定する。"""
    app = find_app(client, bundle_id)
    info = editable_app_info(client, app["id"])
    if info is None:
        raise SystemExit("App 情報が取得できませんでした。")

    relationships = {
        "primaryCategory": {"data": {"type": "appCategories", "id": primary}}
    }
    if secondary:
        relationships["secondaryCategory"] = {
            "data": {"type": "appCategories", "id": secondary}
        }
    print(f"カテゴリを設定します: 主 {primary}" + (f" / 副 {secondary}" if secondary else ""))
    client.write("PATCH", f"/v1/appInfos/{info['id']}", {
        "data": {"type": "appInfos", "id": info["id"], "relationships": relationships}
    })
    print("完了しました。")
    return 0


def read_review_notes() -> str:
    """review-notes-en.md の ``` で囲まれた本文を取り出す。"""
    text = io.open(REVIEW_NOTES, encoding="utf-8").read()
    parts = text.split("```")
    if len(parts) < 3:
        raise SystemExit(f"{REVIEW_NOTES.name} に本文（``` で囲んだ部分）がありません。")
    return parts[1].strip()


def set_review_details(client: Client, bundle_id: str, contact: dict) -> int:
    """審査連絡先と審査メモを登録する（App Review Information）。

    電話番号が渡されていない場合でも、App Store Connect 側で連絡先が入力済みなら
    **審査メモだけ**を更新する（電話番号を人に渡さずに済ませたいとき用）。
    """
    app = find_app(client, bundle_id)
    version = editable_version(client, app["id"])
    if version is None:
        raise SystemExit("編集できるバージョンがありません。")

    try:
        existing = client.get(
            f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    except ASCError:
        existing = None

    notes = read_review_notes()

    # 連絡先が渡されていないとき: 画面で入力済みならメモだけ更新する。
    if not contact.get("phone"):
        if not (existing and existing["attributes"].get("contactPhone")):
            raise SystemExit(
                "審査連絡先の電話番号がありません。\n"
                "Secret ASC_REVIEW_PHONE を登録するか、App Store Connect の"
                "「App 審査に関する情報」で連絡先を入力してから実行してください。")
        print(f"連絡先は App Store Connect の入力を使い、審査メモ（{len(notes)} 文字）だけ更新します")
        client.write("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {
            "data": {"type": "appStoreReviewDetails", "id": existing["id"],
                     "attributes": {"notes": notes, "demoAccountRequired": False}}
        })
        print("完了しました。")
        return 0

    attributes = {
        "contactFirstName": contact["first_name"],
        "contactLastName": contact["last_name"],
        "contactPhone": contact["phone"],
        "contactEmail": contact["email"],
        "notes": notes,
        "demoAccountRequired": False,
    }
    # 連絡先そのものは表示しない（Public リポジトリのログに残さない）。
    print(f"審査情報を登録します（メモ {len(notes)} 文字 / 連絡先は非表示）")

    if existing:
        client.write("PATCH", f"/v1/appStoreReviewDetails/{existing['id']}", {
            "data": {"type": "appStoreReviewDetails", "id": existing["id"],
                     "attributes": attributes}
        })
    else:
        client.write("POST", "/v1/appStoreReviewDetails", {
            "data": {
                "type": "appStoreReviewDetails",
                "attributes": attributes,
                "relationships": {
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version["id"]}
                    }
                },
            }
        })
    print("完了しました。")
    return 0


def upload_binary(url: str, method: str, headers: list[dict], chunk: bytes) -> None:
    """予約時に返ってきた指示どおりに画像の一部を送る。"""
    req = urllib.request.Request(url, data=chunk, method=method)
    for header in headers:
        req.add_header(header["name"], header["value"])
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise ASCError(method, url, e.code, detail) from None


def upload_screenshot(client: Client, set_id: str, image: Path, order: int) -> None:
    data = image.read_bytes()
    # ファイル名は App Store Connect 上の表示名。撮影時の UUID を落として並び順が分かる名前にする。
    name = re.sub(r"_0_[0-9A-F-]+\.png$", ".png", image.name, flags=re.IGNORECASE)
    print(f"    {order + 1}. {name}（{len(data) // 1024} KB）")
    if client.dry_run:
        return

    reserved = client.request("POST", "/v1/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": len(data), "fileName": name},
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        }
    })["data"]

    for operation in reserved["attributes"].get("uploadOperations", []):
        start = operation["offset"]
        end = start + operation["length"]
        upload_binary(operation["url"], operation["method"],
                      operation.get("requestHeaders", []), data[start:end])

    client.request("PATCH", f"/v1/appScreenshots/{reserved['id']}", {
        "data": {
            "type": "appScreenshots",
            "id": reserved["id"],
            "attributes": {"uploaded": True,
                           "sourceFileChecksum": hashlib.md5(data).hexdigest()},
        }
    })


def reorder_screenshots(client: Client, set_id: str) -> None:
    """セット内の画像をファイル名順（01,02,…）に並べ替える。

    追加でアップロードした画像は末尾に付くため、そのままだと
    「再生画面」が最後に来てしまう。表示順は名前で決めるのが分かりやすい。
    """
    shots = client.get(f"/v1/appScreenshotSets/{set_id}/appScreenshots?limit=50").get("data", [])
    if len(shots) < 2:
        return
    ordered = sorted(shots, key=lambda shot: shot["attributes"].get("fileName") or "")
    if [s["id"] for s in ordered] == [s["id"] for s in shots]:
        return
    print("    並び順を "
          + " → ".join((s["attributes"].get("fileName") or "?").split("-")[0] for s in ordered))
    client.request("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots", {
        "data": [{"type": "appScreenshots", "id": shot["id"]} for shot in ordered]
    })


def push_screenshots(client: Client, bundle_id: str, directory: Path,
                     display_type: str, replace: bool) -> int:
    """`<ディレクトリ>/<ロケール>/*.png` を言語ごとにアップロードする。

    ロケール名のフォルダは ASC のロケール（ja, en-US, ...）でも、原本の言語キー（ja, en, ...）でもよい。
    """
    if not directory.is_dir():
        raise SystemExit(f"スクリーンショットのフォルダがありません: {directory}")

    app = find_app(client, bundle_id)
    version = editable_version(client, app["id"])
    if version is None:
        raise SystemExit("編集できるバージョンがありません。")
    version_locs = localizations(
        client, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")

    total = 0
    for folder in sorted(p for p in directory.iterdir() if p.is_dir()):
        locale = LOCALE_MAP.get(folder.name, folder.name)
        if locale not in version_locs:
            print(f"  {folder.name}: ロケール {locale} が未作成のため飛ばします")
            continue
        images = sorted((p for p in folder.iterdir()
                         if p.suffix.lower() in {".png", ".jpg", ".jpeg"}
                         and not p.name.startswith(("00-", "ERROR"))),
                        key=lambda p: p.name)
        if not images:
            print(f"  {locale}: 画像がありません")
            continue

        loc_id = version_locs[locale]["id"]
        sets = client.get(
            f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets?limit=20").get("data", [])
        target = next((s for s in sets
                       if s["attributes"].get("screenshotDisplayType") == display_type), None)

        if target and replace:
            existing = client.get(
                f"/v1/appScreenshotSets/{target['id']}/appScreenshots?limit=50").get("data", [])
            for shot in existing:
                print(f"  {locale}: 既存の画像を削除 {shot['attributes'].get('fileName')}")
                if not client.dry_run:
                    client.request("DELETE", f"/v1/appScreenshots/{shot['id']}")

        if target is None:
            print(f"  {locale}: {display_type} のセットを作成します")
            created = client.write("POST", "/v1/appScreenshotSets", {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": display_type},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": loc_id}
                        }
                    },
                }
            })
            target = created.get("data")
            if target is None:
                print("    （dry-run のため以降は表示のみ）")

        print(f"  {locale}: {len(images)} 枚")
        for order, image in enumerate(images):
            upload_screenshot(client, target["id"] if target else "dry-run", image, order)
            total += 1

        if target and not client.dry_run:
            reorder_screenshots(client, target["id"])

    print(f"\n合計 {total} 枚を処理しました。")
    return 0


def diagnose(client: Client, bundle_id: str) -> int:
    """提出前チェック。読み取れる範囲で「未設定のまま提出しようとしていないか」を見る。"""
    app = find_app(client, bundle_id)
    app_id = app["id"]
    print(f"アプリ: {app['attributes'].get('name')} (id={app_id})\n")

    def probe(label: str, path: str, summarize=None) -> None:
        try:
            res = client.get(path)
        except ASCError as error:
            first = ""
            try:
                first = json.loads(error.detail)["errors"][0].get("detail", "")
            except Exception:
                first = error.detail[:120].replace("\n", " ")
            print(f"  {label}: 取得できず（HTTP {error.code}）{first}")
            return
        data = res.get("data")
        if not data:
            print(f"  {label}: 未設定")
            return
        print(f"  {label}: {summarize(res) if summarize else 'あり'}")

    print("価格・配信")
    probe("価格スケジュール", f"/v1/apps/{app_id}/appPriceSchedule?include=manualPrices,baseTerritory",
          lambda res: "設定あり（"
                      + ", ".join(sorted({item["type"] for item in res.get("included", [])}))
                      + "）" if res.get("included") else "設定あり")
    probe("配信地域", f"/v1/apps/{app_id}/appAvailabilityV2",
          lambda res: "全地域向け"
                      if res["data"]["attributes"].get("availableInNewTerritories")
                      else "地域を限定して配信")

    # App のプライバシー（データ収集の申告）は公開 API から読めないため、画面での確認を促す。
    print("\nApp のプライバシー（データ収集の申告）")
    print("  API では読めません。App Store Connect の「App のプライバシー」で"
          "『データを収集していません』になっているか目視で確認してください。")

    print("\nバージョン")
    version = editable_version(client, app_id)
    if version is None:
        print("  編集できるバージョンがありません")
        return 0
    va = version["attributes"]
    print(f"  {va.get('versionString')}: {va.get('appStoreState')} / 公開方法 {va.get('releaseType')}")

    checks = []
    locs = localizations(
        client, f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    primary = app["attributes"].get("primaryLocale")
    for locale, item in sorted(locs.items()):
        a = item["attributes"]
        shots = client.get(
            f"/v1/appStoreVersionLocalizations/{item['id']}/appScreenshotSets?limit=10"
        ).get("data", [])
        if not a.get("description"):
            checks.append(f"{locale}: 説明が未入力")
        if locale == primary and not shots:
            checks.append(f"{locale}（主要言語）: スクリーンショットが未登録")

    if not client.get(f"/v1/appStoreVersions/{version['id']}/build").get("data"):
        checks.append("ビルドが未選択")
    try:
        if not client.get(
                f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data"):
            checks.append("審査に関する情報が未入力")
    except ASCError:
        checks.append("審査に関する情報が未入力")

    print("\n提出前チェック")
    if checks:
        for item in checks:
            print(f"  × {item}")
    else:
        print("  ○ API から見える範囲では不足はありません")
    print("\n  ※ EU の事業者（トレーダー）情報と「App のプライバシー」の細目は、"
          "App Store Connect の画面でも目視確認してください。")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=["status", "push", "attach-build", "category", "review", "screenshots",
                 "diagnose"],
        default="status")
    parser.add_argument("--primary-category", default="EDUCATION")
    parser.add_argument("--screenshots-dir", default="screenshots",
                        help="<ロケール>/xx.png を並べたフォルダ")
    parser.add_argument("--display-type", default="APP_IPHONE_67",
                        help="画面サイズの種類（6.7/6.9インチは APP_IPHONE_67）")
    parser.add_argument("--replace", action="store_true",
                        help="既にある画像を消してから入れ直す")
    parser.add_argument("--secondary-category", default="")
    parser.add_argument("--build", default="", help="紐づけるビルド番号（空なら最新の VALID）")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--version", default="1.0", help="編集できるバージョンが無いときに作る版数")
    parser.add_argument("--dry-run", action="store_true", help="変更内容を表示するだけで送信しない")
    parser.add_argument("--key-id", default=os.environ.get("ASC_KEY_ID", ""))
    parser.add_argument("--issuer-id", default=os.environ.get("ASC_ISSUER_ID", ""))
    parser.add_argument("--private-key", default=os.environ.get("ASC_PRIVATE_KEY", ""),
                        help="AuthKey_XXXX.p8 の中身（表示しない）")
    args = parser.parse_args()

    if not (args.key_id and args.issuer_id and args.private_key):
        raise SystemExit("ASC_KEY_ID / ASC_ISSUER_ID / ASC_PRIVATE_KEY が必要です。")

    client = Client(make_token(args.key_id, args.issuer_id, args.private_key),
                    dry_run=args.dry_run)
    try:
        if args.mode == "status":
            return show_status(client, args.bundle_id)
        if args.mode == "attach-build":
            return attach_build(client, args.bundle_id, args.build or None)
        if args.mode == "diagnose":
            return diagnose(client, args.bundle_id)
        if args.mode == "screenshots":
            return push_screenshots(client, args.bundle_id, Path(args.screenshots_dir),
                                    args.display_type, args.replace)
        if args.mode == "category":
            return set_category(client, args.bundle_id,
                                args.primary_category, args.secondary_category or None)
        if args.mode == "review":
            # ワークフローからは未設定の Secret も「空文字」で渡ってくるため、
            # get(..., 既定値) ではなく or で拾う（空なら既定値にする）。
            contact = {
                "first_name": os.environ.get("ASC_REVIEW_FIRST_NAME") or "Toshiharu",
                "last_name": os.environ.get("ASC_REVIEW_LAST_NAME") or "Katami",
                "phone": os.environ.get("ASC_REVIEW_PHONE") or "",
                "email": (os.environ.get("ASC_REVIEW_EMAIL")
                          or "atamitrading@jewelrysunflower.com"),
            }
            return set_review_details(client, args.bundle_id, contact)
        return push(client, args.bundle_id, args.version)
    except ASCError as error:
        raise SystemExit(str(error)) from None


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
