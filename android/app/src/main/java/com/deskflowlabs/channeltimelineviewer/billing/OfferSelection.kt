package com.deskflowlabs.channeltimelineviewer.billing

/**
 * 「どの購入オファーで買うか」を決める唯一の場所。
 *
 * Play Console で `pro_unlock` に割引特典（例: ある国だけ・期間限定・50%OFF）を作ると、
 * Play は**その人が対象のオファーだけ**を返してくる。対象外の人には通常のオファーしか
 * 返らないので、**国コードをアプリに持たない**。対象かどうかの判断は Play に任せる。
 *
 * [ProPurchaseReporter] と同じ考えで、Billing SDK の型をここへ持ち込まない
 * （SDK の `ProductDetails` は実機の Play ストアが無いと作れず、テストできないため）。
 * SDK からの写し取りは [ProBillingManager] 側の小さな変換関数が行う。
 *
 * ⚠️ 表示する価格と、実際に購入に使うオファーは**必ず同じもの**にすること。
 *    ずれると「画面の値段と請求額が違う」ことになる。そのために選んだ結果を
 *    [SelectedOffer] ひとつにまとめて持ち回る。
 */
object OfferSelection {

    /**
     * Play が返した購入オファー1件の写し。
     *
     * @param offerToken 購入時に `setOfferToken` へ渡す値。これが無いと割引は適用されない
     * @param isDiscount 割引特典か（`discountDisplayInfo` があるか）
     * @param isRental レンタル（`rentalDetails` がある）。`pro_unlock` では使わない
     * @param isPreorder 予約（`preorderDetails` がある）。`pro_unlock` では使わない
     */
    data class Candidate(
        val offerToken: String?,
        val formattedPrice: String?,
        val priceAmountMicros: Long,
        val priceCurrencyCode: String,
        val offerId: String?,
        val purchaseOptionId: String?,
        val isDiscount: Boolean,
        val isRental: Boolean = false,
        val isPreorder: Boolean = false,
    )

    /** 選んだオファー。価格表示・購入・記録（GA4 の金額）はすべてこれを見る。 */
    data class SelectedOffer(
        /** null なら `setOfferToken` を呼ばない＝旧来どおりの購入（後方互換）。 */
        val offerToken: String?,
        val formattedPrice: String?,
        val priceAmountMicros: Long,
        val priceCurrencyCode: String,
        val offerId: String?,
        val purchaseOptionId: String?,
        val isDiscount: Boolean,
    )

    /**
     * 対象のオファーの中から、実際に買うものを1つ選ぶ。
     *
     * 選び方:
     *   1. 割引オファー（`discountDisplayInfo` あり）があれば割引を優先する
     *   2. 割引が複数あるときは **`priceAmountMicros` が最小**のものを選ぶ
     *   3. 割引が無ければ通常の購入オプション（Play が返した順の先頭）を使う
     *   4. レンタル・予約は `pro_unlock` では使わないので**選ばない**
     *   5. 一覧が空（古い Play ストア・オファーを1つも設定していない商品）のときは、
     *      従来の単数形 [fallback] に戻る。このときトークンは渡さない（＝今までと同じ挙動）
     *
     * @param candidates `getOneTimePurchaseOfferDetailsList()` の写し
     * @param fallback 従来の `getOneTimePurchaseOfferDetails()` の写し（無ければ null）
     */
    fun select(candidates: List<Candidate>, fallback: Candidate?): SelectedOffer? {
        val usable = candidates.filterNot { it.isRental || it.isPreorder }
        val chosen = usable.filter { it.isDiscount }.minByOrNull { it.priceAmountMicros }
            ?: usable.firstOrNull { !it.isDiscount }
        if (chosen != null && !chosen.offerToken.isNullOrBlank()) {
            return chosen.toSelected(offerToken = chosen.offerToken)
        }
        // トークンの無いオファーは買えない（＝Play の返しが想定外）。従来の形に戻す。
        return fallback?.toSelected(offerToken = null)
    }

    private fun Candidate.toSelected(offerToken: String?) = SelectedOffer(
        offerToken = offerToken,
        formattedPrice = formattedPrice,
        priceAmountMicros = priceAmountMicros,
        priceCurrencyCode = priceCurrencyCode,
        offerId = offerId,
        purchaseOptionId = purchaseOptionId,
        isDiscount = isDiscount,
    )
}
