import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// クリップボードを読むための最小インターフェース（テスト用に差し替えられるようにする）。
protocol PasteboardProviding {
    /// URL らしき内容が入っているか。**中身は読まない**（iOS のペースト確認を出さない）。
    func containsProbableURL() async -> Bool
    /// 実際の文字列を読む（ユーザー操作の直後にだけ呼ぶ）。
    func readString() -> String?
}

/// 共有シートから受け取った URL を、メインアプリ側で拾い上げるための検出器。
///
/// iOS の仕様上、共有シート拡張から**アプリを直接開くことはできない**（Today / iMessage 拡張のみ可）。
/// そのため拡張は URL をクリップボードに置き、アプリを開いたときにここで拾って
/// 「共有されたURLを開く」ボタンをワンタップで出す。
///
/// - 中身の読み取りはユーザーがボタンを押したときだけ行う（勝手に読まない）。
/// - 表示判定には `detectPatterns` を使うため、ペーストの確認ダイアログは出ない。
@MainActor
final class ClipboardLinkDetector: ObservableObject {
    /// クリップボードに URL らしきものがあるか（ボタンの表示判定にだけ使う）。
    @Published private(set) var hasCandidate = false

    private let pasteboard: PasteboardProviding
    /// 一度開いた URL は再提示しない。
    private var dismissedLink: String?

    init(pasteboard: PasteboardProviding = SystemPasteboard()) {
        self.pasteboard = pasteboard
    }

    /// 画面表示時・フォアグラウンド復帰時に呼ぶ。
    func refresh() async {
        hasCandidate = await pasteboard.containsProbableURL()
    }

    /// ボタンが押されたときに呼ぶ。YouTube の URL なら返す（それ以外は nil）。
    func takeYouTubeLink() -> String? {
        guard let raw = pasteboard.readString(),
              let link = SharedLinkParser.extractYouTubeURLString(from: raw) else {
            hasCandidate = false
            return nil
        }
        guard link != dismissedLink else {
            hasCandidate = false
            return nil
        }
        dismissedLink = link
        hasCandidate = false
        return link
    }

    /// ボタンを閉じる（今回は使わない、の意思表示）。
    func dismiss() {
        hasCandidate = false
    }
}

#if canImport(UIKit)
/// 実機用。`detectPatterns` は中身を露出しないので確認ダイアログが出ない。
struct SystemPasteboard: PasteboardProviding {
    func containsProbableURL() async -> Bool {
        guard UIPasteboard.general.hasStrings else { return false }
        do {
            let patterns = try await UIPasteboard.general.detectPatterns(for: [.probableWebURL])
            return patterns.contains(.probableWebURL)
        } catch {
            return false
        }
    }

    func readString() -> String? {
        UIPasteboard.general.string
    }
}
#else
struct SystemPasteboard: PasteboardProviding {
    func containsProbableURL() async -> Bool { false }
    func readString() -> String? { nil }
}
#endif
