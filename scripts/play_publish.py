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
# 1.17: 視聴回数の表示（一覧・再生画面）＋並び順「人気順」。35 言語（Claude 訳）。
RELEASE_NOTES = {
    "ja-JP": "・一覧と再生画面に、公開日と並べて視聴回数を表示するようにしました。\n・並び順に「人気順」（視聴回数の多い順）を追加しました。",
    "en-US": "• View counts now appear next to the publish date in the list and on the player screen.\n• New sort option: Most popular (most viewed first).",
    "zh-CN": "・列表和播放画面会在发布日期旁显示观看次数。\n・排序新增「最受欢迎」（按观看次数从多到少）。",
    "es-ES": "• Ahora se muestran las visualizaciones junto a la fecha de publicación en la lista y en la pantalla de reproducción.\n• Nuevo orden: Más populares (las más vistas primero).",
    "de-DE": "• Aufrufe werden jetzt neben dem Veröffentlichungsdatum in der Liste und auf dem Wiedergabebildschirm angezeigt.\n• Neue Sortierung: Beliebteste (meiste Aufrufe zuerst).",
    "fr-FR": "• Le nombre de vues s’affiche désormais à côté de la date de publication, dans la liste et sur l’écran de lecture.\n• Nouveau tri : Les plus populaires (les plus vues d’abord).",
    "ko-KR": "・목록과 재생 화면에서 게시일 옆에 조회수를 표시합니다.\n・정렬에 「인기순」(조회수가 많은 순)을 추가했습니다.",
    "ar": "• يظهر عدد المشاهدات الآن بجانب تاريخ النشر في القائمة وفي شاشة التشغيل.\n• ترتيب جديد: الأكثر شعبية (الأكثر مشاهدة أولًا).",
    "bn-BD": "• তালিকা ও প্লেয়ার স্ক্রিনে প্রকাশের তারিখের পাশে এখন ভিউ সংখ্যা দেখা যায়।\n• নতুন সাজানো: সবচেয়ে জনপ্রিয় (সবচেয়ে বেশি দেখা আগে)।",
    "cs-CZ": "• Počet zhlédnutí se nyní zobrazuje vedle data zveřejnění v seznamu i na obrazovce přehrávání.\n• Nové řazení: Nejoblíbenější (nejsledovanější první).",
    "nl-NL": "• Weergaven staan nu naast de publicatiedatum in de lijst en op het afspeelscherm.\n• Nieuwe sortering: Populairste (meest bekeken eerst).",
    "fil": "• Makikita na ang bilang ng panonood sa tabi ng petsa ng pag-publish sa listahan at sa screen ng player.\n• Bagong pagkakasunod-sunod: Pinakasikat (pinakamaraming nanood muna).",
    "el-GR": "• Οι προβολές εμφανίζονται πλέον δίπλα στην ημερομηνία δημοσίευσης στη λίστα και στην οθόνη αναπαραγωγής.\n• Νέα ταξινόμηση: Δημοφιλέστερα (περισσότερες προβολές πρώτα).",
    "hi-IN": "• सूची और प्लेयर स्क्रीन पर अब प्रकाशन तिथि के साथ व्यू संख्या दिखती है।\n• नया क्रम: सबसे लोकप्रिय (सबसे ज़्यादा देखे गए पहले)।",
    "hu-HU": "• A megtekintések száma mostantól a közzététel dátuma mellett látható a listában és a lejátszási képernyőn.\n• Új rendezés: Legnépszerűbb (a legtöbbet nézett elöl).",
    "id": "• Jumlah tayangan kini muncul di samping tanggal publikasi di daftar dan layar pemutar.\n• Urutan baru: Terpopuler (paling banyak ditonton dulu).",
    "it-IT": "• Le visualizzazioni ora compaiono accanto alla data di pubblicazione nell'elenco e nella schermata di riproduzione.\n• Nuovo ordinamento: Più popolari (i più visti prima).",
    "kn-IN": "• ಪಟ್ಟಿಯಲ್ಲಿ ಮತ್ತು ಪ್ಲೇಯರ್ ಪರದೆಯಲ್ಲಿ ಪ್ರಕಟಣೆಯ ದಿನಾಂಕದ ಪಕ್ಕದಲ್ಲಿ ಈಗ ವೀಕ್ಷಣೆಗಳ ಸಂಖ್ಯೆ ಕಾಣಿಸುತ್ತದೆ.\n• ಹೊಸ ವಿಂಗಡಣೆ: ಅತ್ಯಂತ ಜನಪ್ರಿಯ (ಹೆಚ್ಚು ವೀಕ್ಷಿಸಿದವು ಮೊದಲು).",
    "mr-IN": "• यादीत आणि प्लेयर स्क्रीनवर आता प्रकाशन तारखेशेजारी व्ह्यू संख्या दिसते.\n• नवीन क्रम: सर्वाधिक लोकप्रिय (सर्वाधिक पाहिलेले आधी).",
    "pl-PL": "• Liczba wyświetleń jest teraz widoczna obok daty publikacji na liście i na ekranie odtwarzania.\n• Nowe sortowanie: Najpopularniejsze (najczęściej oglądane najpierw).",
    "pt-BR": "• As visualizações agora aparecem ao lado da data de publicação na lista e na tela do player.\n• Nova ordenação: Mais populares (mais vistos primeiro).",
    "pa": "• ਸੂਚੀ ਅਤੇ ਪਲੇਅਰ ਸਕ੍ਰੀਨ 'ਤੇ ਹੁਣ ਪ੍ਰਕਾਸ਼ਨ ਮਿਤੀ ਦੇ ਨਾਲ ਵਿਊਜ਼ ਦੀ ਗਿਣਤੀ ਦਿਖਦੀ ਹੈ।\n• ਨਵਾਂ ਕ੍ਰਮ: ਸਭ ਤੋਂ ਪ੍ਰਸਿੱਧ (ਸਭ ਤੋਂ ਵੱਧ ਦੇਖੇ ਗਏ ਪਹਿਲਾਂ)।",
    "ro": "• Numărul de vizionări apare acum lângă data publicării, în listă și pe ecranul de redare.\n• Sortare nouă: Cele mai populare (cele mai vizionate primele).",
    "ru-RU": "• Число просмотров теперь показано рядом с датой публикации в списке и на экране воспроизведения.\n• Новая сортировка: Популярные (сначала самые просматриваемые).",
    "sv-SE": "• Antal visningar visas nu bredvid publiceringsdatumet i listan och på uppspelningsskärmen.\n• Ny sortering: Populäraste (mest visade först).",
    "ta-IN": "• பட்டியலிலும் பிளேயர் திரையிலும் வெளியீட்டுத் தேதிக்கு அருகில் இப்போது பார்வைகளின் எண்ணிக்கை தெரியும்.\n• புதிய வரிசை: மிகவும் பிரபலமானவை (அதிகம் பார்க்கப்பட்டவை முதலில்).",
    "te-IN": "• జాబితాలో మరియు ప్లేయర్ స్క్రీన్‌లో ప్రచురణ తేదీ పక్కన ఇప్పుడు వీక్షణల సంఖ్య కనిపిస్తుంది.\n• కొత్త క్రమం: అత్యంత జనాదరణ పొందినవి (ఎక్కువగా చూసినవి ముందు).",
    "th": "• รายการและหน้าเล่นวิดีโอแสดงยอดดูข้างวันที่เผยแพร่แล้ว\n• การเรียงแบบใหม่: ยอดนิยม (ยอดดูมากสุดก่อน)",
    "zh-TW": "• 清單與播放畫面會在發布日期旁顯示觀看次數。\n• 排序新增「最熱門」（觀看次數多的優先）。",
    "tr-TR": "• Görüntülenme sayısı artık listede ve oynatıcı ekranında yayın tarihinin yanında görünüyor.\n• Yeni sıralama: En popüler (en çok izlenen önce).",
    "uk": "• Кількість переглядів тепер показано поруч із датою публікації у списку та на екрані відтворення.\n• Нове сортування: Найпопулярніші (спершу найпереглядуваніші).",
    "ur": "• فہرست اور پلیئر اسکرین پر اب اشاعت کی تاریخ کے ساتھ ویوز کی تعداد نظر آتی ہے۔\n• نئی ترتیب: سب سے مقبول (سب سے زیادہ دیکھی گئی پہلے)۔",
    "vi": "• Lượt xem nay hiển thị cạnh ngày đăng trong danh sách và trên màn hình phát.\n• Thứ tự mới: Phổ biến nhất (xem nhiều nhất trước).",
    "ms": "• Jumlah tontonan kini dipaparkan di sebelah tarikh terbit dalam senarai dan pada skrin pemain.\n• Susunan baharu: Paling popular (paling banyak ditonton dahulu).",
    "zu": "• Inani lokubukwa manje livela eduze kosuku lokushicilelwa ohlwini nasesikrinini sokudlala.\n• Ukuhlela okusha: Okudume kakhulu (okubukwe kakhulu kuqala).",
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
