import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 「YouTube の共有から追加する」で使うクリップボードの窓口（テスト用に差し替えられるようにする）。
protocol CopyGuidePasteboard {
    /// クリップボードが書き換わるたびに増える番号。**中身は読まない**（ペーストの確認は出ない）。
    var changeCount: Int { get }
    /// Web の URL らしきものが入っているか。**中身は読まない**（ペーストの確認は出ない）。
    func containsProbableWebURL() async -> Bool
    /// 実際の中身を読む。iOS 16 以降、他のアプリでコピーしたものだとペーストの確認が出る。
    func readText() -> String?
}

/// 「YouTube の共有から追加する」（Android 版の CopyLinkGuide に当たる iOS 版）。
///
/// 1. 案内の［YouTube を開く］で YouTube を開く直前に `startAwaiting()` を呼ぶ
///    （そのときのクリップボードの変更番号を控える）
/// 2. 利用者は YouTube で［共有］→［コピー］を押し、iOS が左上に出す「◀ アプリ名」で戻る
/// 3. 前面に戻ったら `takeNewlyCopiedLink()`。**案内から YouTube へ行っていたときだけ**、
///    クリップボードが書き換わっていて URL らしきものがあれば中身を読み、YouTube の URL なら返す
///
/// iOS では裏でクリップボードを読めず、画面の端にボタンを出すこともできない（Android との違い）。
/// 中身を読むとペーストの確認が出るので、`changeCount` と `containsProbableWebURL()`（どちらも
/// 中身を読まない）で先に絞り、**読むのは1回の戻りにつき多くて1回**にしている。
/// 読むのは YouTube の URL だけで、それ以外は使わず、どこにも送らない。
@MainActor
final class CopyLinkGuideStore: ObservableObject {

    enum Outcome: Equatable {
        /// 何もしない（案内から YouTube へ行っていない・まだ何もコピーしていない・時間切れ）。
        case none
        /// 新しくコピーされた YouTube のリンク。待ち状態は終わっている。
        case link(String)
        /// 新しく何かコピーされたが、YouTube のリンクではなかった（または読めなかった）。
        case notYouTube
    }

    /// 案内から YouTube を開いてから、この時間までに戻ってきたら「コピーしに行っていた」とみなす（Android と同じ 30 分）。
    static let awaitInterval: TimeInterval = 30 * 60

    private static let sinceKey = "copyGuide.awaitingSince"
    private static let baselineKey = "copyGuide.baselineChangeCount"

    private let defaults: UserDefaults
    private let pasteboard: CopyGuidePasteboard
    private let now: () -> Date
    /// 前面に戻ったときの確認が重ならないようにする（ペーストの確認を二重に出さない）。
    private var isChecking = false

    init(defaults: UserDefaults = .standard,
         pasteboard: CopyGuidePasteboard = SystemCopyGuidePasteboard(),
         now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.pasteboard = pasteboard
        self.now = now
    }

    /// 案内から YouTube へ行っている途中か。
    var isAwaiting: Bool {
        guard let since = defaults.object(forKey: Self.sinceKey) as? Date else { return false }
        return now().timeIntervalSince(since) <= Self.awaitInterval
    }

    /// 案内から YouTube を開く直前に呼ぶ。
    func startAwaiting() {
        defaults.set(now(), forKey: Self.sinceKey)
        defaults.set(pasteboard.changeCount, forKey: Self.baselineKey)
    }

    /// 待ち状態をやめる。
    func stopAwaiting() {
        defaults.removeObject(forKey: Self.sinceKey)
        defaults.removeObject(forKey: Self.baselineKey)
    }

    /// 前面に戻ったときに呼ぶ。案内から YouTube へ行っていたときだけクリップボードを見る。
    func takeNewlyCopiedLink() async -> Outcome {
        guard !isChecking else { return .none }
        guard let since = defaults.object(forKey: Self.sinceKey) as? Date else { return .none }
        guard now().timeIntervalSince(since) <= Self.awaitInterval else {
            stopAwaiting()
            return .none
        }
        let current = pasteboard.changeCount
        // 何もコピーしていない（YouTube を見ただけで戻ってきた）。待ち状態は続ける。
        guard current != defaults.integer(forKey: Self.baselineKey) else { return .none }

        isChecking = true
        defer { isChecking = false }
        // 同じコピーで二度は読まない（YouTube のリンクでなかったときも、次のコピーまで待つ）。
        defaults.set(current, forKey: Self.baselineKey)

        guard await pasteboard.containsProbableWebURL() else { return .notYouTube }
        guard let raw = pasteboard.readText(),
              let link = SharedLinkParser.extractYouTubeURLString(from: raw) else {
            return .notYouTube
        }
        stopAwaiting()
        return .link(link)
    }
}

#if canImport(UIKit)
/// 実機用。
struct SystemCopyGuidePasteboard: CopyGuidePasteboard {
    var changeCount: Int { UIPasteboard.general.changeCount }

    func containsProbableWebURL() async -> Bool {
        let pasteboard = UIPasteboard.general
        // URL 型で入っていればそれで足りる（YouTube の［コピー］はこちら）。
        if pasteboard.hasURLs { return true }
        // 文字として入っている場合は、中身を読まずに「URL らしいか」だけを確かめる。
        guard pasteboard.hasStrings else { return false }
        return await withCheckedContinuation { continuation in
            pasteboard.detectPatterns(for: [\UIPasteboard.DetectedValues.probableWebURL]) { result in
                switch result {
                case .success(let found): continuation.resume(returning: !found.isEmpty)
                case .failure: continuation.resume(returning: false)
                }
            }
        }
    }

    func readText() -> String? {
        let pasteboard = UIPasteboard.general
        return pasteboard.string ?? pasteboard.url?.absoluteString
    }
}
#else
struct SystemCopyGuidePasteboard: CopyGuidePasteboard {
    var changeCount: Int { 0 }
    func containsProbableWebURL() async -> Bool { false }
    func readText() -> String? { nil }
}
#endif
