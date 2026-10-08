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
# 1.18: 人気動画から選ぶ／YouTube の共有→コピーで追加／一覧の一番上へ・一番下へ／読み込みの％表示。35 言語（Claude 訳）。
# 1.20: 人気動画・コピーした動画をすぐ再生（一覧は再生中に読み込む）＋再生画面の表示の整理。35 言語（Claude 訳）。
RELEASE_NOTES = {
    "ja-JP": "・人気動画や YouTube でコピーした動画を選ぶと、すぐ再生が始まるようになりました（チャンネルの一覧は再生中に読み込みます）。\n・再生画面の表示を見やすくしました。",
    "en-US": "• Videos you pick from popular videos or copy in YouTube now start playing right away (the channel list loads while you watch).\n• The player screen is easier to read.",
    "zh-CN": "・从热门视频中选择或在 YouTube 中复制的视频现在会立即开始播放（频道列表在播放时加载）。\n・播放画面更易阅读了。",
    "es-ES": "• Los vídeos que eliges entre los populares o copias en YouTube ahora se reproducen al instante (la lista del canal se carga mientras ves).\n• La pantalla de reproducción es más fácil de leer.",
    "de-DE": "• Videos, die du aus beliebten Videos auswählst oder in YouTube kopierst, starten jetzt sofort (die Kanalliste lädt während der Wiedergabe).\n• Der Wiedergabebildschirm ist übersichtlicher.",
    "fr-FR": "• Les vidéos choisies parmi les vidéos populaires ou copiées dans YouTube se lancent désormais tout de suite (la liste de la chaîne se charge pendant la lecture).\n• L’écran de lecture est plus lisible.",
    "ko-KR": "・인기 동영상에서 고르거나 YouTube에서 복사한 동영상이 바로 재생됩니다(채널 목록은 재생 중에 불러옵니다).\n・재생 화면을 보기 쉽게 바꿨습니다.",
    "ar": "• تبدأ الآن الفيديوهات التي تختارها من الفيديوهات الرائجة أو تنسخها في YouTube بالتشغيل فورًا (تُحمَّل قائمة القناة أثناء المشاهدة).\n• أصبحت شاشة التشغيل أسهل في القراءة.",
    "bn-BD": "• জনপ্রিয় ভিডিও থেকে বাছাই করা বা YouTube-এ কপি করা ভিডিও এখন সঙ্গে সঙ্গে চালু হয় (দেখার সময় চ্যানেলের তালিকা লোড হয়)।\n• প্লেয়ার স্ক্রিন পড়া আরও সহজ হয়েছে।",
    "cs-CZ": "• Videa vybraná z populárních nebo zkopírovaná v YouTube se teď hned spustí (seznam kanálu se načte během přehrávání).\n• Obrazovka přehrávače je přehlednější.",
    "nl-NL": "• Video’s die je kiest uit populaire video’s of kopieert in YouTube, starten nu meteen (de kanaallijst laadt tijdens het kijken).\n• Het afspeelscherm is overzichtelijker.",
    "fil": "• Agad nang nagpe-play ang mga video na pinili mo sa mga sikat na video o kinopya sa YouTube (nilo-load ang listahan ng channel habang nanonood).\n• Mas madaling basahin ang player screen.",
    "el-GR": "• Τα βίντεο που επιλέγετε από τα δημοφιλή ή αντιγράφετε στο YouTube ξεκινούν πλέον αμέσως (η λίστα του καναλιού φορτώνει όσο παρακολουθείτε).\n• Η οθόνη αναπαραγωγής διαβάζεται πιο εύκολα.",
    "hi-IN": "• लोकप्रिय वीडियो से चुने गए या YouTube में कॉपी किए गए वीडियो अब तुरंत चलने लगते हैं (देखते समय चैनल की सूची लोड होती है)।\n• प्लेयर स्क्रीन अब पढ़ने में आसान है।",
    "hu-HU": "• A népszerű videók közül választott vagy a YouTube-ban másolt videók most azonnal elindulnak (a csatorna listája lejátszás közben töltődik be).\n• A lejátszó képernyő áttekinthetőbb lett.",
    "id": "• Video yang Anda pilih dari video populer atau salin di YouTube kini langsung diputar (daftar channel dimuat selama menonton).\n• Layar pemutar kini lebih mudah dibaca.",
    "it-IT": "• I video scelti tra quelli popolari o copiati in YouTube ora partono subito (l’elenco del canale si carica durante la visione).\n• La schermata di riproduzione è più leggibile.",
    "kn-IN": "• ಜನಪ್ರಿಯ ವೀಡಿಯೊಗಳಿಂದ ಆಯ್ಕೆ ಮಾಡಿದ ಅಥವಾ YouTube ನಲ್ಲಿ ನಕಲಿಸಿದ ವೀಡಿಯೊಗಳು ಈಗ ತಕ್ಷಣ ಪ್ಲೇ ಆಗುತ್ತವೆ (ನೋಡುತ್ತಿರುವಾಗ ಚಾನೆಲ್ ಪಟ್ಟಿ ಲೋಡ್ ಆಗುತ್ತದೆ).\n• ಪ್ಲೇಯರ್ ಪರದೆ ಓದಲು ಇನ್ನಷ್ಟು ಸುಲಭ.",
    "mr-IN": "• लोकप्रिय व्हिडिओमधून निवडलेले किंवा YouTube मध्ये कॉपी केलेले व्हिडिओ आता लगेच सुरू होतात (पाहताना चॅनेलची यादी लोड होते).\n• प्लेअर स्क्रीन वाचायला अधिक सोपी झाली आहे.",
    "pl-PL": "• Filmy wybrane z popularnych lub skopiowane w YouTube odtwarzają się teraz od razu (lista kanału wczytuje się w trakcie oglądania).\n• Ekran odtwarzania jest bardziej czytelny.",
    "pt-BR": "• Vídeos escolhidos entre os populares ou copiados no YouTube agora começam na hora (a lista do canal carrega enquanto você assiste).\n• A tela do player ficou mais fácil de ler.",
    "pa": "• ਪ੍ਰਸਿੱਧ ਵੀਡੀਓ ਵਿੱਚੋਂ ਚੁਣੇ ਜਾਂ YouTube ਵਿੱਚ ਕਾਪੀ ਕੀਤੇ ਵੀਡੀਓ ਹੁਣ ਤੁਰੰਤ ਚੱਲਦੇ ਹਨ (ਦੇਖਦੇ ਸਮੇਂ ਚੈਨਲ ਦੀ ਸੂਚੀ ਲੋਡ ਹੁੰਦੀ ਹੈ)।\n• ਪਲੇਅਰ ਸਕ੍ਰੀਨ ਪੜ੍ਹਨ ਵਿੱਚ ਹੋਰ ਆਸਾਨ ਹੈ।",
    "ro": "• Videoclipurile alese dintre cele populare sau copiate în YouTube pornesc acum imediat (lista canalului se încarcă în timp ce urmărești).\n• Ecranul de redare este mai ușor de citit.",
    "ru-RU": "• Видео, выбранные среди популярных или скопированные в YouTube, теперь запускаются сразу (список канала загружается во время просмотра).\n• Экран воспроизведения стал понятнее.",
    "sv-SE": "• Videor du väljer bland populära videor eller kopierar i YouTube startar nu direkt (kanallistan laddas medan du tittar).\n• Uppspelningsskärmen är lättare att läsa.",
    "ta-IN": "• பிரபல வீடியோக்களில் இருந்து தேர்ந்தெடுத்த அல்லது YouTube இல் நகலெடுத்த வீடியோக்கள் இப்போது உடனே இயங்கும் (பார்க்கும்போதே சேனல் பட்டியல் ஏற்றப்படும்).\n• பிளேயர் திரை படிக்க எளிதாக உள்ளது.",
    "te-IN": "• జనాదరణ పొందిన వీడియోల నుండి ఎంచుకున్న లేదా YouTubeలో కాపీ చేసిన వీడియోలు ఇప్పుడు వెంటనే ప్లే అవుతాయి (చూస్తున్నప్పుడే ఛానెల్ జాబితా లోడ్ అవుతుంది).\n• ప్లేయర్ స్క్రీన్ చదవడానికి మరింత సులభం.",
    "th": "• วิดีโอที่เลือกจากวิดีโอยอดนิยมหรือคัดลอกใน YouTube จะเริ่มเล่นทันที (รายการของช่องจะโหลดระหว่างที่ดู)\n• หน้าจอเล่นวิดีโออ่านง่ายขึ้น",
    "zh-TW": "• 從熱門影片選擇或在 YouTube 複製的影片，現在會立即開始播放（頻道清單會在播放時載入）。\n• 播放畫面更容易閱讀了。",
    "tr-TR": "• Popüler videolardan seçtiğiniz veya YouTube’da kopyaladığınız videolar artık hemen oynatılıyor (kanal listesi izlerken yükleniyor).\n• Oynatıcı ekranı daha kolay okunuyor.",
    "uk": "• Відео, вибрані серед популярних або скопійовані в YouTube, тепер запускаються одразу (список каналу завантажується під час перегляду).\n• Екран відтворення став зрозумілішим.",
    "ur": "• مقبول ویڈیوز میں سے منتخب کی گئی یا YouTube میں کاپی کی گئی ویڈیوز اب فوراً چلنے لگتی ہیں (دیکھنے کے دوران چینل کی فہرست لوڈ ہوتی ہے)۔\n• پلیئر اسکرین اب پڑھنے میں آسان ہے۔",
    "vi": "• Video bạn chọn từ video phổ biến hoặc sao chép trong YouTube giờ phát ngay (danh sách kênh được tải trong lúc xem).\n• Màn hình phát dễ đọc hơn.",
    "ms": "• Video yang anda pilih daripada video popular atau salin dalam YouTube kini dimainkan serta-merta (senarai saluran dimuatkan semasa menonton).\n• Skrin pemain lebih mudah dibaca.",
    "zu": "• Amavidiyo owakhetha kumavidiyo adumile noma owakopisha ku-YouTube manje aqala ukudlala ngokushesha (uhlu lwesiteshi lulayishwa ngesikhathi ubuka).\n• Isikrini sokudlala sesilula ukufunda.",
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
