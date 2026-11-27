package com.arthurrios.finova.domain.fx

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Where a transaction's `amount` came from when it was received in another currency (1.7.0).
 * Port of `ForeignAmount` on iOS.
 *
 * `Transaction.amount` stays in the app currency, always, so every ledger, budget and balance
 * reader is untouched. This value only describes the conversion: the money as received, the rate
 * used, and whether that rate is still live (follows the market) or locked (frozen on payday).
 *
 * Times are epoch seconds, as on iOS.
 */
data class ForeignAmount(
    /** ISO 4217 code of the money received, e.g. "USD". */
    val currency: String,
    /** Amount in that currency, minor units (US$ 5,000.00 → 500000). */
    val amount: Long,
    /** Locked rate × 1,000,000. Null while live. */
    val rateMicros: Long? = null,
    /** When the locked rate was quoted (market) or its day (ECB), epoch seconds. Null while live. */
    val rateDate: Long? = null,
    /** When the rate was frozen, epoch seconds. Not null = locked forever. */
    val lockedAt: Long? = null,
    /** Rate when the income was added (the % badge baseline), × 1,000,000. */
    val entryRateMicros: Long? = null,
    /** When that entry rate was quoted, epoch seconds. */
    val entryRateDate: Long? = null,
    /** The user typed the amount actually received after the lock ("Enter amount received"). */
    val isReceivedAmount: Boolean = false,
    /** "market" or "ecb": where the locked rate came from. */
    val rateSource: String? = null,
    /** Fee the user expects on the conversion, basis points (20 = 0.20%), off the total. */
    val feeBps: Long? = null,
    /**
     * "Provider difference": how much less than the market the user's provider pays, in app
     * currency per 1 unit of [currency], × 1,000,000 (R$ 0,05 per US$ 1 → 50000).
     */
    val spreadMicros: Long? = null,
) {
    val isLocked: Boolean get() = lockedAt != null

    /**
     * A copy for a NEW occurrence of a recurring series: same money and the series' entry rate,
     * but never the template's lock. Copying a lock would freeze future months at an old rate.
     */
    fun unlockedCopy() = ForeignAmount(
        currency = currency, amount = amount,
        entryRateMicros = entryRateMicros, entryRateDate = entryRateDate,
        feeBps = feeBps, spreadMicros = spreadMicros,
    )

    /** The rate the badge compares with the entry rate: the locked rate after payday, the live one before. */
    fun currentRateMicros(liveRateMicros: Long?): Long? = if (isLocked) rateMicros else liveRateMicros

    /** Badge value in tenths of a percent, or null when there is no baseline or no rate. */
    fun changeTenths(liveRateMicros: Long?): Long? {
        val entry = entryRateMicros ?: return null
        val current = currentRateMicros(liveRateMicros) ?: return null
        return FxMath.changeTenths(entry, current)
    }
}

/** The conversion and % badge math. Pure and integer/BigDecimal only, the same as iOS `FxMath`. */
object FxMath {
    const val MICROS_PER_UNIT = 1_000_000L

    /**
     * `round_half_even(fxAmount × max(0, rate − spread) × 10^(baseDigits − fxDigits))`, then the
     * fee (basis points) comes off that total. Rates in micros.
     */
    fun convert(
        fxAmount: Long,
        rateMicros: Long,
        fxDigits: Int,
        baseDigits: Int,
        feeBps: Long = 0,
        spreadMicros: Long = 0,
    ): Long {
        val rate = effectiveRateMicros(rateMicros, spreadMicros)
        var value = BigDecimal.valueOf(fxAmount)
            .multiply(BigDecimal.valueOf(rate))
            .movePointLeft(6)
            .movePointRight(baseDigits - fxDigits)
        val fee = feeBps.coerceIn(0, 9_999)
        if (fee > 0) value = value.multiply(BigDecimal.valueOf(10_000 - fee)).movePointLeft(4)
        return roundHalfEven(value)
    }

    /** The rate the user's provider really pays: market minus the provider difference, never below 0. */
    fun effectiveRateMicros(rateMicros: Long, spreadMicros: Long): Long =
        maxOf(0, rateMicros - maxOf(0, spreadMicros))

    private val FeePattern = Regex("""^(\d+(\.\d*)?|\.\d+)$""")

    /** "0,20" / "0.2" / "" → basis points (20). Null for text that is not a percent from 0 to 99.99. */
    fun feeBps(fromText: String): Long? {
        val cleaned = fromText.trim().replace("%", "").trim().replace(",", ".")
        if (cleaned.isEmpty()) return 0
        if (!FeePattern.matches(cleaned)) return null
        val value = cleaned.toBigDecimalOrNull() ?: return null
        if (value.signum() < 0 || value >= BigDecimal(100)) return null
        return roundHalfEven(value.movePointRight(2))
    }

    /** 20 → "0.20" (no % sign), always a point. */
    fun feeText(bps: Long): String = "%d.%02d".format(bps / 100, bps % 100)

    /** The rate implied by an amount typed by hand: `typed / fxAmount`, in micros. */
    fun impliedRateMicros(typedAmount: Long, fxAmount: Long, fxDigits: Int, baseDigits: Int): Long? {
        if (fxAmount <= 0 || typedAmount <= 0) return null
        return BigDecimal.valueOf(typedAmount)
            .movePointRight(6 + fxDigits - baseDigits)
            .divide(BigDecimal.valueOf(fxAmount), 0, RoundingMode.HALF_EVEN)
            .longValueExact()
    }

    /** A decimal rate (as the provider sends it, e.g. "5.7651") to micros. */
    fun micros(fromRate: BigDecimal): Long = roundHalfEven(fromRate.movePointRight(6))

    /**
     * Change from [baselineMicros] to [currentMicros] in tenths of a percent, rounded half away
     * from zero. 5.0000 → 5.4000 = 80 (+8.0%). Integers only, so both platforms agree.
     */
    fun changeTenths(baselineMicros: Long, currentMicros: Long): Long? {
        if (baselineMicros <= 0 || currentMicros <= 0) return null
        val n = (currentMicros - baselineMicros) * 1000
        val d = baselineMicros
        return if (n >= 0) (2 * n + d) / (2 * d) else -((-2 * n + d) / (2 * d))
    }

    /** `+8.0%`, `−2.3%`, `0.0%` (never `−0.0%`), with a real minus and always a point. */
    fun formatChange(tenths: Long): String {
        val magnitude = kotlin.math.abs(tenths)
        val body = "${magnitude / 10}.${magnitude % 10}%"
        return when {
            tenths > 0 -> "+$body"
            tenths < 0 -> "−$body"
            else -> body
        }
    }

    fun roundHalfEven(value: BigDecimal): Long = value.setScale(0, RoundingMode.HALF_EVEN).longValueExact()
}

/** Good or bad for the user, not up or down. Income going up is good; an expense going up is bad. */
enum class FxBadgeTone {
    Good, Bad, Neutral;

    companion object {
        fun tone(isIncome: Boolean, changeTenths: Long): FxBadgeTone = when {
            changeTenths == 0L -> Neutral
            (changeTenths > 0) == isIncome -> Good
            else -> Bad
        }
    }
}
