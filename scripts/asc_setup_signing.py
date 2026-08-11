# -*- coding: utf-8 -*-
"""App Store Connect API を使って、iOS App Store 配布用の署名アセットを **Mac なしで** 用意する。

やること:
  1. 配布用の秘密鍵(RSA2048) と CSR をローカル生成
  2. ASC API で「Apple Distribution」証明書を発行 (POST /v1/certificates)
  3. 秘密鍵 + 証明書 から .p12 を作成 (GitHub Actions の keychain に取り込む形式)
  4. 登録済み Bundle ID を検索 (GET /v1/bundleIds)
  5. App Store 配布用プロビジョニングプロファイルを作成 (POST /v1/profiles)
  6. 生成物を base64 化して GitHub Secrets に登録 (gh secret set)

前提:
  - App Store Connect の「ユーザーとアクセス → 統合 → App Store Connect API」で
    **チームキー**(Admin または App Manager ロール) を発行し、.p8 をダウンロード済み
  - gh CLI がログイン済み (gh auth status)

秘密情報の扱い:
  - .p8 / 秘密鍵 / .p12 の中身は **標準出力に出さない**。GitHub Secrets へ直接渡す。
  - 生成した秘密鍵・.p12 は既定で out_dir(gitignore 済み) に保存する。

使い方:
    python scripts/asc_setup_signing.py \
        --key-id  <ASC Key ID> \
        --issuer-id <ASC Issuer ID> \
        --p8 <AuthKey_XXXX.p8 のパス> \
        [--bundle-id com.deskflowlabs.channeltimelineviewer] \
        [--repo kataming/ChannelTimelineViewer] \
        [--dry-run]   # 既存アセットの確認だけ行い、作成・登録はしない
"""

from __future__ import annotations

import argparse
import base64
import datetime as _dt
import json
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API_BASE = "https://api.appstoreconnect.apple.com"
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT_DIR = REPO_ROOT / "build" / "signing"

# 発行する証明書の種類。Apple Distribution(=iOS/tvOS 共用の配布証明書)
CERTIFICATE_TYPE = "DISTRIBUTION"
PROFILE_TYPE = "IOS_APP_STORE"


# --- ASC API -----------------------------------------------------------------
def make_token(key_id: str, issuer_id: str, p8_path: Path) -> str:
    """ASC API 用の ES256 JWT を作る(有効期限は仕様上の上限 20 分未満)。"""
    private_key = p8_path.read_text(encoding="utf-8")
    now = int(time.time())
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 15 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(
        payload, private_key, algorithm="ES256", headers={"kid": key_id, "typ": "JWT"}
    )


def api(token: str, method: str, path: str, body: dict | None = None) -> dict:
    url = path if path.startswith("http") else f"{API_BASE}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")
        raise SystemExit(
            f"[ASC API エラー] {method} {path} -> HTTP {e.code}\n{detail}"
        ) from None


# --- 鍵 / CSR / p12 -----------------------------------------------------------
def generate_key_and_csr(common_name: str, country: str = "JP"):
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = (
        x509.CertificateSigningRequestBuilder()
        .subject_name(
            x509.Name(
                [
                    x509.NameAttribute(NameOID.COMMON_NAME, common_name),
                    x509.NameAttribute(NameOID.COUNTRY_NAME, country),
                ]
            )
        )
        .sign(key, hashes.SHA256())
    )
    csr_pem = csr.public_bytes(serialization.Encoding.PEM).decode("ascii")
    return key, csr_pem


def build_p12(key, cert_der: bytes, password: str, friendly_name: str) -> bytes:
    cert = x509.load_der_x509_certificate(cert_der)
    return pkcs12.serialize_key_and_certificates(
        name=friendly_name.encode("utf-8"),
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(
            password.encode("utf-8")
        ),
    )


# --- GitHub Secrets -----------------------------------------------------------
def set_secret(repo: str, name: str, value: str) -> None:
    """gh secret set を stdin 経由で実行する(値をコマンドライン/ログに出さない)。"""
    proc = subprocess.run(
        ["gh", "secret", "set", name, "-R", repo, "--body-file", "-"],
        input=value.encode("utf-8"),
        capture_output=True,
    )
    if proc.returncode != 0:
        raise SystemExit(
            f"[gh secret set 失敗] {name}\n{proc.stderr.decode('utf-8', errors='replace')}"
        )
    print(f"  ✓ Secret 登録: {name}")


# --- メイン -------------------------------------------------------------------
def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--key-id", required=True, help="App Store Connect API の Key ID")
    p.add_argument("--issuer-id", required=True, help="同 Issuer ID (UUID)")
    p.add_argument("--p8", required=True, type=Path, help="AuthKey_XXXXXX.p8 のパス")
    p.add_argument(
        "--bundle-id", default="com.deskflowlabs.channeltimelineviewer",
    )
    p.add_argument("--repo", default="kataming/ChannelTimelineViewer")
    p.add_argument("--profile-name", default="ChannelTimelineViewer App Store")
    p.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="既存の証明書/Bundle ID/プロファイルを表示するだけで、作成も Secret 登録もしない",
    )
    p.add_argument(
        "--reuse-cert-id",
        default=None,
        help="既存の証明書を使う場合の certificate id(秘密鍵が手元にある時のみ有効)",
    )
    args = p.parse_args()

    if not args.p8.exists():
        raise SystemExit(f"p8 ファイルが見つかりません: {args.p8}")

    token = make_token(args.key_id, args.issuer_id, args.p8)
    print("App Store Connect API に接続しています…")

    # 1) 既存の証明書を確認(Apple Distribution は同時に持てる数に上限があるため)
    certs = api(token, "GET", "/v1/certificates?limit=200")
    dist = [
        c
        for c in certs.get("data", [])
        if c["attributes"].get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION")
    ]
    print(f"\n既存の配布証明書: {len(dist)} 件")
    for c in dist:
        a = c["attributes"]
        print(
            f"  - {a.get('certificateType')} / {a.get('displayName')} "
            f"/ 期限 {a.get('expirationDate')} / id={c['id']}"
        )

    # 2) Bundle ID を確認
    bundles = api(
        token,
        "GET",
        f"/v1/bundleIds?filter[identifier]={args.bundle_id}&limit=200",
    )
    bundle_data = [
        b for b in bundles.get("data", [])
        if b["attributes"].get("identifier") == args.bundle_id
    ]
    if not bundle_data:
        raise SystemExit(
            f"Bundle ID '{args.bundle_id}' が Apple Developer に見つかりません。\n"
            "App Store Connect / Certificates,Identifiers&Profiles で登録済みか確認してください。"
        )
    bundle_res_id = bundle_data[0]["id"]
    print(f"\nBundle ID: {args.bundle_id} (id={bundle_res_id})")

    # 3) 既存プロファイルを確認
    profiles = api(token, "GET", "/v1/profiles?limit=200")
    same_name = [
        pr for pr in profiles.get("data", [])
        if pr["attributes"].get("name") == args.profile_name
    ]
    print(f"既存プロファイル(同名): {len(same_name)} 件")

    if args.dry_run:
        print("\n--dry-run のため、作成・登録は行いませんでした。")
        return

    args.out_dir.mkdir(parents=True, exist_ok=True)

    # 4) 証明書を発行
    print("\n配布証明書を発行しています…")
    key, csr_pem = generate_key_and_csr(common_name="Channel Timeline Viewer Distribution")
    (args.out_dir / "distribution.key.pem").write_bytes(
        key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.PKCS8,
            encryption_algorithm=serialization.NoEncryption(),
        )
    )
    created = api(
        token,
        "POST",
        "/v1/certificates",
        {
            "data": {
                "type": "certificates",
                "attributes": {
                    "certificateType": CERTIFICATE_TYPE,
                    "csrContent": csr_pem,
                },
            }
        },
    )
    cert_id = created["data"]["id"]
    cert_attrs = created["data"]["attributes"]
    cert_der = base64.b64decode(cert_attrs["certificateContent"])
    (args.out_dir / "distribution.cer").write_bytes(cert_der)
    print(
        f"  ✓ 発行: {cert_attrs.get('displayName')} "
        f"(期限 {cert_attrs.get('expirationDate')}, id={cert_id})"
    )

    # 5) .p12 を作成
    p12_password = secrets.token_urlsafe(24)
    p12_bytes = build_p12(
        key, cert_der, p12_password, "Channel Timeline Viewer Distribution"
    )
    (args.out_dir / "distribution.p12").write_bytes(p12_bytes)
    print("  ✓ .p12 を作成(build/signing/distribution.p12)")

    # 6) プロビジョニングプロファイルを作成
    print("\nプロビジョニングプロファイルを作成しています…")
    stamp = _dt.datetime.now().strftime("%Y%m%d%H%M%S")
    profile_name = args.profile_name if not same_name else f"{args.profile_name} {stamp}"
    prof = api(
        token,
        "POST",
        "/v1/profiles",
        {
            "data": {
                "type": "profiles",
                "attributes": {"name": profile_name, "profileType": PROFILE_TYPE},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_res_id}},
                    "certificates": {
                        "data": [{"type": "certificates", "id": cert_id}]
                    },
                },
            }
        },
    )
    prof_attrs = prof["data"]["attributes"]
    profile_b64 = prof_attrs["profileContent"]  # 既に base64
    (args.out_dir / "profile.mobileprovision").write_bytes(
        base64.b64decode(profile_b64)
    )
    print(
        f"  ✓ 作成: {prof_attrs.get('name')} "
        f"(UUID {prof_attrs.get('uuid')}, 期限 {prof_attrs.get('expirationDate')})"
    )

    # 7) GitHub Secrets に登録
    print(f"\nGitHub Secrets に登録しています ({args.repo})…")
    set_secret(args.repo, "ASC_KEY_ID", args.key_id)
    set_secret(args.repo, "ASC_ISSUER_ID", args.issuer_id)
    set_secret(args.repo, "ASC_PRIVATE_KEY", args.p8.read_text(encoding="utf-8"))
    set_secret(
        args.repo,
        "BUILD_CERT_P12_BASE64",
        base64.b64encode(p12_bytes).decode("ascii"),
    )
    set_secret(args.repo, "BUILD_CERT_PASSWORD", p12_password)
    set_secret(args.repo, "PROVISIONING_PROFILE_BASE64", profile_b64)
    set_secret(args.repo, "PROVISIONING_PROFILE_NAME", prof_attrs.get("name", profile_name))

    print(
        "\n完了。次は GitHub Actions の 'iOS Release' ワークフローを実行してください:\n"
        f"  gh workflow run ios-release.yml -R {args.repo}\n"
        "\n注意: build/signing/ 配下には秘密鍵と .p12 が入っています(.gitignore 済み)。\n"
        "      証明書を再発行するとこのファイルは無効になります。バックアップは安全な場所に。"
    )


if __name__ == "__main__":
    sys.exit(main())
