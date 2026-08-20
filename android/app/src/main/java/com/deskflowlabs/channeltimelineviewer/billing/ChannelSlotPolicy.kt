package com.deskflowlabs.channeltimelineviewer.billing

/**
 * 「保存できるチャンネルは何件か」だけを決める純粋なロジック。
 *
 * 制限するのは**同時に保存できるチャンネル数だけ**で、保存済みチャンネルの中の機能は
 * 無料でも一切制限しない（並べ替え・視聴済み・続きから・メモ・進捗・公式プレイヤー再生）。
 *
 * Google Play や Compose に依存させないので、そのまま単体テストできる。
 */
object ChannelSlotPolicy {

    /** 無料で同時に保存できるチャンネル数。 */
    const val FREE_CHANNEL_LIMIT = 1

    /**
     * そのチャンネルを開いて（＝保存して）よいか。
     *
     * - Pro なら常に可
     * - すでに保存済みのチャンネルなら可（枠を増やさないため）
     * - 空きがあれば可
     *
     * 以前のバージョンで2件以上保存している人（この課金を入れる前からの利用者）が
     * いても、**保存済みのものは開ける**。減らすのは本人の操作に任せる。
     */
    fun canOpen(savedChannelIds: Collection<String>, channelId: String, isPro: Boolean): Boolean =
        isPro || channelId in savedChannelIds || savedChannelIds.size < FREE_CHANNEL_LIMIT

    /**
     * 入れ替えのために外すチャンネル。新しく1件入れる空きを作る分だけ、
     * 古い（最後に開いたのが古い）ものから外す。
     *
     * @param savedChannelIdsNewestFirst 最終利用が新しい順に並んだ保存済みチャンネル
     */
    fun idsToRemoveForReplacement(savedChannelIdsNewestFirst: List<String>): List<String> {
        val keep = (FREE_CHANNEL_LIMIT - 1).coerceAtLeast(0)
        if (savedChannelIdsNewestFirst.size <= keep) return emptyList()
        return savedChannelIdsNewestFirst.drop(keep)
    }
}
