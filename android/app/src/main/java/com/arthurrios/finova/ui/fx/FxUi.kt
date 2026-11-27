package com.arthurrios.finova.ui.fx

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.fx.FxBadgeTone
import com.arthurrios.finova.domain.fx.FxCurrency
import com.arthurrios.finova.domain.fx.FxDay
import com.arthurrios.finova.domain.fx.FxMath
import com.arthurrios.finova.domain.fx.FxQuote
import com.arthurrios.finova.domain.fx.FxSource
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import java.math.BigDecimal
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Currency
import java.util.Locale

/** Text for foreign-currency income. Port of the formatting helpers in ForeignCurrencyService.swift. */
object FxFormat {
    fun symbol(currency: String, locale: Locale = Locale.getDefault()): String =
        runCatching { Currency.getInstance(currency).getSymbol(locale) }.getOrDefault(currency)

    /**
     * `US$ 5,000.00`: the phone's symbol for the currency, the digits in the money's own style
     * (1,000.00), so a dollar amount never reads like a reais one next to it.
     */
    fun amount(amountMinor: Long, currency: String): String {
        val digits = FxCurrency.digits(currency)
        val format = DecimalFormat("#,##0" + if (digits > 0) "." + "0".repeat(digits) else "", DecimalFormatSymbols(Locale.US))
        return symbol(currency) + " " + format.format(BigDecimal.valueOf(amountMinor, digits))
    }

    /** `US$ 1 = R$ 5,7651` */
    fun rate(rateMicros: Long, currency: String, appCurrency: String): String {
        val formatter = NumberFormat.getCurrencyInstance(Locale.getDefault()).apply {
            this.currency = Currency.getInstance(appCurrency)
            minimumFractionDigits = 4
            maximumFractionDigits = 4
        }
        return "${symbol(currency)} 1 = " + formatter.format(BigDecimal.valueOf(rateMicros, 6))
    }

    /** An app-currency value with 2 to 4 decimals ("R$ 0,05", "R$ 0,0525"). */
    fun smallMoney(micros: Long, appCurrency: String, min: Int = 2, max: Int = 4): String =
        NumberFormat.getCurrencyInstance(Locale.getDefault()).apply {
            this.currency = Currency.getInstance(appCurrency)
            minimumFractionDigits = min
            maximumFractionDigits = max
        }.format(BigDecimal.valueOf(micros, 6))

    /** 5651550 → "5,65155" in the phone's format, 2 to 6 decimals, so amount × rate on screen adds up. */
    fun plainRate(micros: Long): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
        minimumFractionDigits = 2
        maximumFractionDigits = 6
    }.format(BigDecimal.valueOf(micros, 6))

    /** 90 → "0,9" in the phone's format (up to 2 decimals). */
    fun fee(bps: Long): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
        minimumFractionDigits = 0
        maximumFractionDigits = 2
    }.format(BigDecimal.valueOf(bps, 2))

    /** Short date for rate labels: 26/11. */
    fun shortDate(epochSeconds: Long): String =
        Instant.ofEpochSecond(epochSeconds).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("dd/MM"))

    fun fullDate(epochSeconds: Long): String =
        Instant.ofEpochSecond(epochSeconds).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern("dd/MM/yyyy"))

    fun shortTime(epochSeconds: Long): String =
        Instant.ofEpochSecond(epochSeconds).atZone(ZoneId.systemDefault())
            .format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(Locale.getDefault()))
}

/** "Market rate · 18:59" for a live quote, "ECB, 26/11" for the fallback. */
@Composable
fun fxSourceText(quote: FxQuote): String {
    val at = quote.quotedAt
    return if (quote.source == FxSource.Market && at != null) {
        stringResource(R.string.fx_source_market, FxFormat.shortTime(at))
    } else {
        stringResource(R.string.fx_hint_ecb, FxDay.epoch(quote.date)?.let(FxFormat::shortDate) ?: quote.date)
    }
}

/** The small Stocks-style pill: tinted background, coloured text, `+8.0%`. Colour means good or bad for the user. */
@Composable
fun FxBadge(tenths: Long, isIncome: Boolean, isLocked: Boolean, modifier: Modifier = Modifier, trailingText: String? = null) {
    val color = when (FxBadgeTone.tone(isIncome, tenths)) {
        FxBadgeTone.Good -> FinovaColors.MainGreen
        FxBadgeTone.Bad -> FinovaColors.MainRed
        FxBadgeTone.Neutral -> FinovaColors.Gray500
    }
    val magnitude = "%.1f".format(Locale.ROOT, kotlin.math.abs(tenths) / 10.0)
    val a11y = when {
        tenths > 0 -> stringResource(R.string.fx_badge_a11y_up, magnitude)
        tenths < 0 -> stringResource(R.string.fx_badge_a11y_down, magnitude)
        else -> stringResource(R.string.fx_badge_a11y_flat)
    }
    Row(verticalAlignment = Alignment.CenterVertically, modifier = modifier) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .clip(RoundedCornerShape(CornerRadius.Small))
                .background(color.copy(alpha = 0.12f))
                .padding(horizontal = 4.dp, vertical = 1.dp)
                .semantics { contentDescription = a11y },
        ) {
            if (isLocked) {
                Icon(Icons.Filled.Lock, contentDescription = null, tint = color, modifier = Modifier.size(8.dp))
                Spacer(Modifier.width(2.dp))
            }
            Text(
                FxMath.formatChange(tenths),
                style = FinovaType.Title2XS.copy(fontSize = 10.sp, fontWeight = FontWeight.Bold),
                color = color,
            )
        }
        if (trailingText != null) {
            Text(" $trailingText", style = FinovaType.TextSM, color = FinovaColors.Gray600)
        }
    }
}

/**
 * The "Rate updated" hint over the dashboard (a toast-like label on iOS; a Material snackbar
 * here), above the add button and inside the safe area.
 */
@Composable
fun FxRateHintHost(hints: kotlinx.coroutines.flow.Flow<FxQuote>, modifier: Modifier = Modifier) {
    val host = androidx.compose.runtime.remember { androidx.compose.material3.SnackbarHostState() }
    val format = stringResource(R.string.fx_rate_updated)
    androidx.compose.runtime.LaunchedEffect(hints) {
        hints.collect { quote ->
            host.showSnackbar(format.format(FxFormat.rate(quote.rateMicros, quote.base, quote.quote)))
        }
    }
    androidx.compose.material3.SnackbarHost(
        host,
        modifier = modifier
            .navigationBarsPadding()
            .padding(bottom = 84.dp),
    )
}
