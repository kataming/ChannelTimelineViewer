"""App Store の「このバージョンの新機能」を、今回の版の実態に合わせて7言語で書き換える。

⚠️ 書く内容は「**審査時点で実際に見える変更**」に限る。
Watch Queue V2（接続した人だけの自動同期）は、サーバー側の Feature Flag が OFF のあいだ
入口すら現れない。ストア公開より後に ON にする順序なので、審査時点では利用できない。
見えない機能を新機能として書くと事実と食い違うため、ここには書かない。

    python scripts/tmp_update_whatsnew.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "docs" / "AppStore" / "metadata.json"

WHATS_NEW = {
    "ja": (
        "・はじめて使うときに、チャンネルの追加方法を案内するようにしました。\n"
        "・再生画面の「自動再生」の表示を分かりやすくし、初期状態をオンにしました"
        "（すでにご自分で切り替えた方の設定はそのままです）。"
    ),
    "en": (
        "• New to the app? A short guide now shows you how to add a channel.\n"
        "• The Autoplay switch is clearer, and it now starts turned on "
        "(if you already chose a setting yourself, it is kept)."
    ),
    "zh-Hans": (
        "• 首次使用时，会引导你如何添加频道。\n"
        "• 播放页面的“自动播放”开关更清晰，并且默认开启（若你已自行设置过，将保持原样）。"
    ),
    "es": (
        "• ¿Es tu primera vez? Ahora una breve guía te muestra cómo añadir un canal.\n"
        "• El interruptor de reproducción automática es más claro y viene activado "
        "(si ya elegiste tu ajuste, se mantiene)."
    ),
    "de": (
        "• Neu hier? Eine kurze Anleitung zeigt jetzt, wie du einen Kanal hinzufügst.\n"
        "• Der Schalter für die automatische Wiedergabe ist klarer und ist jetzt standardmäßig an "
        "(deine eigene Einstellung bleibt erhalten)."
    ),
    "fr": (
        "• Première utilisation ? Un court guide vous montre comment ajouter une chaîne.\n"
        "• Le bouton de lecture automatique est plus clair et il est désormais activé par défaut "
        "(si vous aviez déjà choisi, votre réglage est conservé)."
    ),
    "ko": (
        "• 처음 사용할 때 채널을 추가하는 방법을 안내합니다.\n"
        "• 재생 화면의 ‘자동 재생’ 표시를 알기 쉽게 바꾸고, 기본값을 켬으로 했습니다"
        "(직접 설정하신 경우에는 그대로 유지됩니다)."
    ),
}


def main() -> int:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    locales = list(data["_locales"].keys())
    missing = [code for code in locales if code not in WHATS_NEW]
    if missing:
        raise SystemExit(f"言語が足りません: {missing}")

    limit = data.get("_limits", {}).get("whatsNew")
    for code, text in WHATS_NEW.items():
        if limit and len(text) > int(limit):
            raise SystemExit(f"{code} の文字数が上限 {limit} を超えています（{len(text)}）")

    before = data["whatsNew"]
    data["whatsNew"] = {code: WHATS_NEW[code] for code in locales}
    SOURCE.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print("whatsNew を書き換えました。")
    print(f"  前: {before.get('ja', '')[:60]}")
    print(f"  後: {data['whatsNew']['ja'][:60]}")
    print(f"  言語数: {len(data['whatsNew'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
