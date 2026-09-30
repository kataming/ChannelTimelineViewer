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
RELEASE_NOTES = {
    "ja-JP": "・チャンネル内検索：動画一覧の虫眼鏡から、タイトルで動画を絞り込めます。並び順や視聴済みの表示はそのままです。\n・アプリが35言語に対応しました。",
    "en-US": "• Search within a channel: tap the magnifying glass on the video list to narrow videos by title. Your sort order and watched marks stay as they are.\n• The app is now available in 35 languages.",
    "zh-CN": "・频道内搜索：在视频列表中点按放大镜，即可按标题筛选视频。排序和已观看标记保持不变。\n・应用现已支持 35 种语言。",
    "es-ES": "• Búsqueda dentro del canal: toca la lupa en la lista de vídeos para filtrarlos por título. El orden y las marcas de visto se mantienen.\n• La app ya está disponible en 35 idiomas.",
    "de-DE": "• Suche im Kanal: Tippe in der Videoliste auf die Lupe, um Videos nach Titel zu filtern. Sortierung und Gesehen-Markierungen bleiben erhalten.\n• Die App ist jetzt in 35 Sprachen verfügbar.",
    "fr-FR": "• Recherche dans la chaîne : touchez la loupe dans la liste des vidéos pour les filtrer par titre. L’ordre de tri et les marques « vu » sont conservés.\n• L’app est désormais disponible en 35 langues.",
    "ko-KR": "・채널 내 검색: 동영상 목록에서 돋보기를 눌러 제목으로 동영상을 좁혀 볼 수 있습니다. 정렬 순서와 시청 완료 표시는 그대로 유지됩니다.\n・앱이 35개 언어를 지원합니다.",
    "ar": "• البحث داخل القناة: انقر على العدسة المكبّرة في قائمة الفيديوهات لتضييق الفيديوهات حسب العنوان. يبقى ترتيب الفرز وعلامات المشاهدة كما هي.\n• أصبح التطبيق متاحًا الآن بـ 35 لغة.",
    "bn-BD": "• চ্যানেলের ভেতরে খোঁজা: ভিডিও তালিকায় ম্যাগনিফাইং গ্লাসে ট্যাপ করে শিরোনাম দিয়ে ভিডিও বাছাই করুন। আপনার সাজানোর ক্রম ও দেখা হয়েছে চিহ্ন যেমন আছে তেমনই থাকে।\n• অ্যাপটি এখন ৩৫টি ভাষায় উপলব্ধ।",
    "cs-CZ": "• Hledání v kanálu: klepnutím na lupu v seznamu videí zúžíte videa podle názvu. Řazení a značky zhlédnutí zůstanou beze změny.\n• Aplikace je nyní k dispozici v 35 jazycích.",
    "nl-NL": "• Zoeken binnen een kanaal: tik op het vergrootglas in de videolijst om video's op titel te filteren. Je sortering en bekeken-markeringen blijven zoals ze zijn.\n• De app is nu beschikbaar in 35 talen.",
    "fil": "• Paghahanap sa loob ng channel: i-tap ang magnifying glass sa listahan ng video para salain ang mga video ayon sa pamagat. Hindi nagbabago ang pagkakasunod-sunod at mga marka ng napanood.\n• Available na ang app sa 35 wika.",
    "el-GR": "• Αναζήτηση μέσα σε ένα κανάλι: πατήστε τον μεγεθυντικό φακό στη λίστα βίντεο για να φιλτράρετε τα βίντεο με βάση τον τίτλο. Η ταξινόμηση και οι σημάνσεις προβολής σας μένουν ως έχουν.\n• Η εφαρμογή είναι πλέον διαθέσιμη σε 35 γλώσσες.",
    "hi-IN": "• चैनल के अंदर खोज: वीडियो सूची पर आवर्धक लेंस (मैग्निफ़ाइंग ग्लास) पर टैप करके शीर्षक से वीडियो छाँटें। आपका क्रम और देखे गए के निशान जैसे हैं वैसे ही रहते हैं।\n• ऐप अब 35 भाषाओं में उपलब्ध है।",
    "hu-HU": "• Keresés a csatornán belül: koppints a nagyítóra a videólistán, és szűkítsd a videókat cím szerint. A rendezés és a megnézett jelölések változatlanok maradnak.\n• Az alkalmazás mostantól 35 nyelven érhető el.",
    "id": "• Cari di dalam channel: ketuk ikon kaca pembesar di daftar video untuk menyaring video berdasarkan judul. Urutan dan tanda sudah ditonton tetap seperti semula.\n• Aplikasi kini tersedia dalam 35 bahasa.",
    "it-IT": "• Ricerca all'interno di un canale: tocca la lente d'ingrandimento nell'elenco dei video per filtrarli per titolo. Ordinamento e segni di visione restano invariati.\n• L'app è ora disponibile in 35 lingue.",
    "kn-IN": "• ಚಾನೆಲ್‌ನೊಳಗೆ ಹುಡುಕಾಟ: ಶೀರ್ಷಿಕೆಯ ಮೂಲಕ ವೀಡಿಯೊಗಳನ್ನು ಸೀಮಿತಗೊಳಿಸಲು ವೀಡಿಯೊ ಪಟ್ಟಿಯಲ್ಲಿರುವ ಭೂತಗನ್ನಡಿ ಐಕಾನ್ ಟ್ಯಾಪ್ ಮಾಡಿ. ನಿಮ್ಮ ವಿಂಗಡಣೆಯ ಕ್ರಮ ಮತ್ತು ನೋಡಿದ ಗುರುತುಗಳು ಹಾಗೆಯೇ ಇರುತ್ತವೆ.\n• ಆ್ಯಪ್ ಈಗ 35 ಭಾಷೆಗಳಲ್ಲಿ ಲಭ್ಯವಿದೆ.",
    "mr-IN": "• चॅनेलमध्ये शोध: व्हिडिओ यादीवरील भिंगावर टॅप करून शीर्षकानुसार व्हिडिओ निवडा. तुमचा क्रम आणि पाहिलेल्यांच्या खुणा जशा आहेत तशाच राहतात.\n• ॲप आता 35 भाषांमध्ये उपलब्ध आहे.",
    "pl-PL": "• Wyszukiwanie w kanale: stuknij lupę na liście filmów, aby zawęzić filmy po tytule. Kolejność sortowania i oznaczenia obejrzanych pozostają bez zmian.\n• Aplikacja jest teraz dostępna w 35 językach.",
    "pt-BR": "• Busca dentro do canal: toque na lupa da lista de vídeos para filtrar os vídeos pelo título. A ordenação e as marcas de assistido continuam como estão.\n• O app agora está disponível em 35 idiomas.",
    "pa": "• ਚੈਨਲ ਦੇ ਅੰਦਰ ਖੋਜ: ਵੀਡੀਓ ਸੂਚੀ 'ਤੇ ਵੱਡਦਰਸ਼ੀ ਸ਼ੀਸ਼ੇ 'ਤੇ ਟੈਪ ਕਰਕੇ ਸਿਰਲੇਖ ਨਾਲ ਵੀਡੀਓ ਛਾਂਟੋ। ਤੁਹਾਡਾ ਕ੍ਰਮ ਅਤੇ ਦੇਖੇ ਗਏ ਦੇ ਨਿਸ਼ਾਨ ਜਿਵੇਂ ਹਨ ਉਵੇਂ ਹੀ ਰਹਿੰਦੇ ਹਨ।\n• ਐਪ ਹੁਣ 35 ਭਾਸ਼ਾਵਾਂ ਵਿੱਚ ਉਪਲਬਧ ਹੈ।",
    "ro": "• Căutare în canal: atingeți lupa din lista de videoclipuri pentru a restrânge videoclipurile după titlu. Ordinea de sortare și marcajele de vizionare rămân neschimbate.\n• Aplicația este acum disponibilă în 35 de limbi.",
    "ru-RU": "• Поиск внутри канала: нажмите на лупу в списке видео, чтобы отобрать видео по названию. Порядок сортировки и отметки о просмотре сохраняются.\n• Приложение теперь доступно на 35 языках.",
    "sv-SE": "• Sök inom en kanal: tryck på förstoringsglaset i videolistan för att filtrera videor efter titel. Din sortering och dina sedda-markeringar förblir som de är.\n• Appen finns nu på 35 språk.",
    "ta-IN": "• சேனலுக்குள் தேடல்: தலைப்பின்படி வீடியோக்களைச் சுருக்க, வீடியோ பட்டியலில் உள்ள உருப்பெருக்கியைத் தட்டவும். உங்கள் வரிசை முறையும் பார்த்த குறிகளும் அப்படியே இருக்கும்.\n• ஆப் இப்போது 35 மொழிகளில் கிடைக்கிறது.",
    "te-IN": "• ఛానెల్‌లో శోధన: శీర్షిక ద్వారా వీడియోలను తగ్గించడానికి వీడియో జాబితాలోని భూతద్దం గుర్తును నొక్కండి. మీ క్రమం, చూసిన గుర్తులు అలాగే ఉంటాయి.\n• యాప్ ఇప్పుడు 35 భాషల్లో అందుబాటులో ఉంది.",
    "th": "• ค้นหาภายในช่อง: แตะไอคอนแว่นขยายในรายการวิดีโอเพื่อกรองวิดีโอตามชื่อ ลำดับการเรียงและเครื่องหมายดูแล้วยังคงเหมือนเดิม\n• ตอนนี้แอปรองรับ 35 ภาษาแล้ว",
    "zh-TW": "• 頻道內搜尋：點一下影片清單上的放大鏡，即可依標題篩選影片。排序方式與已觀看標記都維持不變。\n• App 現已支援 35 種語言。",
    "tr-TR": "• Kanal içinde arama: videoları başlığa göre daraltmak için video listesindeki büyütece dokunun. Sıralama düzeniniz ve izlendi işaretleriniz olduğu gibi kalır.\n• Uygulama artık 35 dilde kullanılabilir.",
    "uk": "• Пошук у межах каналу: торкніться лупи в списку відео, щоб відібрати відео за назвою. Порядок сортування й позначки перегляду залишаються без змін.\n• Застосунок тепер доступний 35 мовами.",
    "ur": "• چینل کے اندر تلاش: ویڈیو فہرست میں میگنیفائنگ گلاس پر تھپتھپائیں اور عنوان سے ویڈیوز کو محدود کریں۔ آپ کی ترتیب اور دیکھی گئی کے نشان جوں کے توں رہتے ہیں۔\n• ایپ اب 35 زبانوں میں دستیاب ہے۔",
    "vi": "• Tìm kiếm trong kênh: nhấn vào biểu tượng kính lúp trên danh sách video để lọc video theo tiêu đề. Thứ tự sắp xếp và dấu đã xem vẫn giữ nguyên.\n• Ứng dụng hiện đã hỗ trợ 35 ngôn ngữ.",
    "ms": "• Carian dalam saluran: ketik ikon kanta pembesar pada senarai video untuk menapis video mengikut tajuk. Susunan dan tanda sudah ditonton kekal seperti biasa.\n• Apl kini tersedia dalam 35 bahasa.",
    "zu": "• Sesha ngaphakathi kwesiteshi: thepha ingilazi yokukhulisa ohlwini lwamavidiyo ukuze uhlunge amavidiyo ngesihloko. Ukuhlelwa kwakho namamaki okubukiwe kuhlala kunjalo.\n• Uhlelo lokusebenza manje selutholakala ngezilimi ezingu-35.",
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
