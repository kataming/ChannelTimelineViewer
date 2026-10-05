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
RELEASE_NOTES = {
    "ja-JP": "・人気の動画から選ぶだけで、そのチャンネルを開けるようになりました。\n・YouTube で［共有］→［コピー］して戻るだけで、チャンネルを追加できるようになりました。\n・動画一覧のメニューに「一番上へ」「一番下へ」を追加しました。\n・動画の読み込み中に進み具合（％）を表示するようにしました。",
    "en-US": "• Pick a popular video to open its channel right away.\n• Add a channel by tapping Share → Copy link in YouTube and coming back.\n• New “Go to top” and “Go to bottom” in the video list menu.\n• Loading now shows progress (%).",
    "zh-CN": "・只需从热门视频中选择，即可直接打开该频道。\n・在 YouTube 中点［分享］→［复制链接］后返回，即可添加频道。\n・视频列表菜单新增「回到顶部」「转到底部」。\n・加载视频时会显示进度（%）。",
    "es-ES": "• Elige un vídeo popular para abrir su canal al instante.\n• Añade un canal tocando Compartir → Copiar enlace en YouTube y volviendo.\n• Nuevas opciones «Ir al principio» e «Ir al final» en el menú de la lista.\n• La carga ahora muestra el progreso (%).",
    "de-DE": "• Wähle ein beliebtes Video, um seinen Kanal sofort zu öffnen.\n• Kanal hinzufügen: in YouTube Teilen → Link kopieren tippen und zurückkehren.\n• Neu im Listenmenü: „Zum Anfang“ und „Zum Ende“.\n• Beim Laden wird jetzt der Fortschritt (%) angezeigt.",
    "fr-FR": "• Choisissez une vidéo populaire pour ouvrir sa chaîne aussitôt.\n• Ajoutez une chaîne en touchant Partager → Copier le lien dans YouTube, puis en revenant.\n• Nouveaux « Aller en haut » et « Aller en bas » dans le menu de la liste.\n• Le chargement affiche maintenant la progression (%).",
    "ko-KR": "・인기 동영상을 고르기만 하면 그 채널이 바로 열립니다.\n・YouTube에서 [공유] → [링크 복사] 후 돌아오기만 하면 채널을 추가할 수 있습니다.\n・동영상 목록 메뉴에 「맨 위로」「맨 아래로」를 추가했습니다.\n・동영상을 불러오는 동안 진행률(%)을 표시합니다.",
    "ar": "• اختر فيديو رائجًا لفتح قناته مباشرة.\n• أضف قناة بالنقر على مشاركة ← نسخ الرابط في YouTube ثم العودة.\n• جديد في قائمة الفيديوهات: «الانتقال إلى الأعلى» و«الانتقال إلى الأسفل».\n• يظهر الآن تقدّم التحميل (%).",
    "bn-BD": "• জনপ্রিয় ভিডিও বেছে নিলেই সেই চ্যানেল সঙ্গে সঙ্গে খোলে।\n• YouTube-এ শেয়ার → লিঙ্ক কপি করে ফিরে এলেই চ্যানেল যোগ হয়।\n• ভিডিও তালিকার মেনুতে নতুন “একদম উপরে যান” ও “একদম নিচে যান”।\n• লোড হওয়ার সময় এখন অগ্রগতি (%) দেখায়।",
    "cs-CZ": "• Vyberte populární video a hned se otevře jeho kanál.\n• Kanál přidáte klepnutím na Sdílet → Kopírovat odkaz v YouTube a návratem zpět.\n• Nové položky „Na začátek“ a „Na konec“ v nabídce seznamu.\n• Načítání nyní ukazuje průběh (%).",
    "nl-NL": "• Kies een populaire video om het kanaal meteen te openen.\n• Voeg een kanaal toe via Delen → Link kopiëren in YouTube en kom terug.\n• Nieuw in het lijstmenu: ‘Naar boven’ en ‘Naar beneden’.\n• Het laden toont nu de voortgang (%).",
    "fil": "• Pumili ng sikat na video para agad mabuksan ang channel nito.\n• Magdagdag ng channel: i-tap ang Share → Kopyahin ang link sa YouTube at bumalik.\n• Bago sa menu ng listahan: “Pumunta sa itaas” at “Pumunta sa ibaba”.\n• Ipinapakita na ang progreso (%) habang naglo-load.",
    "el-GR": "• Επιλέξτε ένα δημοφιλές βίντεο για να ανοίξει αμέσως το κανάλι του.\n• Προσθέστε κανάλι πατώντας Κοινοποίηση → Αντιγραφή συνδέσμου στο YouTube και επιστρέφοντας.\n• Νέα στο μενού της λίστας: «Στην αρχή» και «Στο τέλος».\n• Η φόρτωση δείχνει πλέον την πρόοδο (%).",
    "hi-IN": "• लोकप्रिय वीडियो चुनते ही उसका चैनल तुरंत खुल जाता है।\n• YouTube में शेयर → लिंक कॉपी करके लौटते ही चैनल जुड़ जाता है।\n• वीडियो सूची के मेन्यू में नया “सबसे ऊपर जाएं” और “सबसे नीचे जाएं”।\n• लोड होते समय अब प्रगति (%) दिखती है।",
    "hu-HU": "• Válassz egy népszerű videót, és azonnal megnyílik a csatornája.\n• Csatorna hozzáadása: a YouTube-ban Megosztás → Link másolása, majd vissza.\n• Új a lista menüjében: „Ugrás a tetejére” és „Ugrás az aljára”.\n• Betöltéskor most látszik a haladás (%).",
    "id": "• Pilih video populer untuk langsung membuka salurannya.\n• Tambahkan saluran dengan mengetuk Bagikan → Salin link di YouTube lalu kembali.\n• Baru di menu daftar: “Ke paling atas” dan “Ke paling bawah”.\n• Saat memuat kini ditampilkan progresnya (%).",
    "it-IT": "• Scegli un video popolare per aprire subito il suo canale.\n• Aggiungi un canale toccando Condividi → Copia link in YouTube e tornando qui.\n• Novità nel menu dell'elenco: “Vai all'inizio” e “Vai alla fine”.\n• Il caricamento ora mostra l'avanzamento (%).",
    "kn-IN": "• ಜನಪ್ರಿಯ ವೀಡಿಯೊ ಆಯ್ಕೆಮಾಡಿದರೆ ಅದರ ಚಾನಲ್ ತಕ್ಷಣ ತೆರೆಯುತ್ತದೆ.\n• YouTube ನಲ್ಲಿ ಹಂಚಿಕೊಳ್ಳಿ → ಲಿಂಕ್ ನಕಲಿಸಿ ಮಾಡಿ ಹಿಂತಿರುಗಿದರೆ ಚಾನಲ್ ಸೇರುತ್ತದೆ.\n• ವೀಡಿಯೊ ಪಟ್ಟಿಯ ಮೆನುವಿನಲ್ಲಿ ಹೊಸ “ಮೇಲ್ಭಾಗಕ್ಕೆ ಹೋಗಿ” ಮತ್ತು “ಕೆಳಭಾಗಕ್ಕೆ ಹೋಗಿ”.\n• ಲೋಡ್ ಆಗುವಾಗ ಈಗ ಪ್ರಗತಿ (%) ತೋರಿಸುತ್ತದೆ.",
    "mr-IN": "• लोकप्रिय व्हिडिओ निवडताच त्याचे चॅनेल लगेच उघडते.\n• YouTube मध्ये शेअर → लिंक कॉपी करून परत आल्यावर चॅनेल जोडले जाते.\n• व्हिडिओ यादीच्या मेनूमध्ये नवीन “सर्वात वर जा” आणि “सर्वात खाली जा”.\n• लोड होताना आता प्रगती (%) दिसते.",
    "pl-PL": "• Wybierz popularny film, aby od razu otworzyć jego kanał.\n• Dodaj kanał: w YouTube dotknij Udostępnij → Kopiuj link i wróć.\n• Nowe w menu listy: „Przejdź na górę” i „Przejdź na dół”.\n• Podczas wczytywania widać teraz postęp (%).",
    "pt-BR": "• Escolha um vídeo popular para abrir o canal na hora.\n• Adicione um canal tocando em Compartilhar → Copiar link no YouTube e voltando.\n• Novo no menu da lista: “Ir para o topo” e “Ir para o final”.\n• O carregamento agora mostra o progresso (%).",
    "pa": "• ਪ੍ਰਸਿੱਧ ਵੀਡੀਓ ਚੁਣਦੇ ਹੀ ਉਸਦਾ ਚੈਨਲ ਤੁਰੰਤ ਖੁੱਲ੍ਹਦਾ ਹੈ।\n• YouTube ਵਿੱਚ ਸਾਂਝਾ ਕਰੋ → ਲਿੰਕ ਕਾਪੀ ਕਰਕੇ ਵਾਪਸ ਆਉਂਦੇ ਹੀ ਚੈਨਲ ਜੁੜ ਜਾਂਦਾ ਹੈ।\n• ਵੀਡੀਓ ਸੂਚੀ ਦੇ ਮੀਨੂ ਵਿੱਚ ਨਵਾਂ “ਸਭ ਤੋਂ ਉੱਪਰ ਜਾਓ” ਅਤੇ “ਸਭ ਤੋਂ ਹੇਠਾਂ ਜਾਓ”।\n• ਲੋਡ ਹੋਣ ਵੇਲੇ ਹੁਣ ਤਰੱਕੀ (%) ਦਿਖਦੀ ਹੈ।",
    "ro": "• Alegeți un videoclip popular ca să deschideți imediat canalul lui.\n• Adăugați un canal atingând Distribuiți → Copiați linkul în YouTube și revenind.\n• Nou în meniul listei: „Mergi sus” și „Mergi jos”.\n• Încărcarea afișează acum progresul (%).",
    "ru-RU": "• Выберите популярное видео — сразу откроется его канал.\n• Канал можно добавить: в YouTube нажмите «Поделиться» → «Копировать ссылку» и вернитесь.\n• В меню списка появились «В начало» и «В конец».\n• При загрузке теперь виден прогресс (%).",
    "sv-SE": "• Välj en populär video för att öppna kanalen direkt.\n• Lägg till en kanal genom att trycka på Dela → Kopiera länk i YouTube och komma tillbaka.\n• Nytt i listmenyn: ”Till toppen” och ”Till botten”.\n• Laddningen visar nu förloppet (%).",
    "ta-IN": "• பிரபலமான வீடியோவைத் தேர்ந்தெடுத்தால் அதன் சேனல் உடனே திறக்கும்.\n• YouTube-இல் பகிர் → இணைப்பை நகலெடு செய்து திரும்பினால் சேனல் சேர்க்கப்படும்.\n• வீடியோ பட்டியல் மெனுவில் புதிய “மேலே செல்” மற்றும் “கீழே செல்”.\n• ஏற்றும்போது இப்போது முன்னேற்றம் (%) காட்டப்படும்.",
    "te-IN": "• జనాదరణ పొందిన వీడియోను ఎంచుకుంటే దాని ఛానెల్ వెంటనే తెరుచుకుంటుంది.\n• YouTube లో షేర్ → లింక్‌ను కాపీ చేసి తిరిగి వస్తే ఛానెల్ జోడించబడుతుంది.\n• వీడియో జాబితా మెనూలో కొత్తగా “పైకి వెళ్లండి”, “కిందికి వెళ్లండి”.\n• లోడ్ అవుతున్నప్పుడు ఇప్పుడు పురోగతి (%) కనిపిస్తుంది.",
    "th": "• เลือกวิดีโอยอดนิยมเพื่อเปิดช่องนั้นได้ทันที\n• เพิ่มช่องได้ด้วยการแตะ แชร์ → คัดลอกลิงก์ ใน YouTube แล้วกลับมา\n• เมนูรายการวิดีโอมี “ไปบนสุด” และ “ไปล่างสุด” แล้ว\n• ขณะโหลดจะแสดงความคืบหน้า (%)",
    "zh-TW": "• 只要從熱門影片中選擇，就能直接開啟該頻道。\n• 在 YouTube 點［分享］→［複製連結］後返回，即可新增頻道。\n• 影片清單選單新增「回到頂端」「跳到底部」。\n• 載入影片時會顯示進度（%）。",
    "tr-TR": "• Popüler bir video seçin, kanalı hemen açılsın.\n• YouTube'da Paylaş → Bağlantıyı kopyala'ya dokunup geri dönerek kanal ekleyin.\n• Liste menüsünde yeni: “En üste git” ve “En alta git”.\n• Yükleme sırasında artık ilerleme (%) gösteriliyor.",
    "uk": "• Виберіть популярне відео — одразу відкриється його канал.\n• Канал можна додати: у YouTube торкніться «Поширити» → «Копіювати посилання» і поверніться.\n• У меню списку з'явилися «На початок» і «У кінець».\n• Під час завантаження тепер видно прогрес (%).",
    "ur": "• مقبول ویڈیو منتخب کریں، اس کا چینل فوراً کھل جائے گا۔\n• YouTube میں شیئر ← لنک کاپی کر کے واپس آئیں تو چینل شامل ہو جاتا ہے۔\n• ویڈیو فہرست کے مینو میں نیا “سب سے اوپر جائیں” اور “سب سے نیچے جائیں”۔\n• لوڈ ہوتے وقت اب پیش رفت (%) دکھائی دیتی ہے۔",
    "vi": "• Chọn một video phổ biến để mở ngay kênh của video đó.\n• Thêm kênh bằng cách nhấn Chia sẻ → Sao chép đường liên kết trong YouTube rồi quay lại.\n• Menu danh sách có thêm “Lên đầu” và “Xuống cuối”.\n• Khi tải nay hiển thị tiến độ (%).",
    "ms": "• Pilih video popular untuk terus membuka salurannya.\n• Tambah saluran dengan mengetik Kongsi → Salin pautan dalam YouTube dan kembali.\n• Baharu dalam menu senarai: “Ke paling atas” dan “Ke paling bawah”.\n• Pemuatan kini menunjukkan kemajuan (%).",
    "zu": "• Khetha ividiyo edumile ukuze uvule isiteshi sayo ngokushesha.\n• Engeza isiteshi ngokuthepha okuthi Yabelana → Kopisha isixhumanisi ku-YouTube bese ubuyela.\n• Okusha kumenyu yohlu: “Iya phezulu” no-“Iya phansi”.\n• Ukulayisha manje kubonisa inqubekela phambili (%).",
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
