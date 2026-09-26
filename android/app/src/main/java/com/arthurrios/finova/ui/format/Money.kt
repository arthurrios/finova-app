package com.arthurrios.finova.ui.format

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import java.math.BigDecimal
import java.text.DecimalFormat
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/** What iOS shows instead of an amount while values are hidden (ValueMask.placeholder). */
const val HiddenValue = "••••••"

/**
 * Money is kept in minor units (cents), like iOS. Port of `Int.currencyString` /
 * `maskedCurrencyString()`.
 */
object Money {
    fun format(cents: Long, currencyCode: String, locale: Locale = Locale.getDefault()): String =
        formatter(currencyCode, locale).format(toMajor(cents, currencyCode))

    fun formatMasked(cents: Long, currencyCode: String, hidden: Boolean, locale: Locale = Locale.getDefault()): String =
        if (hidden) HiddenValue else format(cents, currencyCode, locale)

    /**
     * The amount with a smaller currency symbol, as the transaction rows show it on iOS
     * (`maskedCurrencyAttributedString(symbolFont:font:)`).
     */
    fun annotated(
        cents: Long,
        currencyCode: String,
        symbolStyle: TextStyle,
        hidden: Boolean,
        locale: Locale = Locale.getDefault(),
    ): AnnotatedString {
        if (hidden) return AnnotatedString(HiddenValue)
        val fmt = formatter(currencyCode, locale)
        val text = fmt.format(toMajor(cents, currencyCode))
        val symbol = (fmt as? DecimalFormat)?.decimalFormatSymbols?.currencySymbol
        val start = symbol?.let { text.indexOf(it) } ?: -1
        return buildAnnotatedString {
            if (symbol == null || start < 0) {
                append(text)
            } else {
                append(text.substring(0, start))
                withStyle(SpanStyle(fontSize = symbolStyle.fontSize, fontWeight = symbolStyle.fontWeight)) {
                    append(symbol)
                }
                append(text.substring(start + symbol.length))
            }
        }
    }

    /**
     * Compact form for tight spots: "R$1,5k", "$2.3M" (CurrencyUtils.compactString on iOS). Below
     * a thousand it is the whole amount without cents. The decimal mark follows the language; iOS
     * always writes a point, so pt-BR read "R$1.5k".
     */
    fun compact(cents: Long, currencyCode: String, locale: Locale = Locale.getDefault()): String {
        val currency = Currency.getInstance(currencyCode)
        val amount = toMajor(kotlin.math.abs(cents), currencyCode).toDouble()
        val sign = if (cents < 0) "-" else ""
        val symbol = currency.getSymbol(locale)
        fun num(value: Double, decimals: Int) = String.format(locale, "%.${decimals}f", value)
        return sign + symbol + when {
            amount >= 1_000_000 -> (amount / 1_000_000).let { if (it >= 10) num(it, 0) else num(it, 1) } + "M"
            amount >= 1_000 -> (amount / 1_000).let { if (it >= 100) num(it, 0) else num(it, 1) } + "k"
            else -> num(amount, 0)
        }
    }

    fun compactMasked(cents: Long, currencyCode: String, hidden: Boolean): String =
        if (hidden) HiddenValue else compact(cents, currencyCode)

    private fun formatter(currencyCode: String, locale: Locale): NumberFormat =
        NumberFormat.getCurrencyInstance(locale).apply {
            val currency = Currency.getInstance(currencyCode)
            this.currency = currency
            minimumFractionDigits = currency.defaultFractionDigits.coerceAtLeast(0)
            maximumFractionDigits = currency.defaultFractionDigits.coerceAtLeast(0)
        }

    private fun toMajor(cents: Long, currencyCode: String): BigDecimal {
        val digits = Currency.getInstance(currencyCode).defaultFractionDigits.coerceAtLeast(0)
        return BigDecimal.valueOf(cents, digits)
    }
}

/** Port of `Int.localizedDayOfMonth`: "23rd" in English, "23" elsewhere. */
fun localizedDayOfMonth(day: Int, locale: Locale = Locale.getDefault()): String {
    if (locale.language != "en") return day.toString()
    val suffix = when {
        day % 100 in 11..13 -> "th"
        day % 10 == 1 -> "st"
        day % 10 == 2 -> "nd"
        day % 10 == 3 -> "rd"
        else -> "th"
    }
    return "$day$suffix"
}
