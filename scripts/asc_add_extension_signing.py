# -*- coding: utf-8 -*-
"""Share Extension 用の Bundle ID とプロビジョニングプロファイルを **Mac なしで** 用意する。

共有シート（Share Extension）はアプリ本体とは別の Bundle ID を持つため、
App Store 配布用のプロファイルもアプリ本体とは別に必要になる。
このスクリプトは App Store Connect API を使って次を行う:

  1. Share Extension の Bundle ID を確認し、無ければ登録 (POST /v1/bundleIds)
  2. 有効な配布証明書 (Apple Distribution) を取得
  3. Share Extension 用の App Store 配布プロファイルを作成 (POST /v1/profiles)
  4. base64 化して GitHub Secrets に登録
       PROVISIONING_PROFILE_EXT_BASE64 / PROVISIONING_PROFILE_EXT_NAME

前提:
  - `scripts/asc_setup_signing.py` を実行済み（配布証明書と本体用プロファイルが作成済み）
  - App Store Connect API の チームキー(.p8) を持っている
  - gh CLI がログイン済み

使い方:
    python scripts/asc_add_extension_signing.py \
        --key-id <ASC Key ID> \
        --issuer-id <ASC Issuer ID> \
        --p8 <AuthKey_XXXX.p8 のパス> \
        [--repo kataming/ChannelTimelineViewer] \
        [--dry-run]

秘密情報は標準出力に出さない（プロファイル/証明書の中身は表示しない）。
"""

from __future__ import annotations

import argparse
import base64
import datetime as _dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from asc_setup_signing import (  # noqa: E402  (パス調整後に import する)
    DEFAULT_OUT_DIR,
    api,
    make_token,
    set_secret,
)

APP_BUNDLE_ID = "com.deskflowlabs.channeltimelineviewer"
EXT_BUNDLE_ID = "com.deskflowlabs.channeltimelineviewer.shareextension"
EXT_BUNDLE_NAME = "Channel Timeline Viewer Share Extension"
EXT_PROFILE_NAME = "ChannelTimelineViewer ShareExtension App Store"
PROFILE_TYPE = "IOS_APP_STORE"


def find_bundle_id(token: str, identifier: str) -> str | None:
    """登録済み Bundle ID のリソースIDを返す（無ければ None）。"""
    res = api(token, "GET", f"/v1/bundleIds?filter[identifier]={identifier}&limit=200")
    for item in res.get("data", []):
        if item["attributes"].get("identifier") == identifier:
            return item["id"]
    return None


def create_bundle_id(token: str, identifier: str, name: str) -> str:
    res = api(
        token,
        "POST",
        "/v1/bundleIds",
        {
            "data": {
                "type": "bundleIds",
                "attributes": {
                    "identifier": identifier,
                    "name": name,
                    "platform": "IOS",
                },
            }
        },
    )
    return res["data"]["id"]


def find_reusable_profile(token: str, bundle_identifier: str, cert_ids: set[str]) -> dict | None:
    """指定 Bundle ID 用の、有効でいま使える配布プロファイルを1つ返す（無ければ None）。

    CI から毎回実行するため、使い回せるものがあれば作り直さない
    （実行のたびにプロファイルが増えていくのを防ぐ）。
    証明書が入れ替わっている場合は使えないので、含まれる証明書もチェックする。
    """
    # ※ fields[profiles] で属性を絞ると relationships まで落ちることがあるので指定しない。
    res = api(token, "GET", "/v1/profiles?limit=200&include=bundleId")
    # include で返る bundleIds の id -> identifier を作る
    identifiers = {
        item["id"]: item["attributes"].get("identifier")
        for item in res.get("included", [])
        if item.get("type") == "bundleIds"
    }
    candidates = []
    for prof in res.get("data", []):
        attrs = prof["attributes"]
        if attrs.get("profileType") != PROFILE_TYPE:
            continue
        if attrs.get("profileState") != "ACTIVE":
            continue
        rel = prof.get("relationships", {}).get("bundleId", {}).get("data") or {}
        if identifiers.get(rel.get("id")) != bundle_identifier:
            continue
        candidates.append(prof)

    for prof in sorted(
        candidates, key=lambda p: p["attributes"].get("expirationDate") or "", reverse=True
    ):
        linked = api(token, "GET", f"/v1/profiles/{prof['id']}/certificates?limit=200")
        linked_ids = {c["id"] for c in linked.get("data", [])}
        if linked_ids & cert_ids:
            return prof
    return None


def valid_distribution_certificates(token: str) -> list[dict]:
    """期限内の配布証明書を新しい順に返す。"""
    res = api(token, "GET", "/v1/certificates?limit=200")
    now = _dt.datetime.now(_dt.timezone.utc)
    certs = []
    for cert in res.get("data", []):
        attrs = cert["attributes"]
        if attrs.get("certificateType") not in ("DISTRIBUTION", "IOS_DISTRIBUTION"):
            continue
        expiry = attrs.get("expirationDate")
        if expiry:
            try:
                if _dt.datetime.fromisoformat(expiry.replace("Z", "+00:00")) <= now:
                    continue
            except ValueError:
                pass
        certs.append(cert)
    return certs


def create_profile(token: str, name: str, bundle_res_id: str, cert_ids: list[str]) -> dict:
    prof = api(
        token,
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": name, "profileType": PROFILE_TYPE},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_res_id}},
                    # CI の keychain に入る証明書がどれでも通るよう、有効な配布証明書をすべて含める
                    "certificates": {
                        "data": [{"type": "certificates", "id": cid} for cid in cert_ids]
                    },
                },
            }
        },
    )
    return prof["data"]


def run_ci(args) -> None:
    """CI から呼ぶ: Bundle ID とプロファイルを用意し、ファイルに書き出すだけ。

    GitHub Secrets への登録は行わない（Actions の GITHUB_TOKEN では Secret を書けないため）。
    リリースのたびに実行されるので、**使えるプロファイルがあれば作り直さない**。
    """
    if not args.out or not args.name_out:
        raise SystemExit("--ci には --out と --name-out が必要です")

    token = make_token(args.key_id, args.issuer_id, args.p8)

    ext_res_id = find_bundle_id(token, args.bundle_id)
    if ext_res_id is None:
        print(f"Bundle ID を登録します: {args.bundle_id}")
        ext_res_id = create_bundle_id(token, args.bundle_id, args.bundle_name)
        print(f"  ✓ 登録しました (id={ext_res_id})")
    else:
        print(f"Bundle ID は登録済み: {args.bundle_id}")

    certs = valid_distribution_certificates(token)
    if not certs:
        raise SystemExit("有効な配布証明書がありません（scripts/asc_setup_signing.py を実行してください）")
    cert_ids = [c["id"] for c in certs]

    reusable = find_reusable_profile(token, args.bundle_id, set(cert_ids))
    if reusable is not None:
        data = reusable
        print(f"既存プロファイルを再利用します: {data['attributes'].get('name')}")
    else:
        stamp = _dt.datetime.now().strftime("%Y%m%d%H%M%S")
        name = f"{args.profile_name} {stamp}"
        print(f"プロファイルを作成します: {name}")
        data = create_profile(token, name, ext_res_id, cert_ids)

    attrs = data["attributes"]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(base64.b64decode(attrs["profileContent"]))
    args.name_out.write_text(attrs.get("name", ""), encoding="utf-8")
    print(
        f"  ✓ {attrs.get('name')} (UUID {attrs.get('uuid')}, 期限 {attrs.get('expirationDate')})"
    )


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--key-id", required=True, help="App Store Connect API の Key ID")
    p.add_argument("--issuer-id", required=True, help="同 Issuer ID (UUID)")
    p.add_argument("--p8", required=True, type=Path, help="AuthKey_XXXXXX.p8 のパス")
    p.add_argument("--bundle-id", default=EXT_BUNDLE_ID)
    p.add_argument("--bundle-name", default=EXT_BUNDLE_NAME)
    p.add_argument("--profile-name", default=EXT_PROFILE_NAME)
    p.add_argument("--repo", default="kataming/ChannelTimelineViewer")
    p.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="現状の確認だけを行い、作成・Secret 登録はしない",
    )
    p.add_argument(
        "--ci",
        action="store_true",
        help=(
            "CI(GitHub Actions)から実行するモード。gh secret set は行わず、"
            "使えるプロファイルがあれば再利用して --out / --name-out に書き出す"
        ),
    )
    p.add_argument("--out", type=Path, help="--ci: プロファイル(.mobileprovision)の出力先")
    p.add_argument("--name-out", type=Path, help="--ci: プロファイル名の出力先")
    args = p.parse_args()

    if not args.p8.exists():
        raise SystemExit(f"p8 ファイルが見つかりません: {args.p8}")

    if args.ci:
        run_ci(args)
        return

    token = make_token(args.key_id, args.issuer_id, args.p8)
    print("App Store Connect API に接続しています…")

    # 0) 本体の Bundle ID があることを確認（無ければ手順そのものが誤り）
    if find_bundle_id(token, APP_BUNDLE_ID) is None:
        raise SystemExit(
            f"アプリ本体の Bundle ID '{APP_BUNDLE_ID}' が見つかりません。"
            "先に scripts/asc_setup_signing.py を実行してください。"
        )

    # 1) 拡張の Bundle ID
    ext_res_id = find_bundle_id(token, args.bundle_id)
    if ext_res_id:
        print(f"Bundle ID は登録済み: {args.bundle_id} (id={ext_res_id})")
    else:
        print(f"Bundle ID が未登録です: {args.bundle_id}")
        if args.dry_run:
            print("--dry-run のため作成しません。")
        else:
            ext_res_id = create_bundle_id(token, args.bundle_id, args.bundle_name)
            print(f"  ✓ 登録しました (id={ext_res_id})")

    # 2) 配布証明書
    certs = valid_distribution_certificates(token)
    print(f"\n有効な配布証明書: {len(certs)} 件")
    for cert in certs:
        attrs = cert["attributes"]
        print(f"  - {attrs.get('displayName')} / 期限 {attrs.get('expirationDate')} / id={cert['id']}")
    if not certs:
        raise SystemExit(
            "有効な配布証明書がありません。scripts/asc_setup_signing.py で発行してください。"
        )

    # 3) 既存プロファイルの確認
    profiles = api(token, "GET", "/v1/profiles?limit=200")
    same_name = [
        pr for pr in profiles.get("data", [])
        if pr["attributes"].get("name") == args.profile_name
    ]
    print(f"既存プロファイル(同名): {len(same_name)} 件")

    if args.dry_run:
        print("\n--dry-run のため、作成・登録は行いませんでした。")
        return

    stamp = _dt.datetime.now().strftime("%Y%m%d%H%M%S")
    profile_name = args.profile_name if not same_name else f"{args.profile_name} {stamp}"

    print("\nShare Extension 用プロビジョニングプロファイルを作成しています…")
    prof_data = create_profile(token, profile_name, ext_res_id, [c["id"] for c in certs])
    attrs = prof_data["attributes"]
    profile_b64 = attrs["profileContent"]  # 既に base64
    args.out_dir.mkdir(parents=True, exist_ok=True)
    out_path = args.out_dir / "profile-shareextension.mobileprovision"
    out_path.write_bytes(base64.b64decode(profile_b64))
    print(
        f"  ✓ 作成: {attrs.get('name')} "
        f"(UUID {attrs.get('uuid')}, 期限 {attrs.get('expirationDate')})"
    )

    print(f"\nGitHub Secrets に登録しています ({args.repo})…")
    set_secret(args.repo, "PROVISIONING_PROFILE_EXT_BASE64", profile_b64)
    set_secret(args.repo, "PROVISIONING_PROFILE_EXT_NAME", attrs.get("name", profile_name))

    print(
        "\n完了。次は 'iOS Release' ワークフローを実行すると、共有シート拡張を含む "
        ".ipa が TestFlight にアップロードされます:\n"
        f"  gh workflow run ios-release.yml -R {args.repo}\n"
    )


if __name__ == "__main__":
    sys.exit(main())
