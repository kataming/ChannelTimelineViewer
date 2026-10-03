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
  --mode promote   すでにアップロード済みのビルドを別トラック（既定は製品版）へ下書きで載せる
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
            # ⚠️ 実際に利用者へ出ている文章まで見る。
            #    版を上げたのに前の版の説明が残っていると、ここでしか気づけない
            #    （トラック名と版数だけ見ても分からない）。
            for release in releases:
                notes = release.get("releaseNotes") or []
                if not notes:
                    continue
                name = release.get("name") or ""
                print(f"      リリースノート（{name}・{len(notes)} 言語）:")
                for note in sorted(notes, key=lambda item: item.get("language", "")):
                    text = (note.get("text") or "").replace("\n", " / ")
                    print(f"        {note.get('language')}: {text}")
    finally:
        edits.delete(packageName=PACKAGE_NAME, editId=edit_id).execute()
    return 0


def push_listing(api, dry_run: bool) -> int:
    data = load_metadata()
    locales = list(data["_locales"])

    if dry_run:
        for locale in locales:
            shots = image_sets(locale)["phoneScreenshots"]
            print(f"  [dry-run] {locale}: テキスト3項目 / スクリーンショット {len(shots)} 枚"
                  f"（{shots[0].parent.name if shots else 'なし'}）")
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
    """言語ごとに入れる画像。アイコンとフィーチャーグラフィックは全言語共通のものを使う。

    スクリーンショットは7言語ぶんしか作らない（2026-10-01 のユーザー判断）。ほかの言語には英語の画像を入れる。
    入れないと Play は既定の言語（日本語）の画像を出すため、アラビア語の利用者に日本語の画面が見えてしまう。
    """
    folder = SCREENSHOT_DIR / locale
    if not folder.is_dir():
        folder = SCREENSHOT_DIR / "en-US"
    screenshots = sorted(
        path for path in folder.glob("*.png")
        if not path.name.startswith(("00-", "ERROR"))
    ) if folder.is_dir() else []
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


# リリースの説明（Play のロケール名で持つ。500字まで）。
#
# ⚠️ バージョンを上げるたびに**ここを書き直すこと**。前の版の文章が残ったまま公開されると、
#    利用者への説明が実態と食い違う（1.8 では計測の追加＝利用者に見える変更が入った）。
#    文言はアプリ内「このアプリについて」の説明（Localization/strings.json の about.analytics.*）と
#    そろえる。画面名も各言語の about.title と同じ表記を使う。
#
# 1.9 (versionCode 11): Pro 購入の計測を「購入開始」と「購入成立」に分けた（公開済み）。
#
# 1.10: 利用者から見える変更が2つ入る。**必ず両方書くこと**。
#   - チャンネルの追加方法の案内（初回チュートリアル）を追加
#   - 自動再生の初期状態をオフ→オンに変更。
#     ⚠️ **「すでにご自分で切り替えた方の設定はそのまま」を必ず書く。**
#     これが抜けると「勝手に設定を変えられた」と受け取られる。実装も実際にそうなっていて、
#     新しい既定が効くのは**一度も操作していない端末だけ**（PlaybackSettingsStore）。
#
# 1.15: チャンネル内検索 ＋ アプリ画面を 35 言語に。リリースノートも 35 言語
#   （7言語は App Store の whatsNew と同文、ほかは Claude 訳）。
# 1.16: 無料版に AdMob の広告（Pro は広告なし）＋購入まわりの修正。35 言語（Claude 訳）。
RELEASE_NOTES = {
    "ja-JP": "・無料版に広告が表示されるようになりました。動画一覧の画面下と、最初の画面の保存チャンネルの下の2か所だけで、再生画面には表示しません。\n・Pro（買い切り）には広告は表示されません。\n・購入まわりの安定性を改善しました。",
    "en-US": "• The free version now shows ads — only at the bottom of the video list and below your saved channel on the first screen. Ads never appear on the player screen.\n• Pro (one-time purchase) has no ads.\n• Improved reliability of purchases.",
    "zh-CN": "・免费版现在会显示广告，仅出现在视频列表底部和首页已保存频道的下方，播放画面不显示。\n・Pro（一次性买断）不显示广告。\n・提升了购买相关的稳定性。",
    "es-ES": "• La versión gratuita ahora muestra anuncios: solo en la parte inferior de la lista de vídeos y debajo de tu canal guardado en la primera pantalla. Nunca aparecen en la pantalla de reproducción.\n• Pro (compra única) no tiene anuncios.\n• Mejoras de fiabilidad en las compras.",
    "de-DE": "• Die kostenlose Version zeigt jetzt Werbung – nur unten in der Videoliste und unter deinem gespeicherten Kanal auf dem ersten Bildschirm. Auf dem Wiedergabebildschirm erscheint nie Werbung.\n• Pro (einmaliger Kauf) ist werbefrei.\n• Käufe funktionieren zuverlässiger.",
    "fr-FR": "• La version gratuite affiche désormais des publicités, uniquement en bas de la liste des vidéos et sous votre chaîne enregistrée sur le premier écran. Jamais sur l’écran de lecture.\n• Pro (achat unique) est sans publicité.\n• Fiabilité des achats améliorée.",
    "ko-KR": "・무료 버전에 광고가 표시됩니다. 동영상 목록 아래와 첫 화면의 저장한 채널 아래 두 곳뿐이며, 재생 화면에는 표시하지 않습니다.\n・Pro(1회 구매)에는 광고가 없습니다.\n・구매 관련 안정성을 개선했습니다.",
    "ar": "• تعرض النسخة المجانية الآن إعلانات، فقط أسفل قائمة الفيديوهات وأسفل قناتك المحفوظة في الشاشة الأولى. لا تظهر الإعلانات أبدًا في شاشة التشغيل.\n• Pro (شراء لمرة واحدة) بلا إعلانات.\n• تحسين موثوقية عمليات الشراء.",
    "bn-BD": "• বিনামূল্যের সংস্করণে এখন বিজ্ঞাপন দেখানো হয় — শুধু ভিডিও তালিকার নিচে এবং প্রথম স্ক্রিনে আপনার সংরক্ষিত চ্যানেলের নিচে। প্লেয়ার স্ক্রিনে কখনো বিজ্ঞাপন দেখানো হয় না।\n• Pro (একবারের কেনাকাটা)-তে কোনো বিজ্ঞাপন নেই।\n• কেনাকাটার নির্ভরযোগ্যতা বাড়ানো হয়েছে।",
    "cs-CZ": "• Bezplatná verze nyní zobrazuje reklamy – jen dole v seznamu videí a pod uloženým kanálem na první obrazovce. Na obrazovce přehrávání se reklamy nikdy nezobrazují.\n• Pro (jednorázový nákup) je bez reklam.\n• Spolehlivější nákupy.",
    "nl-NL": "• De gratis versie toont nu advertenties, alleen onderaan de videolijst en onder je opgeslagen kanaal op het eerste scherm. Nooit op het afspeelscherm.\n• Pro (eenmalige aankoop) heeft geen advertenties.\n• Aankopen werken betrouwbaarder.",
    "fil": "• May mga ad na ngayon ang libreng bersyon — sa ibaba lang ng listahan ng video at sa ilalim ng naka-save mong channel sa unang screen. Hindi kailanman lumalabas ang ad sa screen ng player.\n• Walang ad ang Pro (isang beses na pagbili).\n• Mas maaasahan na ang pagbili.",
    "el-GR": "• Η δωρεάν έκδοση εμφανίζει πλέον διαφημίσεις — μόνο στο κάτω μέρος της λίστας βίντεο και κάτω από το αποθηκευμένο κανάλι στην πρώτη οθόνη. Ποτέ στην οθόνη αναπαραγωγής.\n• Το Pro (εφάπαξ αγορά) δεν έχει διαφημίσεις.\n• Πιο αξιόπιστες αγορές.",
    "hi-IN": "• मुफ़्त संस्करण में अब विज्ञापन दिखते हैं — सिर्फ़ वीडियो सूची के नीचे और पहली स्क्रीन पर आपके सहेजे गए चैनल के नीचे। प्लेयर स्क्रीन पर विज्ञापन कभी नहीं दिखते।\n• Pro (एक बार की खरीदारी) में कोई विज्ञापन नहीं है।\n• खरीदारी की विश्वसनीयता में सुधार।",
    "hu-HU": "• Az ingyenes verzió mostantól hirdetéseket jelenít meg – csak a videólista alján és az első képernyőn a mentett csatorna alatt. A lejátszási képernyőn soha.\n• A Pro (egyszeri vásárlás) hirdetésmentes.\n• Megbízhatóbb vásárlás.",
    "id": "• Versi gratis kini menampilkan iklan — hanya di bagian bawah daftar video dan di bawah channel tersimpan pada layar pertama. Iklan tidak pernah muncul di layar pemutar.\n• Pro (pembelian sekali bayar) tanpa iklan.\n• Keandalan pembelian ditingkatkan.",
    "it-IT": "• La versione gratuita ora mostra pubblicità, solo in fondo all'elenco dei video e sotto il canale salvato nella prima schermata. Mai nella schermata di riproduzione.\n• Pro (acquisto una tantum) è senza pubblicità.\n• Acquisti più affidabili.",
    "kn-IN": "• ಉಚಿತ ಆವೃತ್ತಿಯಲ್ಲಿ ಈಗ ಜಾಹೀರಾತುಗಳು ಕಾಣಿಸುತ್ತವೆ — ವೀಡಿಯೊ ಪಟ್ಟಿಯ ಕೆಳಗೆ ಮತ್ತು ಮೊದಲ ಪರದೆಯಲ್ಲಿ ಉಳಿಸಿದ ಚಾನೆಲ್‌ನ ಕೆಳಗೆ ಮಾತ್ರ. ಪ್ಲೇಯರ್ ಪರದೆಯಲ್ಲಿ ಎಂದಿಗೂ ಜಾಹೀರಾತು ಇರುವುದಿಲ್ಲ.\n• Pro (ಒಂದು ಬಾರಿಯ ಖರೀದಿ) ಜಾಹೀರಾತುಗಳಿಲ್ಲ.\n• ಖರೀದಿಯ ವಿಶ್ವಾಸಾರ್ಹತೆ ಸುಧಾರಿಸಲಾಗಿದೆ.",
    "mr-IN": "• मोफत आवृत्तीत आता जाहिराती दिसतात — फक्त व्हिडिओ यादीच्या तळाशी आणि पहिल्या स्क्रीनवरील जतन केलेल्या चॅनेलखाली. प्लेयर स्क्रीनवर जाहिरात कधीही दिसत नाही.\n• Pro (एकदाच खरेदी) मध्ये जाहिराती नाहीत.\n• खरेदीची विश्वासार्हता सुधारली.",
    "pl-PL": "• Wersja bezpłatna wyświetla teraz reklamy – tylko na dole listy filmów i pod zapisanym kanałem na pierwszym ekranie. Nigdy na ekranie odtwarzania.\n• Pro (jednorazowy zakup) jest bez reklam.\n• Bardziej niezawodne zakupy.",
    "pt-BR": "• A versão gratuita agora exibe anúncios — só no fim da lista de vídeos e abaixo do canal salvo na primeira tela. Nunca na tela do player.\n• O Pro (compra única) não tem anúncios.\n• Compras mais confiáveis.",
    "pa": "• ਮੁਫ਼ਤ ਸੰਸਕਰਣ ਵਿੱਚ ਹੁਣ ਇਸ਼ਤਿਹਾਰ ਦਿਖਾਈ ਦਿੰਦੇ ਹਨ — ਸਿਰਫ਼ ਵੀਡੀਓ ਸੂਚੀ ਦੇ ਹੇਠਾਂ ਅਤੇ ਪਹਿਲੀ ਸਕ੍ਰੀਨ 'ਤੇ ਤੁਹਾਡੇ ਸੰਭਾਲੇ ਚੈਨਲ ਦੇ ਹੇਠਾਂ। ਪਲੇਅਰ ਸਕ੍ਰੀਨ 'ਤੇ ਕਦੇ ਨਹੀਂ।\n• Pro (ਇੱਕ ਵਾਰ ਦੀ ਖਰੀਦ) ਵਿੱਚ ਕੋਈ ਇਸ਼ਤਿਹਾਰ ਨਹੀਂ।\n• ਖਰੀਦ ਦੀ ਭਰੋਸੇਯੋਗਤਾ ਵਿੱਚ ਸੁਧਾਰ।",
    "ro": "• Versiunea gratuită afișează acum reclame — doar în partea de jos a listei de videoclipuri și sub canalul salvat de pe primul ecran. Niciodată pe ecranul de redare.\n• Pro (achiziție unică) este fără reclame.\n• Achiziții mai fiabile.",
    "ru-RU": "• В бесплатной версии теперь показывается реклама — только внизу списка видео и под сохранённым каналом на первом экране. На экране воспроизведения рекламы нет.\n• В Pro (разовая покупка) рекламы нет.\n• Покупки стали надёжнее.",
    "sv-SE": "• Gratisversionen visar nu annonser – bara längst ned i videolistan och under din sparade kanal på första skärmen. Aldrig på uppspelningsskärmen.\n• Pro (engångsköp) är reklamfritt.\n• Pålitligare köp.",
    "ta-IN": "• இலவசப் பதிப்பில் இப்போது விளம்பரங்கள் காட்டப்படும் — வீடியோ பட்டியலின் கீழும், முதல் திரையில் சேமித்த சேனலின் கீழும் மட்டும். பிளேயர் திரையில் ஒருபோதும் காட்டப்படாது.\n• Pro (ஒருமுறை வாங்குதல்) விளம்பரமில்லை.\n• வாங்குதலின் நம்பகத்தன்மை மேம்படுத்தப்பட்டது.",
    "te-IN": "• ఉచిత వెర్షన్‌లో ఇప్పుడు ప్రకటనలు కనిపిస్తాయి — వీడియో జాబితా కింద, మొదటి స్క్రీన్‌లో సేవ్ చేసిన ఛానెల్ కింద మాత్రమే. ప్లేయర్ స్క్రీన్‌లో ఎప్పుడూ కనిపించవు.\n• Pro (ఒకేసారి కొనుగోలు)లో ప్రకటనలు లేవు.\n• కొనుగోళ్ల విశ్వసనీయత మెరుగైంది.",
    "th": "• เวอร์ชันฟรีจะแสดงโฆษณาแล้ว เฉพาะด้านล่างรายการวิดีโอและใต้ช่องที่บันทึกไว้ในหน้าแรก ไม่แสดงในหน้าเล่นวิดีโอ\n• Pro (ซื้อครั้งเดียว) ไม่มีโฆษณา\n• ปรับปรุงความเสถียรของการซื้อ",
    "zh-TW": "• 免費版現在會顯示廣告，只出現在影片清單底部與首頁已儲存頻道的下方，播放畫面不會顯示。\n• Pro（一次購買）沒有廣告。\n• 提升了購買的穩定性。",
    "tr-TR": "• Ücretsiz sürümde artık reklam gösteriliyor; yalnızca video listesinin altında ve ilk ekranda kayıtlı kanalınızın altında. Oynatıcı ekranında asla gösterilmez.\n• Pro (tek seferlik satın alma) reklamsızdır.\n• Satın alma daha güvenilir.",
    "uk": "• У безкоштовній версії тепер показується реклама — лише внизу списку відео та під збереженим каналом на першому екрані. На екрані відтворення реклами немає.\n• У Pro (разова покупка) реклами немає.\n• Покупки стали надійнішими.",
    "ur": "• مفت ورژن میں اب اشتہارات دکھائے جاتے ہیں — صرف ویڈیو فہرست کے نیچے اور پہلی اسکرین پر آپ کے محفوظ چینل کے نیچے۔ پلیئر اسکرین پر کبھی نہیں۔\n• Pro (ایک بار کی خریداری) میں کوئی اشتہار نہیں۔\n• خریداری زیادہ قابلِ اعتماد ہو گئی۔",
    "vi": "• Phiên bản miễn phí giờ có hiển thị quảng cáo — chỉ ở cuối danh sách video và bên dưới kênh đã lưu ở màn hình đầu tiên. Không bao giờ xuất hiện ở màn hình phát.\n• Pro (mua một lần) không có quảng cáo.\n• Cải thiện độ ổn định khi mua.",
    "ms": "• Versi percuma kini memaparkan iklan — hanya di bahagian bawah senarai video dan di bawah saluran tersimpan pada skrin pertama. Iklan tidak pernah muncul pada skrin pemain.\n• Pro (pembelian sekali sahaja) tanpa iklan.\n• Kebolehpercayaan pembelian dipertingkat.",
    "zu": "• Inguqulo yamahhala manje ibonisa izikhangiso — ngaphansi kohlu lwamavidiyo kuphela nangaphansi kwesiteshi sakho esigciniwe esikrinini sokuqala. Azilokothi zivele esikrinini sokudlala.\n• I-Pro (ukuthenga kanye) ayinazo izikhangiso.\n• Ukuthenga sekuthembeke kakhulu.",
}


def promote(api, track: str, version_code: str, release_name: str, dry_run: bool) -> int:
    """アップロード済みのビルドを別トラックへ**下書き**として載せる。

    公開・審査提出はしない（事故防止のため、最後の一押しは人がコンソールで行う）。
    """
    edits = api.edits()
    edit_id = edits.insert(body={}, packageName=PACKAGE_NAME).execute()["id"]
    try:
        bundles = edits.bundles().list(
            packageName=PACKAGE_NAME, editId=edit_id).execute().get("bundles", [])
        available = sorted(str(b["versionCode"]) for b in bundles)
        if not available:
            raise SystemExit("アップロード済みのビルドがありません。")
        target = version_code or available[-1]
        if target not in available:
            raise SystemExit(f"versionCode {target} は見つかりません（あるのは {available}）。")

        if dry_run:
            print(f"  [dry-run] versionCode {target} を {track} に下書きとして載せる")
            return 0

        edits.tracks().update(
            packageName=PACKAGE_NAME, editId=edit_id, track=track,
            body={
                "track": track,
                "releases": [{
                    "name": release_name,
                    "versionCodes": [target],
                    "status": "draft",
                    "releaseNotes": [
                        {"language": locale, "text": text}
                        for locale, text in RELEASE_NOTES.items()
                    ],
                }],
            },
        ).execute()
        edits.commit(packageName=PACKAGE_NAME, editId=edit_id).execute()
        print(f"  {track} に versionCode {target} を**下書き**で載せました。")
        print("  Play Console で内容を確認し、「審査に送信」を押してください。")
        return 0
    except Exception:
        edits.delete(packageName=PACKAGE_NAME, editId=edit_id).execute()
        raise


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
    parser.add_argument("--mode", choices=["status", "listing", "details", "product", "promote", "aab"], default="status")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--aab", default="", help="--mode aab のときに使う AAB のパス")
    parser.add_argument("--track", default="internal", help="internal / alpha / beta / production")
    parser.add_argument("--release-name", default="1.0")
    parser.add_argument("--version-code", default="", help="--mode promote で載せるビルド（既定は最新）")
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
        if args.mode == "promote":
            return promote(api, args.track, args.version_code, args.release_name, args.dry_run)
        return upload_aab(api, Path(args.aab), args.track, args.release_name, args.dry_run)
    except HttpError as error:
        detail = error.content.decode("utf-8", errors="replace") if error.content else str(error)
        raise SystemExit(f"[Play API エラー] {error.resp.status}\n{detail}") from None


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
