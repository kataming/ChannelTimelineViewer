"""Watch Queue V2 の文言（7言語）を Localization/strings.json に追加する。

既存の書式を壊さないよう、末尾の `}` の前に追記するだけにしてある（再実行しても増えない）。
追加後は次を実行して、生成物までそろえる:

    python scripts/build_localizations.py
    python scripts/build_android_strings.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Localization" / "strings.json"

# key -> (comment, ja, en, zh-Hans, es, de, fr, ko)
ENTRIES = {
    "watchQueue.title": (
        "Watch Queue: 画面のタイトル（機能名なので訳さない）",
        "Watch Queue", "Watch Queue", "Watch Queue", "Watch Queue", "Watch Queue", "Watch Queue", "Watch Queue",
    ),
    "watchQueue.entry.title": (
        "Watch Queue: 入口のボタン",
        "Watch Queue を開く", "Open Watch Queue", "打开 Watch Queue", "Abrir Watch Queue",
        "Watch Queue öffnen", "Ouvrir Watch Queue", "Watch Queue 열기",
    ),
    "watchQueue.entry.subtitle": (
        "Watch Queue: 入口の説明（未接続）",
        "パソコンで保存したキューを順番に観る",
        "Watch the queue you saved on your computer, in order.",
        "按顺序观看你在电脑上保存的队列。",
        "Reproduce en orden la cola que guardaste en tu ordenador.",
        "Sieh dir die auf dem Computer gespeicherte Liste der Reihe nach an.",
        "Regardez dans l’ordre la file enregistrée sur votre ordinateur.",
        "컴퓨터에서 저장한 대기열을 순서대로 시청합니다.",
    ),
    "watchQueue.entry.subtitle.connected": (
        "Watch Queue: 入口の説明（接続済み）",
        "接続済み", "Connected", "已连接", "Conectado", "Verbunden", "Connecté", "연결됨",
    ),
    "watchQueue.pair.title": (
        "Watch Queue: 接続の見出し",
        "接続する", "Connect", "连接", "Conectar", "Verbinden", "Connecter", "연결",
    ),
    "watchQueue.pair.detail": (
        "Watch Queue: 接続の説明",
        "パソコンの拡張機能に表示されたコードを入力してください。",
        "Enter the code shown in the extension on your computer.",
        "请输入电脑上扩展程序显示的代码。",
        "Introduce el código que aparece en la extensión de tu ordenador.",
        "Gib den Code ein, der in der Erweiterung auf deinem Computer angezeigt wird.",
        "Saisissez le code affiché dans l’extension sur votre ordinateur.",
        "컴퓨터의 확장 프로그램에 표시된 코드를 입력하세요.",
    ),
    "watchQueue.pair.field": (
        "Watch Queue: コード入力欄",
        "コード", "Code", "代码", "Código", "Code", "Code", "코드",
    ),
    "watchQueue.pair.button": (
        "Watch Queue: 接続ボタン",
        "接続する", "Connect", "连接", "Conectar", "Verbinden", "Connecter", "연결",
    ),
    "watchQueue.connected": (
        "Watch Queue: 接続済みの表示",
        "接続済みです", "Connected", "已连接", "Conectado", "Verbunden", "Connecté", "연결되었습니다",
    ),
    "watchQueue.refresh": (
        "Watch Queue: 再読み込み",
        "最新の状態にする", "Refresh", "刷新", "Actualizar", "Aktualisieren", "Actualiser", "새로고침",
    ),
    "watchQueue.disconnect": (
        "Watch Queue: 接続解除",
        "接続を解除", "Disconnect", "断开连接", "Desconectar", "Verbindung trennen", "Déconnecter", "연결 해제",
    ),
    "watchQueue.disconnect.confirm": (
        "Watch Queue: 接続解除の確認",
        "接続を解除しますか？", "Disconnect this device?", "要断开此设备的连接吗？",
        "¿Desconectar este dispositivo?", "Dieses Gerät trennen?", "Déconnecter cet appareil ?",
        "이 기기의 연결을 해제할까요?",
    ),
    "watchQueue.disconnect.detail": (
        "Watch Queue: 接続解除の説明（消えないものを明示する）",
        "解除されるのはこの端末だけです。保存したチャンネル・視聴の記録・購入は消えません。",
        "Only this device is disconnected. Your saved channels, watch records and purchase stay.",
        "只会断开此设备。已保存的频道、观看记录和购买不会被删除。",
        "Solo se desconecta este dispositivo. Tus canales guardados, tu historial y tu compra se mantienen.",
        "Nur dieses Gerät wird getrennt. Gespeicherte Kanäle, Verlauf und Kauf bleiben erhalten.",
        "Seul cet appareil est déconnecté. Vos chaînes enregistrées, votre historique et votre achat sont conservés.",
        "이 기기만 연결이 해제됩니다. 저장한 채널·시청 기록·구매는 그대로 유지됩니다.",
    ),
    "watchQueue.empty.title": (
        "Watch Queue: キューが無いとき",
        "キューがありません", "No queues yet", "还没有队列", "Aún no hay colas",
        "Noch keine Listen", "Aucune file pour l’instant", "아직 대기열이 없습니다",
    ),
    "watchQueue.empty.detail": (
        "Watch Queue: キューが無いときの説明",
        "パソコンの拡張機能で動画を保存すると、ここに出ます。",
        "Videos you save with the extension on your computer appear here.",
        "用电脑上的扩展程序保存视频后，会显示在这里。",
        "Los vídeos que guardes con la extensión en tu ordenador aparecerán aquí.",
        "Videos, die du mit der Erweiterung auf dem Computer speicherst, erscheinen hier.",
        "Les vidéos enregistrées avec l’extension sur votre ordinateur apparaissent ici.",
        "컴퓨터의 확장 프로그램으로 저장한 동영상이 여기에 표시됩니다.",
    ),
    "watchQueue.list.header": (
        "Watch Queue: 一覧の見出し",
        "キュー", "Queues", "队列", "Colas", "Listen", "Files d’attente", "대기열",
    ),
    "watchQueue.count.format": (
        "Watch Queue: 件数（%1$@=本数）",
        "%1$@本", "%1$@ videos", "%1$@ 个视频", "%1$@ vídeos", "%1$@ Videos", "%1$@ vidéos", "동영상 %1$@개",
    ),
    "watchQueue.untitled": (
        "Watch Queue: タイトルが取れなかった動画",
        "タイトルなし", "Untitled", "无标题", "Sin título", "Ohne Titel", "Sans titre", "제목 없음",
    ),
    "watchQueue.unplayable": (
        "Watch Queue: 再生できない動画",
        "この動画は再生できません", "This video can’t be played", "此视频无法播放",
        "Este vídeo no se puede reproducir", "Dieses Video kann nicht abgespielt werden",
        "Cette vidéo ne peut pas être lue", "이 동영상은 재생할 수 없습니다",
    ),
    "watchQueue.completed": (
        "Watch Queue: すべて再生し終えた",
        "キューの再生が完了しました", "Queue completed", "队列已播放完毕", "Cola completada",
        "Warteschlange abgeschlossen", "File d’attente terminée", "대기열 재생을 마쳤습니다",
    ),
    "watchQueue.completed.detail": (
        "Watch Queue: すべて再生し終えた説明",
        "このキューの動画をすべて再生しました。", "All videos in this queue have been played.",
        "此队列中的视频已全部播放。", "Se han reproducido todos los vídeos de esta cola.",
        "Alle Videos dieser Warteschlange wurden abgespielt.",
        "Toutes les vidéos de cette file d’attente ont été lues.",
        "이 대기열의 동영상을 모두 재생했습니다.",
    ),
    "watchQueue.restart": (
        "Watch Queue: 最初から再生",
        "最初から再生", "Play from the start", "从头播放", "Reproducir desde el principio",
        "Von vorn abspielen", "Lire depuis le début", "처음부터 재생",
    ),
    "watchQueue.playNext": (
        "Watch Queue: 次の動画を再生",
        "次の動画を再生", "Play next video", "播放下一个视频", "Reproducir el siguiente vídeo",
        "Nächstes Video abspielen", "Lire la vidéo suivante", "다음 동영상 재생",
    ),
    "watchQueue.autoplay": (
        "Watch Queue: 自動再生スイッチ（体験版と同じ設定）",
        "自動再生", "Autoplay", "自动播放", "Reproducción automática",
        "Automatische Wiedergabe", "Lecture automatique", "자동 재생",
    ),
    "watchQueue.error.network": (
        "Watch Queue: 通信できない",
        "接続できませんでした。通信状況を確かめて、もう一度お試しください。",
        "Couldn’t connect. Check your connection and try again.",
        "无法连接。请检查网络后重试。",
        "No se pudo conectar. Comprueba tu conexión e inténtalo de nuevo.",
        "Keine Verbindung. Prüfe deine Verbindung und versuche es erneut.",
        "Connexion impossible. Vérifiez votre connexion et réessayez.",
        "연결하지 못했습니다. 연결 상태를 확인한 뒤 다시 시도해 주세요.",
    ),
    "watchQueue.error.disabled": (
        "Watch Queue: サーバー側で止まっている",
        "この機能はまだ利用できません。", "This feature isn’t available yet.", "此功能尚不可用。",
        "Esta función aún no está disponible.", "Diese Funktion ist noch nicht verfügbar.",
        "Cette fonction n’est pas encore disponible.", "이 기능은 아직 사용할 수 없습니다.",
    ),
    "watchQueue.error.unauthorized": (
        "Watch Queue: 端末の接続が解除されている",
        "接続が解除されました。もう一度接続してください。",
        "This device was disconnected. Please connect again.",
        "此设备的连接已被解除。请重新连接。",
        "Este dispositivo se ha desconectado. Vuelve a conectarlo.",
        "Dieses Gerät wurde getrennt. Bitte verbinde es erneut.",
        "Cet appareil a été déconnecté. Veuillez le reconnecter.",
        "연결이 해제되었습니다. 다시 연결해 주세요.",
    ),
    "watchQueue.error.code": (
        "Watch Queue: コードが違う",
        "コードが違うようです。表示されているコードを確かめてください。",
        "That code doesn’t match. Check the code shown on your computer.",
        "代码不正确。请核对电脑上显示的代码。",
        "El código no coincide. Comprueba el código que aparece en tu ordenador.",
        "Der Code stimmt nicht. Prüfe den auf dem Computer angezeigten Code.",
        "Le code ne correspond pas. Vérifiez le code affiché sur votre ordinateur.",
        "코드가 일치하지 않습니다. 컴퓨터에 표시된 코드를 확인해 주세요.",
    ),
    "watchQueue.error.expired": (
        "Watch Queue: コードの期限切れ",
        "コードの有効期限が切れました。新しいコードを表示してください。",
        "The code expired. Show a new code on your computer.",
        "代码已过期。请在电脑上重新获取代码。",
        "El código ha caducado. Muestra un código nuevo en tu ordenador.",
        "Der Code ist abgelaufen. Lass dir einen neuen Code anzeigen.",
        "Le code a expiré. Affichez un nouveau code sur votre ordinateur.",
        "코드가 만료되었습니다. 컴퓨터에서 새 코드를 표시해 주세요.",
    ),
    "watchQueue.error.used": (
        "Watch Queue: 使用済みのコード",
        "そのコードは使用済みです。新しいコードを表示してください。",
        "That code was already used. Show a new code on your computer.",
        "该代码已被使用。请在电脑上重新获取代码。",
        "Ese código ya se ha usado. Muestra un código nuevo en tu ordenador.",
        "Dieser Code wurde bereits verwendet. Lass dir einen neuen Code anzeigen.",
        "Ce code a déjà été utilisé. Affichez un nouveau code sur votre ordinateur.",
        "이미 사용된 코드입니다. 컴퓨터에서 새 코드를 표시해 주세요.",
    ),
    "watchQueue.error.tooMany": (
        "Watch Queue: 試行しすぎ",
        "試行回数が多すぎます。しばらく待ってからお試しください。",
        "Too many attempts. Please wait a moment and try again.",
        "尝试次数过多。请稍后再试。",
        "Demasiados intentos. Espera un momento e inténtalo de nuevo.",
        "Zu viele Versuche. Bitte warte kurz und versuche es erneut.",
        "Trop de tentatives. Patientez un instant et réessayez.",
        "시도 횟수가 너무 많습니다. 잠시 후 다시 시도해 주세요.",
    ),
    "watchQueue.error.generic": (
        "Watch Queue: そのほかの失敗",
        "うまくいきませんでした。もう一度お試しください。",
        "That didn’t work. Please try again.",
        "操作未成功。请重试。",
        "No ha funcionado. Inténtalo de nuevo.",
        "Das hat nicht geklappt. Bitte versuche es erneut.",
        "Cela n’a pas fonctionné. Veuillez réessayer.",
        "실행하지 못했습니다. 다시 시도해 주세요.",
    ),
}

LANGS = ("ja", "en", "zh-Hans", "es", "de", "fr", "ko")


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    existing = json.loads(text)

    missing = {k: v for k, v in ENTRIES.items() if k not in existing}
    if not missing:
        print("strings.json: already up to date")
        return 0

    blocks = []
    for key, values in missing.items():
        comment, *translations = values
        lines = [f"  {json.dumps(key, ensure_ascii=False)}: {{"]
        lines.append(f"    \"comment\": {json.dumps(comment, ensure_ascii=False)},")
        for lang, value in zip(LANGS, translations):
            suffix = "," if lang != LANGS[-1] else ""
            lines.append(f"    {json.dumps(lang, ensure_ascii=False)}: {json.dumps(value, ensure_ascii=False)}{suffix}")
        lines.append("  }")
        blocks.append("\n".join(lines))

    trimmed = text.rstrip()
    if not trimmed.endswith("}"):
        raise SystemExit("strings.json の形が想定と違います")
    body = trimmed[: trimmed.rfind("}")].rstrip()
    updated = body + ",\n" + ",\n".join(blocks) + "\n}\n"

    json.loads(updated)  # 壊れた JSON を書かない
    SOURCE.write_text(updated, encoding="utf-8")
    print(f"strings.json: added {len(missing)} keys")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
