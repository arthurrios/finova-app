package com.arthurrios.finova.domain.importer

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormatSymbols
import java.util.Locale

/**
 * Which separator means what, decided PER COLUMN and never per cell: two rows of one column must not
 * be read under different conventions, or `1.234` is 1234 on one line and 1.23 on the next.
 */
data class NumberFormatSpec(val decimalSeparator: Char, val groupingSeparator: Char?) {
    companion object {
        val PtBR = NumberFormatSpec(',', '.')
        val EnUS = NumberFormatSpec('.', ',')
    }
}

/**
 * Text to cents. Port of AmountParser.swift, with [BigDecimal] where iOS uses `Decimal`: binary
 * floating point cannot hold 1234.56, and a cent lost per row is a ledger that does not reconcile.
 */
object AmountParser {
    data class Parsed(
        /** Signed. Direction is applied again at normalization, where the transaction type carries it. */
        val cents: Long,
        /** More than two decimal places came in. A row warning: money is never rounded silently. */
        val wasRounded: Boolean,
    )

    sealed class Failure : Exception() {
        data object Empty : Failure()
        data class Unparseable(val raw: String) : Failure()
        data object OutOfRange : Failure()
    }

    /** About a hundred million currency units. Past that, a document number was read as an amount. */
    const val MAX_CENTS = 100_000_000_00L

    /** Characters banks put in amount fields that carry no numeric meaning. NBSP is the one that bites. */
    private val Noise = setOf('R', '$', '€', '£', ' ', ' ', ' ', ' ', '−')

    fun parseOrNull(raw: String, format: NumberFormatSpec): Parsed? = try {
        parse(raw, format)
    } catch (_: Failure) {
        null
    }

    fun parse(raw: String, format: NumberFormatSpec): Parsed {
        var text = raw.trim()
        if (text.isEmpty()) throw Failure.Empty
        var negative = false

        // Accounting parentheses: (1.234,56) is a credit.
        if (text.startsWith("(") && text.endsWith(")")) {
            negative = true
            text = text.substring(1, text.length - 1)
        }
        // A trailing D/C marker, only after a digit, so a mis-mapped text column still fails.
        trailingDebitCredit(text)?.let { marker ->
            negative = marker == 'D'
            text = text.dropLast(1).trim()
        }
        // A minus can lead or trail depending on the bank.
        if (text.startsWith("-") || text.startsWith("−")) {
            negative = true
            text = text.drop(1)
        } else if (text.endsWith("-") || text.endsWith("−")) {
            negative = true
            text = text.dropLast(1)
        }
        text = text.removePrefix("+")
        text = text.filterNot { it in Noise }
        if (text.isEmpty()) throw Failure.Empty

        // The column's convention: drop grouping, make the decimal mark a POSIX dot.
        format.groupingSeparator?.let { grouping -> text = text.filterNot { it == grouping } }
        if (format.decimalSeparator != '.') text = text.replace(format.decimalSeparator, '.')

        // Anything else left means this was never a number: a description column mapped as the amount.
        if (!text.all { it.isDigit() || it == '.' || it == 'e' || it == 'E' || it == '+' || it == '-' } || text.none { it.isDigit() }) {
            throw Failure.Unparseable(raw)
        }
        // BigDecimal also reads `1.2345E+3`, which Excel-mangled exports really emit.
        val value = try {
            BigDecimal(text)
        } catch (_: NumberFormatException) {
            throw Failure.Unparseable(raw)
        }
        val scaled = value.movePointRight(2)
        // HALF_UP rounds a tie away from zero, like `NSDecimalRound(.plain)`.
        val rounded = scaled.setScale(0, RoundingMode.HALF_UP)
        val wasRounded = rounded.compareTo(scaled) != 0
        if (rounded.abs() > BigDecimal.valueOf(MAX_CENTS)) throw Failure.OutOfRange
        val cents = rounded.toLong()
        return Parsed(if (negative) -kotlin.math.abs(cents) else cents, wasRounded)
    }

    /**
     * Decides the separator convention for a whole column. Proof first: a value carrying BOTH
     * separators settles it. Failing that, separators followed by exactly two digits (decimal-shaped)
     * against exactly three (grouping-shaped). Returns the spec and whether it was proven.
     */
    fun detectFormat(values: List<String>): Pair<NumberFormatSpec, Boolean> {
        val samples = values.filter { it.isNotBlank() }
        if (samples.isEmpty()) return NumberFormatSpec.PtBR to false
        for (value in samples) {
            if (ProvenPtBR.containsMatchIn(value)) return NumberFormatSpec.PtBR to true
            if (ProvenEnUS.containsMatchIn(value)) return NumberFormatSpec.EnUS to true
        }
        var commaDecimal = 0
        var commaGrouping = 0
        var dotDecimal = 0
        var dotGrouping = 0
        for (value in samples) {
            commaDecimal += CommaTwo.findAll(value).count()
            commaGrouping += CommaThree.findAll(value).count()
            dotDecimal += DotTwo.findAll(value).count()
            dotGrouping += DotThree.findAll(value).count()
        }
        if (commaDecimal > 0 && commaDecimal >= dotDecimal) {
            return NumberFormatSpec(',', '.') to (commaGrouping == 0 || dotGrouping > 0)
        }
        if (dotDecimal > 0) return NumberFormatSpec('.', ',') to (dotGrouping == 0 || commaGrouping > 0)
        // Only grouping-shaped separators (every value is `1.234`): unresolvable from the column, so
        // the phone's locale decides and the caller warns.
        val usesComma = DecimalFormatSymbols.getInstance(Locale.getDefault()).decimalSeparator == ','
        return (if (usesComma) NumberFormatSpec.PtBR else NumberFormatSpec.EnUS) to false
    }

    private val ProvenPtBR = Regex("""^[^\d]*-?\d{1,3}(\.\d{3})+,\d{1,2}[^\d]*$""")
    private val ProvenEnUS = Regex("""^[^\d]*-?\d{1,3}(,\d{3})+\.\d{1,2}[^\d]*$""")
    private val CommaTwo = Regex(""",\d{2}(?!\d)""")
    private val CommaThree = Regex(""",\d{3}(?!\d)""")
    private val DotTwo = Regex("""\.\d{2}(?!\d)""")
    private val DotThree = Regex("""\.\d{3}(?!\d)""")

    /** 'D' or 'C' when the value ends in a debit/credit marker right after a digit. */
    private fun trailingDebitCredit(text: String): Char? {
        val last = text.lastOrNull()?.uppercaseChar() ?: return null
        if (last != 'D' && last != 'C') return null
        val before = text.dropLast(1).trim().lastOrNull() ?: return null
        return if (before.isDigit()) last else null
    }
}
