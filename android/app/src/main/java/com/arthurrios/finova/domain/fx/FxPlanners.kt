package com.arthurrios.finova.domain.fx

import com.arthurrios.finova.domain.model.Transaction
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/**
 * One rate as the provider answered it. [date] is the provider's own day ("yyyy-MM-dd"), which can
 * be earlier than the day asked for (weekends, holidays, before the day's publication).
 */
data class FxQuote(
    val base: String,
    val quote: String,
    val date: String,
    val rateMicros: Long,
    val source: FxSource = FxSource.Ecb,
    /** When the market quoted it, epoch seconds. Null for ECB reference rates (one per day). */
    val quotedAt: Long? = null,
)

enum class FxSource(val key: String) {
    /** Live market rate: AwesomeAPI's mid price, (bid + ask) / 2. */
    Market("market"),

    /** European Central Bank daily reference rate (Frankfurter), the fallback. */
    Ecb("ecb");

    companion object {
        fun fromKey(key: String?): FxSource? = entries.firstOrNull { it.key == key }
    }
}

/** Calendar days as "yyyy-MM-dd" in the phone's time zone. Payday and "today" are local days. */
object FxDay {
    fun of(epochSeconds: Long, zone: ZoneId = ZoneId.systemDefault()): String =
        Instant.ofEpochSecond(epochSeconds).atZone(zone).toLocalDate().toString()

    /** Local midnight of a "yyyy-MM-dd" day, as epoch seconds. */
    fun epoch(day: String, zone: ZoneId = ZoneId.systemDefault()): Long? =
        runCatching { LocalDate.parse(day).atStartOfDay(zone).toEpochSecond() }.getOrNull()
}

/** The lock rule (docs/fx-salary-plan.md §3), as a pure function. */
object FxLockRule {
    sealed interface Decision {
        /** Payday has not come yet: keep following the live rate. */
        data object Live : Decision

        /** No rate could be had (offline, or none dated payday yet). Stay live and try again later. */
        data object Wait : Decision

        /** Freeze with this rate, forever. */
        data class Lock(val quote: FxQuote) : Decision
    }

    /**
     * @param payday the row's date ("yyyy-MM-dd", local).
     * @param answer on payday, a fresh live rate dated that day; after payday, that day's closing
     *   rate. Null before payday or when there is none yet.
     */
    fun decide(payday: String, today: String, answer: FxQuote?): Decision = when {
        payday > today -> Decision.Live
        answer == null -> Decision.Wait
        else -> Decision.Lock(answer)
    }
}

/** Minor-unit digits of a currency (BRL 2, JPY 0). */
object FxCurrency {
    fun digits(code: String): Int =
        runCatching { java.util.Currency.getInstance(code).defaultFractionDigits }.getOrDefault(2).coerceAtLeast(0)

    /** Currencies offered first in the picker. */
    val common = listOf("USD", "EUR", "GBP")

    /** Frankfurter's ECB set (the fallback must cover every offered pair). Built in, so the picker works offline. */
    val all = listOf(
        "AUD", "BGN", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR",
        "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK",
        "SGD", "THB", "TRY", "USD", "ZAR",
    )

    /** Whether the app currency is one the provider can convert into. */
    fun isAvailable(appCurrency: String): Boolean = appCurrency in all
}

object FxConversion {
    fun convert(
        fxAmount: Long,
        currency: String,
        rateMicros: Long,
        appCurrency: String,
        feeBps: Long? = null,
        spreadMicros: Long? = null,
    ): Long = FxMath.convert(
        fxAmount = fxAmount,
        rateMicros = rateMicros,
        fxDigits = FxCurrency.digits(currency),
        baseDigits = FxCurrency.digits(appCurrency),
        feeBps = feeBps ?: 0,
        spreadMicros = spreadMicros ?: 0,
    )

    /** A row's amount at [rateMicros], with its own difference and fee. */
    fun convert(fx: ForeignAmount, rateMicros: Long, appCurrency: String): Long =
        convert(fx.amount, fx.currency, rateMicros, appCurrency, fx.feeBps, fx.spreadMicros)
}

/** What the lock/refresh pass decides for one row. Pure: no database, no network. */
object FxRowPlanner {
    data class Change(
        val id: Long,
        val foreign: ForeignAmount?,
        val amount: Long,
        /** True when this change only follows a new live rate (drives the "rate updated" hint). */
        val isLiveMove: Boolean,
    )

    fun plan(
        id: Long,
        date: LocalDate,
        amount: Long,
        fx: ForeignAmount,
        appCurrency: String,
        today: String,
        latest: FxQuote?,
        historical: FxQuote?,
        now: Long,
    ): Change? {
        // The app currency changed to the income's own currency: it is an ordinary row now.
        if (fx.currency == appCurrency) return Change(id, null, fx.amount, isLiveMove = false)
        if (fx.isLocked) return null // Frozen forever.

        return when (val decision = FxLockRule.decide(date.toString(), today, historical)) {
            is FxLockRule.Decision.Lock -> {
                val quote = decision.quote
                val locked = fx.copy(
                    rateMicros = quote.rateMicros,
                    // A market quote keeps its exact time; an ECB rate is a whole day.
                    rateDate = quote.quotedAt ?: FxDay.epoch(quote.date),
                    rateSource = quote.source.key,
                    lockedAt = now,
                )
                Change(id, locked, FxConversion.convert(fx, quote.rateMicros, appCurrency), isLiveMove = false)
            }
            else -> {
                val live = latest ?: return null // Offline: keep the last known amount.
                val converted = FxConversion.convert(fx, live.rateMicros, appCurrency)
                if (converted == amount) null else Change(id, fx, converted, isLiveMove = true)
            }
        }
    }
}

/** Editing a foreign income (docs/fx-salary-plan.md §3). Pure. Port of `FxEditPlanner`. */
object FxEditPlanner {
    data class Result(val foreign: ForeignAmount?, val amount: Long)

    /**
     * @param old the row's conversion before the edit (null for an ordinary row or a new one).
     * @param currency the currency picked in the form (the app currency means "no conversion").
     * @param typedAmount the amount typed, in [currency]'s minor units.
     * @param liveRateMicros newest cached rate for [currency], or a rate typed by hand.
     * @return null when a foreign currency has no rate at all (the form must ask for one).
     */
    fun apply(
        old: ForeignAmount?,
        oldDate: LocalDate,
        newDate: LocalDate,
        currency: String,
        typedAmount: Long,
        appCurrency: String,
        liveRateMicros: Long?,
        liveRateDate: Long?,
        feeBps: Long? = null,
        spreadMicros: Long? = null,
    ): Result? {
        val fee = feeBps?.takeIf { it > 0 }
        val spread = spreadMicros?.takeIf { it > 0 }
        // Set back to the app currency: an ordinary row; the amount is what was typed.
        if (currency == appCurrency) return Result(null, typedAmount)

        if (old != null && old.currency == currency && old.isLocked) {
            val locked = old.rateMicros
            if (oldDate == newDate && locked != null) {
                // New foreign amount × the LOCKED rate. An "amount received" row's rate already
                // holds every fee and difference, so nothing comes off again.
                val keptFee = if (old.isReceivedAmount) null else fee
                val keptSpread = if (old.isReceivedAmount) null else spread
                val kept = old.copy(amount = typedAmount, feeBps = keptFee, spreadMicros = keptSpread)
                return Result(kept, FxConversion.convert(typedAmount, currency, locked, appCurrency, keptFee, keptSpread))
            }
            // Moved to another day: unlock. The next pass locks it again with that day's rate (past)
            // or keeps it live (future). The entry rate stays: only a new currency resets it.
            val live = liveRateMicros ?: old.rateMicros ?: return null
            val unlocked = ForeignAmount(
                currency = currency, amount = typedAmount,
                entryRateMicros = old.entryRateMicros, entryRateDate = old.entryRateDate,
                feeBps = fee, spreadMicros = spread,
            )
            return Result(unlocked, FxConversion.convert(typedAmount, currency, live, appCurrency, fee, spread))
        }

        val live = liveRateMicros ?: return null
        val keepsEntry = old?.currency == currency
        val foreign = ForeignAmount(
            currency = currency, amount = typedAmount,
            entryRateMicros = if (keepsEntry) old?.entryRateMicros ?: live else live,
            entryRateDate = if (keepsEntry) old?.entryRateDate ?: liveRateDate else liveRateDate,
            feeBps = fee, spreadMicros = spread,
        )
        return Result(foreign, FxConversion.convert(typedAmount, currency, live, appCurrency, fee, spread))
    }

    /**
     * "Enter amount received": allowed only after the lock. Stores the implied rate; the badge then
     * compares the entry rate with it, so it includes the bank's spread, IOF and fees.
     */
    fun received(old: ForeignAmount, typedAmount: Long, appCurrency: String): Result? {
        if (!old.isLocked || typedAmount <= 0) return null
        val implied = FxMath.impliedRateMicros(
            typedAmount, old.amount, FxCurrency.digits(old.currency), FxCurrency.digits(appCurrency),
        ) ?: return null
        return Result(old.copy(rateMicros = implied, isReceivedAmount = true), typedAmount)
    }

    /**
     * The foreign half of a series edit, for one row of the series. Port of iOS `applyForeignEdit`:
     * a locked month keeps its money whatever the edit says; set back to the app currency it is an
     * ordinary row; otherwise the row takes the new money, unlocked, keeping the series' entry rate
     * when the currency did not change, at the newest cached rate (or the typed amount offline).
     *
     * @param before the row before the edit.
     * @param edited the row with the edit's other fields applied.
     * @param newForeign the form's conversion (null = app currency).
     */
    fun seriesRow(
        before: Transaction,
        edited: Transaction,
        newForeign: ForeignAmount?,
        appCurrency: String,
        latestRateMicros: (String) -> Long?,
    ): Transaction {
        val old = before.foreign
        if (old == null && newForeign == null) return edited
        if (old != null && old.isLocked) return edited.copy(foreign = old, amount = before.amount)
        if (newForeign == null) return edited.copy(foreign = null)
        var fx = newForeign.unlockedCopy()
        if (old != null && old.currency == newForeign.currency) {
            fx = fx.copy(
                entryRateMicros = old.entryRateMicros ?: newForeign.entryRateMicros,
                entryRateDate = old.entryRateDate ?: newForeign.entryRateDate,
            )
        }
        val amount = latestRateMicros(fx.currency)?.let { FxConversion.convert(fx, it, appCurrency) } ?: edited.amount
        return edited.copy(foreign = fx, amount = amount)
    }
}
