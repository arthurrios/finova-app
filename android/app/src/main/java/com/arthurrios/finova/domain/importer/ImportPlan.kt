package com.arthurrios.finova.domain.importer

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import java.time.LocalDate
import java.time.YearMonth
import kotlin.math.abs

data class ImportSource(
    val filename: String,
    val byteCount: Int,
    val sha256: String,
    val encoding: String,
    val dialect: CsvDialect,
    /** The file needed repair to decode. Worth telling the user before rows land. */
    val wasLossy: Boolean,
)

enum class RowWarning {
    /** More than two decimal places, rounded. Money is never rounded silently. */
    AmountRounded,
    /** The decimal separator could only be guessed. */
    AmbiguousNumberFormat,
    DateFarFromOthers,
    /** An `n/m` installment marker: shown, not acted on. */
    InstallmentHintIgnored,
    TitleWasEmpty,
}

sealed interface RowError {
    data class UnparseableDate(val value: String) : RowError
    data class UnparseableAmount(val value: String) : RowError
    data object ZeroAmount : RowError
    data class MissingField(val role: ColumnRole) : RowError
    data object AmountOutOfRange : RowError
}

/** What must be decided before a row can go in. */
enum class RowDecision { AmbiguousSign, DebitAndCreditBothSet, AmbiguousDate }

sealed interface Disposition {
    data object Insert : Disposition
    data class DuplicateExact(val existingId: Long) : Disposition
    data class DuplicateLikely(val existingId: Long, val similarity: Double) : Disposition
    /**
     * A twin earlier in this same file. Both are kept: two identical coffees on one day are an
     * ordinary Tuesday, and collapsing them loses one.
     */
    data class DuplicateInFile(val firstRowId: Int) : Disposition
    data object AlreadyImported : Disposition
    data class NeedsDecision(val decision: RowDecision) : Disposition
    data class Failed(val error: RowError) : Disposition

    /**
     * Whether the row goes in unless the user says otherwise. A likely duplicate is IN by default and
     * an exact one OUT: a false skip silently loses a real transaction, a visible duplicate costs two taps.
     */
    val isIncludedByDefault: Boolean get() = this is Insert || this is DuplicateInFile || this is DuplicateLikely
    val isFailure: Boolean get() = this is Failed
}

data class ParsedRow(val date: LocalDate, val signedCents: Long, val title: CleanedTitle, val bankCategory: String?)

data class ImportRow(
    /** The source line: stable across re-inference, and what the UI shows. */
    val id: Int,
    val rawCells: List<String>,
    /** Over (file hash, line, raw cells): survives re-inference, so user overrides survive a new date format. */
    val fingerprint: String,
    val parsed: ParsedRow?,
    val disposition: Disposition,
    val categorySuggestion: CategorySuggestion?,
    val warnings: List<RowWarning>,
)

/** The whole proposed change, computed without touching the database. Port of ImportPlan.swift. */
data class ImportPlan(
    val source: ImportSource,
    val schema: ResolvedSchema,
    val confidence: InferenceConfidence,
    /** EVERY row in file order, failures included: a row that vanishes is one the user cannot reason about. */
    val rows: List<ImportRow>,
) {
    val failedRows: List<ImportRow> get() = rows.filter { it.disposition.isFailure }
    val duplicateRows: List<ImportRow>
        get() = rows.filter { it.disposition is Disposition.DuplicateExact || it.disposition is Disposition.DuplicateLikely || it.disposition is Disposition.AlreadyImported }
    val undecidedRows: List<ImportRow> get() = rows.filter { it.disposition is Disposition.NeedsDecision }

    /** Applies the user's overrides and gives the final rows. Pure. */
    fun resolve(overrides: ImportOverrides): ResolvedImport {
        val importable = mutableListOf<ImportableRow>()
        var skipped = 0
        var failed = 0
        for (row in rows) {
            val parsed = row.parsed
            if (parsed == null) { failed++; continue }
            val override = overrides.byFingerprint[row.fingerprint]
            if (!overrides.isIncluded(row)) { skipped++; continue }
            val type = override?.type ?: if (parsed.signedCents > 0) TransactionType.Income else TransactionType.Expense
            val date = override?.date ?: parsed.date
            importable += ImportableRow(
                transaction = Transaction(
                    title = override?.title ?: parsed.title.title,
                    category = override?.category ?: row.categorySuggestion?.category ?: TransactionCategory.Miscellaneous,
                    type = type,
                    // A POSITIVE magnitude: direction lives in `type`, and every reader applies it.
                    amount = abs(parsed.signedCents),
                    date = date,
                    budgetMonth = YearMonth.from(date),
                    // A fact that already happened keeps its Saturday: no weekend rule.
                    businessDayRule = BusinessDayRule.Exact,
                ),
                fingerprint = row.fingerprint,
                sourceLine = row.id,
            )
        }
        return ResolvedImport(importable, skipped, failed)
    }
}

/** One row's worth of user intent, layered over what the planner decided. */
data class RowOverride(
    val isIncluded: Boolean? = null,
    val category: TransactionCategory? = null,
    val title: String? = null,
    val type: TransactionType? = null,
    val date: LocalDate? = null,
) {
    val isEmpty: Boolean get() = isIncluded == null && category == null && title == null && type == null && date == null
}

/**
 * The user's edits on the review screen, keyed by FINGERPRINT and never by position: going back to
 * change the date format recomputes the whole plan, and the fingerprint survives that. Overrides for
 * rows absent from the current plan are kept, so going back and forth loses nothing.
 */
data class ImportOverrides(
    val byFingerprint: Map<String, RowOverride> = emptyMap(),
    val includeExactDuplicates: Boolean = false,
    val includeLikelyDuplicates: Boolean = true,
) {
    fun update(fingerprint: String, change: (RowOverride) -> RowOverride): ImportOverrides {
        val next = change(byFingerprint[fingerprint] ?: RowOverride())
        return copy(byFingerprint = if (next.isEmpty) byFingerprint - fingerprint else byFingerprint + (fingerprint to next))
    }

    /** Whether a row goes in. An explicit per-row choice always wins, even forcing a known duplicate in. */
    fun isIncluded(row: ImportRow): Boolean {
        if (row.disposition.isFailure) return false
        val override = byFingerprint[row.fingerprint]
        override?.isIncluded?.let { return it }
        return when (row.disposition) {
            Disposition.Insert, is Disposition.DuplicateInFile -> true
            is Disposition.DuplicateLikely -> includeLikelyDuplicates
            is Disposition.DuplicateExact -> includeExactDuplicates
            Disposition.AlreadyImported -> false
            // Settled by stating the row's direction; otherwise it stays out.
            is Disposition.NeedsDecision -> override?.type != null
            is Disposition.Failed -> false
        }
    }
}

/** A row that survived review, ready to be written. */
data class ImportableRow(val transaction: Transaction, val fingerprint: String, val sourceLine: Int)

data class ResolvedImport(val rows: List<ImportableRow>, val skippedCount: Int, val failedCount: Int)
