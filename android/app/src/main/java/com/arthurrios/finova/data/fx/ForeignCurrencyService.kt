package com.arthurrios.finova.data.fx

import android.content.Context
import androidx.core.content.edit
import androidx.room.withTransaction
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.repo.toDomain
import com.arthurrios.finova.domain.fx.ForeignAmount
import com.arthurrios.finova.domain.fx.FxQuote
import com.arthurrios.finova.domain.fx.FxRowPlanner
import com.arthurrios.finova.domain.fx.FxSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.LocalDate

/**
 * Saved quotes and the provider defaults. iOS keeps quotes in an `FxRates` table and the defaults
 * in UserDefaults; here both live in one small preferences file. Rates are not account data, so
 * one file serves every account on the phone, like the iOS defaults.
 */
class FxStore(context: Context) {
    private val prefs = context.getSharedPreferences("finova_fx", Context.MODE_PRIVATE)

    data class Cached(val quote: FxQuote, val fetchedAt: Long)

    fun cached(base: String, quote: String, requested: String): Cached? {
        val raw = prefs.getString(key(base, quote, requested), null) ?: return null
        val parts = raw.split(";")
        if (parts.size < 5) return null
        return Cached(
            FxQuote(
                base = base,
                quote = quote,
                date = parts[0],
                rateMicros = parts[1].toLongOrNull() ?: return null,
                source = FxSource.fromKey(parts[2]) ?: FxSource.Ecb,
                quotedAt = parts[3].toLongOrNull(),
            ),
            fetchedAt = parts[4].toLongOrNull() ?: 0,
        )
    }

    fun store(quote: FxQuote, requested: String, fetchedAt: Long) = prefs.edit {
        putString(
            key(quote.base, quote.quote, requested),
            listOf(quote.date, quote.rateMicros, quote.source.key, quote.quotedAt ?: "", fetchedAt).joinToString(";"),
        )
    }

    /** The provider difference saved as the default for one currency, in micros. */
    fun providerDiffMicros(currency: String): Long = prefs.getLong("fxProviderDiffMicros.$currency", 0)

    /** The provider fee saved as the default for one currency, in basis points. */
    fun providerFeeBps(currency: String): Long = prefs.getLong("fxProviderFeeBps.$currency", 0)

    fun saveDefaults(currency: String, diffMicros: Long, feeBps: Long) = prefs.edit {
        putLong("fxProviderDiffMicros.$currency", diffMicros)
        putLong("fxProviderFeeBps.$currency", feeBps)
    }

    var lastRateHintAt: Long
        get() = prefs.getLong("fxLastRateHintAt", 0)
        set(value) = prefs.edit { putLong("fxLastRateHintAt", value) }

    private fun key(base: String, quote: String, requested: String) = "rate|$base|$quote|$requested"
}

/**
 * Keeps foreign-currency income converted: live before payday, locked on payday. Port of
 * ForeignCurrencyService.swift. Runs when the app comes to the front, when the dashboard opens,
 * and after a foreign income is saved.
 */
class ForeignCurrencyService(
    val store: FxStore,
    private val database: () -> FinovaDatabase,
    private val appCurrencyCode: () -> String,
    private val provider: FxRateProvider = FallbackRateProvider(AwesomeRateProvider(), FrankfurterRateProvider()),
    private val nowSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
    private val today: () -> LocalDate = { LocalDate.now() },
) {
    val appCurrency: String get() = appCurrencyCode()

    private val mutex = Mutex()

    private val _hints = MutableSharedFlow<FxQuote>(extraBufferCapacity = 1)

    /** A refresh moved live foreign income to a new rate; the dashboard says so, at most once an hour. */
    val rateHints: SharedFlow<FxQuote> = _hints

    private val _version = MutableStateFlow(0)

    /** Bumped whenever a new live quote is saved, so rows and Details re-read their badge. */
    val quotesVersion: StateFlow<Int> = _version

    /** The newest saved quote for [currency] → app currency, however old. */
    fun cachedLatest(currency: String): FxQuote? =
        store.cached(currency, appCurrency, "latest")?.quote?.takeIf { currency != appCurrency }

    /** Micros of [cachedLatest], for the repository's new recurring months. */
    fun cachedLatestMicros(currency: String): Long? = cachedLatest(currency)?.rateMicros

    /**
     * Newest rate for [currency]. Uses the saved one unless it is older than five minutes. Offline,
     * it returns the saved quote however old: good enough to show, never to lock.
     */
    suspend fun latest(currency: String, force: Boolean = false): FxQuote? = withContext(Dispatchers.IO) {
        val base = currency
        val quote = appCurrency
        if (base == quote) return@withContext null
        val saved = store.cached(base, quote, "latest")
        if (!force && saved != null && nowSeconds() - saved.fetchedAt < LATEST_MAX_AGE_SECONDS) return@withContext saved.quote
        try {
            provider.latest(base, quote).also {
                store.store(it, "latest", nowSeconds())
                _version.value++
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            saved?.quote
        }
    }

    /**
     * A live quote that may freeze a payday row: fetched within five minutes and dated payday
     * itself. A stale offline quote, or yesterday's ECB rate, returns null and the row stays live.
     */
    private fun lockableLatest(currency: String, payday: String): FxQuote? {
        val saved = store.cached(currency, appCurrency, "latest") ?: return null
        if (nowSeconds() - saved.fetchedAt >= LATEST_MAX_AGE_SECONDS || saved.quote.date != payday) return null
        return saved.quote
    }

    /** The closing rate of [day]. Only past days are saved: today's close keeps moving. */
    private suspend fun historical(currency: String, day: String): FxQuote? {
        val key = "close:$day"
        store.cached(currency, appCurrency, key)?.let { return it.quote }
        return try {
            provider.historical(currency, appCurrency, day).also {
                if (day < today().toString()) store.store(it, key, nowSeconds())
            }
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (_: Exception) {
            null
        }
    }

    /** Locks every due row and moves every live row to the newest rate. */
    suspend fun refresh(force: Boolean = false) {
        if (!mutex.tryLock()) return
        try {
            withContext(Dispatchers.IO) { runPass(force) }
        } finally {
            mutex.unlock()
        }
    }

    private suspend fun runPass(force: Boolean) {
        val db = database()
        val app = appCurrency
        // Foreign rows the pass may still change: live ones, plus any whose currency is now the app's.
        val rows = db.transactions().getAll().map { it.toDomain() }
            .filter { row -> row.foreign?.let { !it.isLocked || it.currency == app } == true }
        if (rows.isEmpty()) return

        val todayText = today().toString()
        val latestByCurrency = mutableMapOf<String, FxQuote>()
        for (currency in rows.mapNotNull { it.foreign?.currency }.toSet() - app) {
            latest(currency, force)?.let { latestByCurrency[currency] = it }
        }
        val historicalByKey = mutableMapOf<String, FxQuote>()
        for (row in rows) {
            val fx = row.foreign ?: continue
            if (fx.currency == app) continue
            val payday = row.date.toString()
            if (payday > todayText) continue
            val key = "${fx.currency}|$payday"
            if (key in historicalByKey) continue
            val answer = if (payday == todayText) lockableLatest(fx.currency, payday) else historical(fx.currency, payday)
            if (answer != null) historicalByKey[key] = answer
        }

        val stamp = nowSeconds()
        val changes = rows.mapNotNull { row ->
            val fx = row.foreign ?: return@mapNotNull null
            FxRowPlanner.plan(
                id = row.id, date = row.date, amount = row.amount, fx = fx, appCurrency = app, today = todayText,
                latest = latestByCurrency[fx.currency], historical = historicalByKey["${fx.currency}|${row.date}"],
                now = stamp,
            )
        }
        if (changes.isEmpty()) return
        db.withTransaction { changes.forEach { write(db, it.id, it.foreign, it.amount) } }

        val moved = changes.firstOrNull { it.isLiveMove }?.foreign?.currency?.let { latestByCurrency[it] }
        if (moved != null && stamp - store.lastRateHintAt >= RATE_HINT_MIN_INTERVAL_SECONDS) {
            store.lastRateHintAt = stamp
            _hints.tryEmit(moved)
        }
    }

    /** Saves one row's conversion (an "amount received", for one). */
    suspend fun save(id: Long, foreign: ForeignAmount?, amount: Long) = withContext(Dispatchers.IO) {
        write(database(), id, foreign, amount)
    }

    private suspend fun write(db: FinovaDatabase, id: Long, fx: ForeignAmount?, amount: Long) {
        db.transactions().updateForeign(
            id = id, amount = amount, currency = fx?.currency, fxAmount = fx?.amount, rateMicros = fx?.rateMicros,
            rateDate = fx?.rateDate, lockedAt = fx?.lockedAt, entryRateMicros = fx?.entryRateMicros,
            entryRateDate = fx?.entryRateDate, isReceived = fx?.isReceivedAmount ?: false,
            rateSource = fx?.rateSource, feeBps = fx?.feeBps, spreadMicros = fx?.spreadMicros,
        )
    }

    companion object {
        /** The live quote is refreshed at most this often (and on every return to the front). */
        const val LATEST_MAX_AGE_SECONDS = 5 * 60L

        /** The "Rate updated" hint shows at most once an hour: the market moves all day. */
        const val RATE_HINT_MIN_INTERVAL_SECONDS = 60 * 60L
    }
}
