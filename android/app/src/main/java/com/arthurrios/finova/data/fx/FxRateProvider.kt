package com.arthurrios.finova.data.fx

import com.arthurrios.finova.domain.fx.FxMath
import com.arthurrios.finova.domain.fx.FxQuote
import com.arthurrios.finova.domain.fx.FxSource
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Live rates come from AwesomeAPI (market rate), with Frankfurter (European Central Bank reference
 * rates) as the fallback. Neither needs an API key; only currency codes and dates are sent.
 * Port of FxRateProvider.swift.
 */
interface FxRateProvider {
    /** The newest published rate. */
    suspend fun latest(base: String, quote: String): FxQuote

    /** The last published rate on or before [day] ("yyyy-MM-dd"). */
    suspend fun historical(base: String, quote: String, day: String): FxQuote
}

class FxProviderException(message: String) : IOException(message)

/** A plain GET with short timeouts. Runs on the caller's (IO) thread. */
internal fun httpGet(url: String): String {
    val connection = URL(url).openConnection() as HttpURLConnection
    return try {
        connection.connectTimeout = 10_000
        connection.readTimeout = 15_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")
        if (connection.responseCode !in 200..299) throw FxProviderException("HTTP ${connection.responseCode}")
        connection.inputStream.bufferedReader().use { it.readText() }
    } finally {
        connection.disconnect()
    }
}

/** ECB reference rates through Frankfurter. */
class FrankfurterRateProvider(
    private val baseUrl: String = "https://api.frankfurter.dev/v1/",
    private val get: (String) -> String = ::httpGet,
) : FxRateProvider {
    override suspend fun latest(base: String, quote: String) = fetch("latest", base, quote)

    override suspend fun historical(base: String, quote: String, day: String) = fetch(day, base, quote)

    private fun fetch(path: String, base: String, quote: String): FxQuote =
        parse(get("$baseUrl$path?base=$base&symbols=$quote"), base, quote)

    companion object {
        /**
         * `{"amount":1.0,"base":"USD","date":"2026-11-20","rates":{"BRL":5.938}}`. The number is
         * read from the raw text, so 5.7651 never becomes 5.76509999.
         */
        fun parse(text: String, base: String, quote: String): FxQuote {
            val date = Regex(""""date"\s*:\s*"([0-9-]+)"""").find(text)?.groupValues?.get(1)
                ?: throw FxProviderException("No date")
            val rate = Regex(""""$quote"\s*:\s*([0-9.eE+-]+)""").find(text)?.groupValues?.get(1)?.toBigDecimalOrNull()
                ?: throw FxProviderException("No rate")
            return FxQuote(base, quote, date, FxMath.micros(rate), FxSource.Ecb)
        }
    }
}

/** The live market rate (AwesomeAPI), updated every few minutes. */
class AwesomeRateProvider(
    private val baseUrl: String = "https://economia.awesomeapi.com.br/json/",
    private val zone: () -> ZoneId = { ZoneId.systemDefault() },
    private val get: (String) -> String = ::httpGet,
) : FxRateProvider {
    /** `GET /json/last/USD-BRL` → `{"USDBRL":{"bid":"5.6513","ask":"5.6518","timestamp":"1795728610",...}}` */
    override suspend fun latest(base: String, quote: String): FxQuote {
        val text = get("${baseUrl}last/$base-$quote")
        val entry = Regex(""""$base$quote"\s*:\s*(\{[^{}]*\})""").find(text)?.groupValues?.get(1)
            ?: throw FxProviderException("No rate")
        return quote(entry, base, quote, zone())
    }

    /**
     * The day's closing rate: the newest quote on or before [day]. Asks for the week up to [day],
     * because a weekend or holiday has no quote of its own.
     */
    override suspend fun historical(base: String, quote: String, day: String): FxQuote {
        val dayDate = runCatching { LocalDate.parse(day) }.getOrNull() ?: throw FxProviderException("Bad day")
        val compact = DateTimeFormatter.BASIC_ISO_DATE
        val text = get(
            "${baseUrl}daily/$base-$quote/10?start_date=${dayDate.minusDays(6).format(compact)}&end_date=${dayDate.format(compact)}"
        )
        val zone = zone()
        val quotes = Regex("""\{[^{}]*\}""").findAll(text)
            .mapNotNull { runCatching { quote(it.value, base, quote, zone) }.getOrNull() }
            .filter { it.date <= day }
            .toList()
        return quotes.maxByOrNull { it.quotedAt ?: 0 } ?: throw FxProviderException("No rate")
    }

    companion object {
        private fun field(entry: String, name: String): String? =
            Regex(""""$name"\s*:\s*"([^"]*)"""").find(entry)?.groupValues?.get(1)

        /**
         * Numbers arrive as strings ("5.6513"), so BigDecimal reads them exactly. The rate is the
         * mid price, (bid + ask) / 2; without an ask (the daily history sometimes omits it) the bid.
         */
        fun quote(entry: String, base: String, quote: String, zone: ZoneId): FxQuote {
            val bid = field(entry, "bid")?.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }
                ?: throw FxProviderException("No bid")
            val stamp = field(entry, "timestamp")?.toLongOrNull() ?: throw FxProviderException("No time")
            val ask = field(entry, "ask")?.toBigDecimalOrNull()?.takeIf { it.signum() > 0 }
            val mid = ask?.let { bid.add(it).divide(java.math.BigDecimal(2)) } ?: bid
            val day = Instant.ofEpochSecond(stamp).atZone(zone).toLocalDate().toString()
            return FxQuote(base, quote, day, FxMath.micros(mid), FxSource.Market, stamp)
        }
    }
}

/** Tries the market first and falls back to the ECB, so the app never shows nothing. */
class FallbackRateProvider(private val primary: FxRateProvider, private val fallback: FxRateProvider) : FxRateProvider {
    override suspend fun latest(base: String, quote: String): FxQuote =
        try { primary.latest(base, quote) } catch (_: Exception) { fallback.latest(base, quote) }

    override suspend fun historical(base: String, quote: String, day: String): FxQuote =
        try { primary.historical(base, quote, day) } catch (_: Exception) { fallback.historical(base, quote, day) }
}
