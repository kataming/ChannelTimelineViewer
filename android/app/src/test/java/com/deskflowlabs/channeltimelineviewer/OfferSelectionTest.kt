package com.deskflowlabs.channeltimelineviewer

import com.deskflowlabs.channeltimelineviewer.billing.OfferSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「どのオファーで買うか」のテスト（Play の割引特典対応・2026-09-21）。
 *
 * 見ているのは次の2点。
 *   1. 対象の人には**割引**、対象外の人には**通常価格**（対象かどうかは Play が決める。
 *      アプリは返ってきたものから選ぶだけで、国コードは持たない）
 *   2. **画面に出す価格と、実際に購入するオファーが必ず同じ**であること
 */
class OfferSelectionTest {

    private fun offer(
        token: String,
        micros: Long,
        discount: Boolean = false,
        rental: Boolean = false,
        preorder: Boolean = false,
        currency: String = "JPY",
        offerId: String? = null,
    ) = OfferSelection.Candidate(
        offerToken = token,
        formattedPrice = "¥" + (micros / 1_000_000),
        priceAmountMicros = micros,
        priceCurrencyCode = currency,
        offerId = offerId,
        purchaseOptionId = "buy",
        isDiscount = discount,
        isRental = rental,
        isPreorder = preorder,
    )

    private val legacy = offer(token = "legacy-token", micros = 700_000_000)

    @Test
    fun onlyNormalOfferMeansNormalPrice() {
        val selected = OfferSelection.select(listOf(offer("normal", 700_000_000)), legacy)!!
        assertEquals("normal", selected.offerToken)
        assertEquals(700_000_000L, selected.priceAmountMicros)
        assertFalse("割引ではない", selected.isDiscount)
    }

    /** 割引特典の対象外の人には、Play が通常オファーしか返さない。 */
    @Test
    fun userOutsideTheOfferGetsNormalPrice() {
        val selected = OfferSelection.select(
            listOf(offer("normal", 700_000_000), offer("normal2", 700_000_000)),
            legacy,
        )!!
        assertEquals("normal", selected.offerToken)
        assertFalse(selected.isDiscount)
    }

    @Test
    fun discountWinsOverNormal() {
        val selected = OfferSelection.select(
            listOf(
                offer("normal", 700_000_000),
                offer("half", 350_000_000, discount = true, offerId = "bd-50off"),
            ),
            legacy,
        )!!
        assertEquals("half", selected.offerToken)
        assertEquals(350_000_000L, selected.priceAmountMicros)
        assertEquals("bd-50off", selected.offerId)
        assertTrue(selected.isDiscount)
    }

    @Test
    fun cheapestDiscountWinsWhenSeveralApply() {
        val selected = OfferSelection.select(
            listOf(
                offer("normal", 700_000_000),
                offer("off30", 490_000_000, discount = true),
                offer("off50", 350_000_000, discount = true),
                offer("off10", 630_000_000, discount = true),
            ),
            legacy,
        )!!
        assertEquals("off50", selected.offerToken)
        assertEquals(350_000_000L, selected.priceAmountMicros)
    }

    /** 安いだけの通常オファーを「割引」と呼ばない（割引の表示情報が無いものは通常）。 */
    @Test
    fun cheapNormalOfferIsNotTreatedAsDiscount() {
        val selected = OfferSelection.select(
            listOf(offer("normal", 700_000_000), offer("cheap", 100_000_000)),
            legacy,
        )!!
        assertFalse("割引と誤認しない", selected.isDiscount)
        // 割引が無いときは Play が返した順の先頭（＝下位互換の購入オプション）。
        assertEquals("normal", selected.offerToken)
    }

    @Test
    fun rentalAndPreorderAreNeverSelected() {
        val selected = OfferSelection.select(
            listOf(
                offer("rent", 100_000_000, rental = true),
                offer("rent-sale", 50_000_000, discount = true, rental = true),
                offer("preorder", 200_000_000, preorder = true),
                offer("normal", 700_000_000),
            ),
            legacy,
        )!!
        assertEquals("normal", selected.offerToken)
    }

    @Test
    fun emptyListFallsBackToTheOldSingleOffer() {
        val selected = OfferSelection.select(emptyList(), legacy)!!
        // 旧環境では従来どおりトークンを渡さない（渡さないのが今までの挙動）。
        assertNull(selected.offerToken)
        assertEquals(700_000_000L, selected.priceAmountMicros)
        assertEquals("¥700", selected.formattedPrice)
    }

    @Test
    fun offerWithoutTokenFallsBack() {
        val selected = OfferSelection.select(listOf(offer("", 350_000_000, discount = true)), legacy)!!
        assertNull(selected.offerToken)
        assertEquals(700_000_000L, selected.priceAmountMicros)
    }

    @Test
    fun nothingAtAllMeansNoOffer() {
        assertNull(OfferSelection.select(emptyList(), null))
    }

    /** 表示・購入・記録がひとつの [OfferSelection.SelectedOffer] から出ることの確認。 */
    @Test
    fun priceShownAndPriceChargedComeFromTheSameOffer() {
        val selected = OfferSelection.select(
            listOf(offer("normal", 700_000_000), offer("half", 350_000_000, discount = true, currency = "BDT")),
            legacy,
        )!!
        assertEquals("half", selected.offerToken)
        assertEquals("¥350", selected.formattedPrice)
        assertEquals(350_000_000L, selected.priceAmountMicros)
        assertEquals("BDT", selected.priceCurrencyCode)
    }
}
