import Foundation

/// 「保存できるチャンネルは何件か」だけを決める純粋なロジック。
///
/// 制限するのは**同時に保存できるチャンネル数だけ**で、保存したチャンネルの中の機能は
/// 無料でも一切制限しない（並べ替え・視聴済み・続きから・移動ボタン・メモ・進捗・公式プレイヤー再生）。
///
/// Android 版 `billing/ChannelSlotPolicy.kt` と同じ判定にしてある（挙動を揃えるため）。
enum ChannelSlotPolicy {

    /// 無料で同時に保存できるチャンネル数。
    static let freeChannelLimit = 1

    /// そのチャンネルを新しく開いて（＝保存して）よいか。
    ///
    /// - Pro なら常に可
    /// - すでに保存済みなら可（枠を増やさないため）
    /// - 空きがあれば可
    static func canOpen(savedChannelIds: [String], channelId: String, isPro: Bool) -> Bool {
        isPro || savedChannelIds.contains(channelId) || savedChannelIds.count < freeChannelLimit
    }

    /// いま使えるチャンネル。ここに入らない保存済みチャンネルは**ロック**する。
    ///
    /// Pro を返金・取消などで失った人が、保存済みの複数チャンネルをそのまま使い続けられると
    /// 「買って返して使い放題」になるため、上限を超えた分は開けなくする。
    /// ただし**記録は消さない**。Pro を買い直せば全部そのまま戻る。
    ///
    /// - Parameters:
    ///   - savedChannelIdsNewestFirst: 最終利用が新しい順の保存済みチャンネル
    ///   - activeChannelId: 利用者が「無料ではこれを使う」と選んだチャンネル（未選択なら nil）
    static func usableChannelIds(savedChannelIdsNewestFirst: [String],
                                 isPro: Bool,
                                 activeChannelId: String?) -> Set<String> {
        if isPro || savedChannelIdsNewestFirst.count <= freeChannelLimit {
            return Set(savedChannelIdsNewestFirst)
        }
        var usable: [String] = []
        if let activeChannelId, savedChannelIdsNewestFirst.contains(activeChannelId) {
            usable.append(activeChannelId)
        }
        // 未選択・枠が余っている場合は、最後に開いたのが新しい方から埋める。
        for id in savedChannelIdsNewestFirst where usable.count < freeChannelLimit {
            if !usable.contains(id) { usable.append(id) }
        }
        return Set(usable)
    }

    /// 保存はされているが、いまは開けない状態か。
    static func isLocked(savedChannelIdsNewestFirst: [String],
                         channelId: String,
                         isPro: Bool,
                         activeChannelId: String?) -> Bool {
        guard savedChannelIdsNewestFirst.contains(channelId) else { return false }
        return !usableChannelIds(savedChannelIdsNewestFirst: savedChannelIdsNewestFirst,
                                 isPro: isPro,
                                 activeChannelId: activeChannelId).contains(channelId)
    }

    /// 無料ユーザーが「入れ替える」を選んだときに外すチャンネル。
    /// 新しく1件入れる空きを作る分だけ、最後に開いたのが古い方から外す。
    ///
    /// - Important: 外したチャンネルの記録は**削除する**（`ChannelDataRemover`）。
    ///   ロック（Pro 失効時）とは扱いが違うので混同しないこと。
    static func idsToRemoveForReplacement(savedChannelIdsNewestFirst: [String]) -> [String] {
        let keep = max(freeChannelLimit - 1, 0)
        guard savedChannelIdsNewestFirst.count > keep else { return [] }
        return Array(savedChannelIdsNewestFirst.dropFirst(keep))
    }
}
