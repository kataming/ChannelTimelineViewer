import Foundation

/// 動画一覧のメニュー「一番上へ」「一番下へ」の飛び先（Android の VideoListScreen と同じ動き）。
///
/// 5,000 本を超えるチャンネルでも一気に飛べるよう、行の ID を決めるだけにして
/// 画面側（`ScrollViewReader`）でアニメーションなしで `scrollTo` する。
enum VideoListScrollTarget {
    enum Edge: Equatable {
        case top
        case bottom
    }

    /// 検索欄の行（検索中だけ一覧の一番上に出る）。動画 ID（11文字）とは重ならない名前にする。
    static let searchRowID = "ctv.list.top.search"
    /// 進捗の行（動画が1本以上あるとき一覧の一番上の区画に出る）。
    static let progressRowID = "ctv.list.top.progress"

    /// 飛び先の行の ID。飛べる行が無ければ nil。
    ///
    /// - 一番上: 検索中なら検索欄、そうでなければ進捗の行、それも無ければ最初の動画
    /// - 一番下: いま見えている（絞り込み後の）最後の動画
    static func id(for edge: Edge,
                   isSearching: Bool,
                   hasProgressRow: Bool,
                   visibleVideoIds: [String]) -> String? {
        switch edge {
        case .top:
            if isSearching { return searchRowID }
            if hasProgressRow { return progressRowID }
            return visibleVideoIds.first
        case .bottom:
            return visibleVideoIds.last
        }
    }
}
