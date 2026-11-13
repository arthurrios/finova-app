package com.arthurrios.finova.domain.importer

enum class ColumnRole {
    Date,
    Description,
    /** One signed column carrying both directions. */
    Amount,
    /** Money out, in a file that splits the two. */
    Debit,
    /** Money in, in a file that splits the two. */
    Credit,
    /** A running balance. Never imported, but it is what proves which column is the amount, and its sign. */
    Balance,
    /** The bank's own category, a hint only. */
    Category,
    DocId,
    /** A D/C marker column. */
    DirectionFlag,
    Ignored,
}

/** Which way the signs run in a single amount column. */
enum class SignConvention {
    /** Negative is money out: the current-account default. */
    NegativeIsExpense,
    /** Positive is money out: the credit-card statement shape. */
    PositiveIsExpense,
    SeparateDebitCredit,
    IndicatorColumn,
}

/** How strongly one aspect of the schema is believed, and why. */
data class SubConfidence(val score: Double, val evidence: String) {
    companion object {
        fun proof(why: String) = SubConfidence(1.0, why)
        fun strong(why: String) = SubConfidence(0.8, why)
        fun weak(why: String) = SubConfidence(0.4, why)
        fun none(why: String) = SubConfidence(0.0, why)
    }
}

data class InferenceConfidence(
    val header: SubConfidence,
    val dateFormat: SubConfidence,
    val numberFormat: SubConfidence,
    val amountShape: SubConfidence,
    val signConvention: SubConfidence,
    val columnRoles: SubConfidence,
) {
    /**
     * The WEAKEST link, not the mean: certain dates and a coin-flip sign must not average into
     * something comfortable. One unresolved aspect can invert a month of the ledger.
     */
    val overall: Double
        get() = listOf(header, dateFormat, numberFormat, amountShape, signConvention, columnRoles).minOf { it.score }

    enum class Band { High, Medium, Low }

    val band: Band
        get() = when {
            overall >= 0.9 -> Band.High
            overall >= 0.6 -> Band.Medium
            else -> Band.Low
        }

    /** The user settled every aspect on the mapping screen, so none can be in doubt any more. */
    fun confirmedByUser() = copy(
        dateFormat = SubConfidence.proof("confirmed by the user"),
        signConvention = SubConfidence.proof("confirmed by the user"),
        numberFormat = SubConfidence.proof("confirmed by the user"),
        columnRoles = SubConfidence.proof("confirmed by the user"),
    )
}

/** Everything needed to turn rows of strings into transactions. Port of ResolvedSchema.swift. */
data class ResolvedSchema(
    val roles: Map<Int, ColumnRole>,
    val hasHeaderRow: Boolean,
    /** Rows dropped before the header: preamble the bank prepends. */
    val preambleRows: Int,
    val dateFormat: DateFormatSpec,
    val numberFormat: NumberFormatSpec,
    val signConvention: SignConvention,
    /**
     * True when the date column also carries the description (`15/07/2026 14:30 COMPRA MERCADO`): the
     * leading date is consumed and the rest becomes the title.
     */
    val dateColumnCarriesDescription: Boolean = false,
) {
    fun column(role: ColumnRole): Int? = roles.entries.filter { it.value == role }.minOfOrNull { it.key }

    val isUsable: Boolean
        get() = column(ColumnRole.Date) != null &&
            (column(ColumnRole.Amount) != null || column(ColumnRole.Debit) != null || column(ColumnRole.Credit) != null)

    /** A role is single-occupancy: giving it to [index] clears it wherever it was. */
    fun withColumn(index: Int, role: ColumnRole): ResolvedSchema {
        val updated = roles.mapValues { (column, assigned) -> if (assigned == role && column != index) ColumnRole.Ignored else assigned }.toMutableMap()
        updated[index] = role
        return copy(roles = updated)
    }

    /** A plain description for the batch record, so history can say how a file was read. */
    fun describe(): String = buildString {
        append("date=").append(dateFormat.pattern)
        append(" decimal=").append(numberFormat.decimalSeparator)
        append(" sign=").append(signConvention.name)
        roles.toSortedMap().forEach { (column, role) -> if (role != ColumnRole.Ignored) append(" ").append(column + 1).append('=').append(role.name) }
    }
}
