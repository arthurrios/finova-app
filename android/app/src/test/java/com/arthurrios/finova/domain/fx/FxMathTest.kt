package com.arthurrios.finova.domain.fx

import com.arthurrios.finova.data.fx.AwesomeRateProvider
import com.arthurrios.finova.data.fx.FrankfurterRateProvider
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneOffset

class FxMathTest {

    // ---- Conversion: effective rate = max(0, market − spread); total = amount × rate; fee off the total.

    @Test fun convertsAtTheMarketRate() {
        // US$ 5,000.00 × 5.7651 = R$ 28,825.50
        assertEquals(2_882_550L, FxMath.convert(500_000, 5_765_100, fxDigits = 2, baseDigits = 2))
    }

    @Test fun providerDifferenceLowersTheRateBeforeConverting() {
        // 5.7651 − 0.05 = 5.7151 → R$ 28,575.50
        assertEquals(2_857_550L, FxMath.convert(500_000, 5_765_100, 2, 2, spreadMicros = 50_000))
        assertEquals(5_715_100L, FxMath.effectiveRateMicros(5_765_100, 50_000))
    }

    @Test fun feeComesOffTheTotalAfterTheDifference() {
        // R$ 28,575.50 − 0.9% (257.1795) = 28,318.3205 → 28,318.32
        assertEquals(2_831_832L, FxMath.convert(500_000, 5_765_100, 2, 2, feeBps = 90, spreadMicros = 50_000))
    }

    @Test fun aDifferenceBiggerThanTheRateNeverGoesBelowZero() {
        assertEquals(0L, FxMath.effectiveRateMicros(1_000_000, 2_000_000))
        assertEquals(0L, FxMath.convert(100, 1_000_000, 2, 2, spreadMicros = 2_000_000))
        // A negative difference is ignored, never added.
        assertEquals(1_000_000L, FxMath.effectiveRateMicros(1_000_000, -5))
    }

    @Test fun roundsHalfToEven() {
        // 0.05 × 1.5 = 0.075 → 0.08 (7.5 cents rounds to 8); 0.05 × 0.5 = 0.025 → 0.02.
        assertEquals(8L, FxMath.convert(5, 1_500_000, 2, 2))
        assertEquals(2L, FxMath.convert(5, 500_000, 2, 2))
    }

    @Test fun respectsMinorUnitDigits() {
        // ¥10,000 × 0.0366 BRL = R$ 366.00 (JPY has no cents).
        assertEquals(36_600L, FxMath.convert(10_000, 36_600, fxDigits = 0, baseDigits = 2))
        assertEquals(0, FxCurrency.digits("JPY"))
        assertEquals(2, FxCurrency.digits("BRL"))
    }

    @Test fun conversionUsesTheRowsOwnDifferenceAndFee() {
        val fx = ForeignAmount("USD", 500_000, feeBps = 90, spreadMicros = 50_000)
        assertEquals(2_831_832L, FxConversion.convert(fx, 5_765_100, "BRL"))
    }

    // ---- Fee text

    @Test fun parsesFeeText() {
        assertEquals(0L, FxMath.feeBps(""))
        assertEquals(90L, FxMath.feeBps("0,9"))
        assertEquals(20L, FxMath.feeBps("0.2"))
        assertEquals(20L, FxMath.feeBps("0,20 %"))
        assertEquals(9_999L, FxMath.feeBps("99,99"))
    }

    @Test fun rejectsAFeeThatIsNotAPercent() {
        // An invalid fee must block Save, never be saved as 0%.
        assertNull(FxMath.feeBps("100"))
        assertNull(FxMath.feeBps("1,2,3"))
        assertNull(FxMath.feeBps("abc"))
        assertNull(FxMath.feeBps("-1"))
    }

    @Test fun feeTextAlwaysUsesAPoint() {
        assertEquals("0.20", FxMath.feeText(20))
        assertEquals("1.05", FxMath.feeText(105))
    }

    // ---- Badge

    @Test fun changeIsInTenthsOfAPercent() {
        assertEquals(80L, FxMath.changeTenths(5_000_000, 5_400_000))
        // 5.3381 → 5.7651 = +7.999% → +8.0%
        assertEquals(80L, FxMath.changeTenths(5_338_100, 5_765_100))
        assertEquals(-23L, FxMath.changeTenths(1_000_000, 977_000))
        assertNull(FxMath.changeTenths(0, 5))
    }

    @Test fun formatsChangeWithARealMinusAndAPoint() {
        assertEquals("+8.0%", FxMath.formatChange(80))
        assertEquals("−2.3%", FxMath.formatChange(-23))
        assertEquals("0.0%", FxMath.formatChange(0))
    }

    @Test fun toneMeansGoodOrBadForTheUser() {
        assertEquals(FxBadgeTone.Good, FxBadgeTone.tone(isIncome = true, changeTenths = 5))
        assertEquals(FxBadgeTone.Bad, FxBadgeTone.tone(isIncome = true, changeTenths = -5))
        assertEquals(FxBadgeTone.Bad, FxBadgeTone.tone(isIncome = false, changeTenths = 5))
        assertEquals(FxBadgeTone.Neutral, FxBadgeTone.tone(isIncome = true, changeTenths = 0))
    }

    @Test fun badgeComparesTheEntryRateWithTheLockedRateAfterPayday() {
        val live = ForeignAmount("USD", 100, entryRateMicros = 5_000_000)
        assertEquals(80L, live.changeTenths(5_400_000))
        val locked = live.copy(rateMicros = 4_900_000, lockedAt = 1)
        assertEquals(-20L, locked.changeTenths(5_400_000))
    }

    @Test fun impliedRateFromTheAmountReceived() {
        // R$ 28,000.00 for US$ 5,000.00 → 5.6
        assertEquals(5_600_000L, FxMath.impliedRateMicros(2_800_000, 500_000, 2, 2))
        assertNull(FxMath.impliedRateMicros(0, 500_000, 2, 2))
    }

    // ---- Lock rule and the refresh pass

    private val today = "2026-11-20"
    private val now = 1_795_000_000L
    private fun quote(rate: Long, date: String = today) = FxQuote("USD", "BRL", date, rate, FxSource.Market, quotedAt = now)

    @Test fun lockRule() {
        assertEquals(FxLockRule.Decision.Live, FxLockRule.decide("2026-11-21", today, quote(1)))
        assertEquals(FxLockRule.Decision.Wait, FxLockRule.decide(today, today, null))
        assertEquals(FxLockRule.Decision.Lock(quote(1)), FxLockRule.decide("2026-11-19", today, quote(1)))
    }

    @Test fun paydayLocksWithTheRateAndConvertsWithTheRowsDifference() {
        val fx = ForeignAmount("USD", 500_000, entryRateMicros = 5_000_000, spreadMicros = 50_000)
        val change = FxRowPlanner.plan(1, LocalDate.parse(today), 0, fx, "BRL", today, quote(5_000_000), quote(5_765_100), now)!!
        assertTrue(change.foreign!!.isLocked)
        assertEquals(5_765_100L, change.foreign!!.rateMicros) // Stored rates stay market rates.
        assertEquals("market", change.foreign!!.rateSource)
        assertEquals(now, change.foreign!!.rateDate)
        assertEquals(2_857_550L, change.amount)
        assertEquals(false, change.isLiveMove)
    }

    @Test fun beforePaydayFollowsTheLiveRateAndSkipsUnchangedRows() {
        val fx = ForeignAmount("USD", 500_000)
        val date = LocalDate.parse("2026-11-25")
        val moved = FxRowPlanner.plan(1, date, 0, fx, "BRL", today, quote(5_765_100), null, now)!!
        assertEquals(2_882_550L, moved.amount)
        assertTrue(moved.isLiveMove)
        assertNull(FxRowPlanner.plan(1, date, 2_882_550, fx, "BRL", today, quote(5_765_100), null, now))
        // Offline: keep the last known amount.
        assertNull(FxRowPlanner.plan(1, date, 0, fx, "BRL", today, null, null, now))
    }

    @Test fun aPaydayWithNoFreshRateStaysLive() {
        val fx = ForeignAmount("USD", 500_000)
        val change = FxRowPlanner.plan(1, LocalDate.parse(today), 0, fx, "BRL", today, quote(5_765_100), null, now)!!
        assertNull(change.foreign!!.lockedAt)
    }

    @Test fun aLockedRowNeverChangesUnlessTheAppCurrencyBecameItsOwn() {
        val locked = ForeignAmount("USD", 500_000, rateMicros = 5_000_000, lockedAt = 1)
        assertNull(FxRowPlanner.plan(1, LocalDate.parse(today), 5, locked, "BRL", today, quote(6_000_000), quote(6_000_000), now))
        val plain = FxRowPlanner.plan(1, LocalDate.parse(today), 5, locked, "USD", today, null, null, now)!!
        assertNull(plain.foreign)
        assertEquals(500_000L, plain.amount)
    }

    // ---- Editing

    private val day = LocalDate.of(2026, 11, 20)

    @Test fun newForeignIncomeTakesTheLiveRateAsItsEntryRate() {
        val r = FxEditPlanner.apply(null, day, day, "USD", 500_000, "BRL", 5_765_100, 42, feeBps = 0, spreadMicros = 50_000)!!
        assertEquals(5_765_100L, r.foreign!!.entryRateMicros)
        assertEquals(42L, r.foreign!!.entryRateDate)
        assertNull(r.foreign!!.feeBps) // 0 is saved as "none".
        assertEquals(50_000L, r.foreign!!.spreadMicros)
        assertEquals(2_857_550L, r.amount)
    }

    @Test fun noRateMeansTheFormMustAskForOne() {
        assertNull(FxEditPlanner.apply(null, day, day, "USD", 500_000, "BRL", null, null))
    }

    @Test fun setBackToTheAppCurrencyIsAnOrdinaryRow() {
        val old = ForeignAmount("USD", 500_000, entryRateMicros = 1)
        assertEquals(FxEditPlanner.Result(null, 12_345), FxEditPlanner.apply(old, day, day, "BRL", 12_345, "BRL", 5_000_000, null))
    }

    @Test fun editingALockedRowOnTheSameDayKeepsTheLockedRate() {
        val old = ForeignAmount("USD", 500_000, rateMicros = 5_000_000, lockedAt = 9, entryRateMicros = 4_000_000)
        val r = FxEditPlanner.apply(old, day, day, "USD", 600_000, "BRL", 9_000_000, null)!!
        assertEquals(9L, r.foreign!!.lockedAt)
        assertEquals(3_000_000L, r.amount)
    }

    @Test fun movingALockedRowToAnotherDayUnlocksItAndKeepsTheEntryRate() {
        val old = ForeignAmount("USD", 500_000, rateMicros = 5_000_000, lockedAt = 9, entryRateMicros = 4_000_000, entryRateDate = 7)
        val r = FxEditPlanner.apply(old, day, day.plusDays(3), "USD", 500_000, "BRL", 6_000_000, null)!!
        assertNull(r.foreign!!.lockedAt)
        assertEquals(4_000_000L, r.foreign!!.entryRateMicros)
        assertEquals(3_000_000L, r.amount)
    }

    @Test fun aNewCurrencyResetsTheEntryRate() {
        val old = ForeignAmount("USD", 500_000, entryRateMicros = 4_000_000)
        val r = FxEditPlanner.apply(old, day, day, "EUR", 500_000, "BRL", 6_000_000, 1)!!
        assertEquals(6_000_000L, r.foreign!!.entryRateMicros)
    }

    @Test fun amountReceivedNeedsALockAndStoresTheImpliedRate() {
        val live = ForeignAmount("USD", 500_000)
        assertNull(FxEditPlanner.received(live, 2_800_000, "BRL"))
        val r = FxEditPlanner.received(live.copy(rateMicros = 5_000_000, lockedAt = 1), 2_800_000, "BRL")!!
        assertEquals(5_600_000L, r.foreign!!.rateMicros)
        assertTrue(r.foreign!!.isReceivedAmount)
        assertEquals(2_800_000L, r.amount)
    }

    @Test fun aSeriesEditLeavesALockedMonthsMoneyAlone() {
        val locked = ForeignAmount("USD", 500_000, rateMicros = 5_000_000, lockedAt = 1)
        val before = tx(2_500_000, locked)
        val edited = before.copy(title = "New", amount = 9)
        val out = FxEditPlanner.seriesRow(before, edited, ForeignAmount("USD", 700_000), "BRL") { 6_000_000 }
        assertEquals("New", out.title)
        assertEquals(locked, out.foreign)
        assertEquals(2_500_000L, out.amount)
    }

    @Test fun aSeriesEditMovesLiveMonthsToTheNewMoneyKeepingTheEntryRate() {
        val before = tx(2_500_000, ForeignAmount("USD", 500_000, entryRateMicros = 4_000_000))
        val new = ForeignAmount("USD", 700_000, entryRateMicros = 6_000_000, rateMicros = 1, lockedAt = 1, spreadMicros = 1_000_000)
        val out = FxEditPlanner.seriesRow(before, before, new, "BRL") { 6_000_000 }
        assertNull(out.foreign!!.lockedAt)
        assertEquals(4_000_000L, out.foreign!!.entryRateMicros)
        assertEquals(3_500_000L, out.amount) // 7,000.00 × (6.0 − 1.0)
    }

    private fun tx(amount: Long, fx: ForeignAmount?) = Transaction(
        title = "Salary", category = TransactionCategory.Salary, type = TransactionType.Income, amount = amount,
        date = day, budgetMonth = YearMonth.from(day), foreign = fx,
    )

    // ---- Provider answers

    @Test fun readsFrankfurterExactly() {
        val q = FrankfurterRateProvider.parse("""{"amount":1.0,"base":"USD","date":"2026-11-20","rates":{"BRL":5.7651}}""", "USD", "BRL")
        assertEquals(5_765_100L, q.rateMicros)
        assertEquals("2026-11-20", q.date)
        assertEquals(FxSource.Ecb, q.source)
    }

    @Test fun awesomeRateIsTheMidOfBidAndAsk() {
        val q = AwesomeRateProvider.quote(
            """{"code":"USD","bid":"5.6513","ask":"5.6518","timestamp":"1795728610"}""", "USD", "BRL", ZoneOffset.UTC,
        )
        assertEquals(5_651_550L, q.rateMicros)
        assertEquals(1_795_728_610L, q.quotedAt)
        assertEquals(FxSource.Market, q.source)
        val bidOnly = AwesomeRateProvider.quote("""{"bid":"5.6513","timestamp":"1795728610"}""", "USD", "BRL", ZoneOffset.UTC)
        assertEquals(5_651_300L, bidOnly.rateMicros)
    }
}
