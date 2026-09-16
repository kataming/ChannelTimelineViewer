import Foundation
import SwiftUI

/// 「チャンネルの追加方法」の案内を見終わったか。
///
/// 出す条件は「初めてチャンネルを追加しようとしたとき」だけ。起動のたびには出さない。
/// スキップも見終わったのと同じ扱いにする（**同じ案内を二度出さない**。
/// 出し続けると、分かっている人にとっては邪魔でしかない）。
///
/// 保存は他のストアと同じ `UserDefaults`。アプリを消せば一緒に消えるので、
/// 入れ直した人には新しい利用者として、もう一度出る。
@MainActor
final class ChannelTutorialStore: ObservableObject {
    private let key = "channelTutorialCompleted"
    private let defaults: UserDefaults

    @Published private(set) var isCompleted: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isCompleted = defaults.bool(forKey: key)
    }

    // UI テストやスクリーンショット撮影で案内を出したくないときは、起動引数
    //   -channelTutorialCompleted YES
    // を渡す。`UserDefaults` がその値を返すので、上の `init` がそのまま
    // 「見終わった」状態で始まる。**この型に細工は要らない。**
    //
    // ⚠️ 定数にして UITests から参照することはできない（UITests のターゲットからは
    //    アプリ本体の型が見えない）。テスト側には文字列をそのまま書く。
    //    忘れると「テストだけ URL 欄が押せない」という形で表面化する（実際に起きた）。

    /// 見終わった（またはスキップした）。
    ///
    /// 「このアプリについて」から自分で開き直したときは**呼ばない**。
    /// 手で見直しただけで状態が変わると、説明が要る人かどうかの区別がつかなくなる。
    func markCompleted() {
        guard !isCompleted else { return }
        isCompleted = true
        defaults.set(true, forKey: key)
    }

    /// 動作確認用にやり直す（アプリの画面からは呼ばない）。
    func reset() {
        isCompleted = false
        defaults.removeObject(forKey: key)
    }
}
