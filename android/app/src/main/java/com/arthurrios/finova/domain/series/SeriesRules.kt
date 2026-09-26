package com.arthurrios.finova.domain.series

import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.Transaction
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionMode
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.time.BusinessDayAdjuster
import com.arthurrios.finova.domain.time.OccurrenceDates
import com.arthurrios.finova.domain.time.SeriesMonths
import java.time.LocalDate
import java.time.YearMonth

/** A recurring occurrence the user removed on its own: (series parent id, slot month). */
data class SeriesExclusion(val parentId: Long, val slot: YearMonth)

/** What the user picks when deleting part of a series. Port of RecurringCleanupOption. */
enum class SeriesDeleteOption { ThisOnly, ThisAndLater, All }

/** Which delete question a row needs. Port of TransactionComplexityType, collapsed. */
enum class SeriesKind { Simple, Recurring, Installments }

/** Rows to remove, occurrences to remember as removed, and parents that stop repeating. */
data class SeriesDeletion(
    val deleteIds: Set<Long>,
    val addExclusions: Set<SeriesExclusion> = emptySet(),
    val clearExclusionsFor: Set<Long> = emptySet(),
    val stopRepeating: Set<Long> = emptySet(),
)

/** What the user typed in the add sheet, before it becomes rows. */
data class TransactionDraft(
    val title: String,
    val category: TransactionCategory,
    val type: TransactionType,
    /** The whole amount; for installments, the total to split. */
    val amount: Long,
    /** The picked date, before any weekend shift. */
    val date: LocalDate,
    val rule: BusinessDayRule = BusinessDayRule.Exact,
)

/**
 * Recurring and installment rules. Ports of RecurringTransactionManager (materialize, cleanup)
 * and AddTransactionModalViewModel (creation) on iOS 1.5.2, as pure functions.
 */
object SeriesRules {

    /** The suffix iOS gives the hidden, zero-amount row that holds an installment series together. */
    const val INSTALLMENT_PARENT_SUFFIX = " - Installment Parent"

    fun kindOf(row: Transaction): SeriesKind = when (row.mode) {
        TransactionMode.Recurring -> SeriesKind.Recurring
        TransactionMode.Installments -> SeriesKind.Installments
        TransactionMode.Normal -> SeriesKind.Simple
    }

    /** The id that holds the row's series together (a recurring parent points at itself). */
    fun seriesId(row: Transaction): Long = row.parentTransactionId ?: row.id

    // ---- Creation -------------------------------------------------------------------------

    /**
     * The first row of a recurring series. The repository inserts it, then points it at its own id
     * (iOS self-links the parent) and generates the months ahead.
     */
    fun recurringParent(draft: TransactionDraft): Transaction {
        val month = YearMonth.from(draft.date)
        return Transaction(
            title = draft.title,
            category = draft.category,
            type = draft.type,
            amount = draft.amount,
            date = BusinessDayAdjuster.adjust(draft.date, draft.rule),
            // iOS files the series under the picked (unadjusted) month.
            budgetMonth = month,
            isRecurring = true,
            businessDayRule = draft.rule,
            unadjustedDate = draft.date,
            seriesPeriod = month,
        )
    }

    /**
     * An installment purchase: a hidden parent of amount 0 and [count] children. The total is split
     * evenly and the remainder goes on the first installment. Children get their parent id when
     * the repository has inserted the parent.
     */
    fun installmentSeries(draft: TransactionDraft, count: Int): Pair<Transaction, List<Transaction>> {
        require(count > 1) { "An installment series needs more than one installment" }
        val startMonth = YearMonth.from(draft.date)
        val each = draft.amount / count
        val remainder = draft.amount % count
        val parent = Transaction(
            title = draft.title + INSTALLMENT_PARENT_SUFFIX,
            category = draft.category,
            type = draft.type,
            amount = 0,
            date = draft.date,
            budgetMonth = startMonth,
            hasInstallments = true,
            originalAmount = draft.amount,
            totalInstallments = count,
        )
        val children = (1..count).map { number ->
            val unadjusted = OccurrenceDates.occurrence(draft.date.dayOfMonth, startMonth.plusMonths(number - 1L))
            val slot = YearMonth.from(unadjusted)
            Transaction(
                title = draft.title,
                category = draft.category,
                type = draft.type,
                amount = if (number == 1) each + remainder else each,
                date = BusinessDayAdjuster.adjust(unadjusted, draft.rule),
                budgetMonth = slot,
                originalAmount = draft.amount,
                installmentNumber = number,
                totalInstallments = count,
                businessDayRule = draft.rule,
                unadjustedDate = unadjusted,
                seriesPeriod = slot,
            )
        }
        return parent to children
    }

    // ---- Materialization -----------------------------------------------------------------

    /**
     * The recurring occurrences missing from the next [SeriesMonths.HORIZON_MONTHS] months. Port of
     * `materializeMissingOccurrences`: a series only generates forward from its parent's slot, one
     * row per slot, skipping slots the user deleted and slots another identical series already fills.
     */
    fun missingOccurrences(rows: List<Transaction>, exclusions: Set<SeriesExclusion>, today: LocalDate): List<Transaction> {
        val thisMonth = YearMonth.from(today)
        val parents = rows.filter { it.isRecurring && (it.parentTransactionId == null || it.parentTransactionId == it.id) }
        val slotsBySeries = rows.filter { it.parentTransactionId != null }
            .groupBy({ it.parentTransactionId!! }, { it.slot })
            .mapValues { it.value.toSet() }
        val occupiedByFingerprint = rows.filter { it.mode == TransactionMode.Recurring }
            .groupBy { fingerprint(it, rows) }
            .mapValues { entry -> entry.value.map { it.slot }.toSet() }

        return parents.flatMap { parent ->
            val owned = slotsBySeries[parent.id].orEmpty() + parent.slot
            val sameSeriesElsewhere = occupiedByFingerprint[fingerprint(parent, rows)].orEmpty()
            val anchorDay = parent.unadjusted.dayOfMonth
            SeriesMonths.seriesMonths(parent.slot, null, thisMonth)
                .filter { it > parent.slot && it !in owned && it !in sameSeriesElsewhere }
                .filterNot { SeriesExclusion(parent.id, it) in exclusions }
                .map { slot ->
                    val unadjusted = OccurrenceDates.occurrence(anchorDay, slot)
                    Transaction(
                        title = parent.title,
                        category = parent.category,
                        type = parent.type,
                        amount = parent.amount,
                        date = BusinessDayAdjuster.adjust(unadjusted, parent.businessDayRule),
                        budgetMonth = slot,
                        parentTransactionId = parent.id,
                        creditCardId = parent.creditCardId,
                        businessDayRule = parent.businessDayRule,
                        unadjustedDate = unadjusted,
                        seriesPeriod = slot,
                    )
                }
        }
    }

    /**
     * Port of SeriesFingerprint: title (trimmed, lowercase), category, type and the anchor day of
     * the series parent. Two series with the same fingerprint must not both fill one month.
     */
    private fun fingerprint(row: Transaction, rows: List<Transaction>): String {
        val parent = rows.firstOrNull { it.id == seriesId(row) } ?: row
        return listOf(row.title.trim().lowercase(), row.category.key, row.type.key, parent.unadjusted.dayOfMonth).joinToString("|")
    }

    // ---- Deletion ------------------------------------------------------------------------

    /**
     * What deleting [target] with [option] does. Port of `cleanupRecurringInstancesFromDate` and
     * `cleanupInstallmentTransactionsFromDate`, with two changes:
     * - "This only" on a recurring parent keeps the row (hidden through an exclusion) so the series
     *   keeps generating; iOS deleted it, which quietly ended the series.
     * - Removed occurrences are remembered for good; iOS kept them in memory, so they came back.
     */
    fun deletion(target: Transaction, option: SeriesDeleteOption, rows: List<Transaction>): SeriesDeletion =
        when (kindOf(target)) {
            SeriesKind.Simple -> SeriesDeletion(deleteIds = setOf(target.id))
            SeriesKind.Recurring -> recurringDeletion(target, option, rows)
            SeriesKind.Installments -> installmentDeletion(target, option, rows)
        }

    private fun recurringDeletion(target: Transaction, option: SeriesDeleteOption, rows: List<Transaction>): SeriesDeletion {
        val parentId = seriesId(target)
        val members = rows.filter { it.id == parentId || it.parentTransactionId == parentId }
        val isParent = target.id == parentId
        return when (option) {
            SeriesDeleteOption.ThisOnly -> SeriesDeletion(
                deleteIds = if (isParent) emptySet() else setOf(target.id),
                addExclusions = setOf(SeriesExclusion(parentId, target.slot)),
            )
            SeriesDeleteOption.ThisAndLater -> {
                val doomed = members.filter { it.slot >= target.slot }.map { it.id }.toSet()
                if (parentId in doomed) {
                    SeriesDeletion(deleteIds = members.map { it.id }.toSet(), clearExclusionsFor = setOf(parentId))
                } else {
                    SeriesDeletion(deleteIds = doomed, stopRepeating = setOf(parentId))
                }
            }
            SeriesDeleteOption.All -> SeriesDeletion(
                deleteIds = members.map { it.id }.toSet(),
                clearExclusionsFor = setOf(parentId),
            )
        }
    }

    private fun installmentDeletion(target: Transaction, option: SeriesDeleteOption, rows: List<Transaction>): SeriesDeletion {
        val parentId = seriesId(target)
        val children = rows.filter { it.parentTransactionId == parentId && it.installmentNumber != null }
        val number = target.installmentNumber ?: 1
        val doomed = when (option) {
            SeriesDeleteOption.ThisOnly -> setOf(target.id)
            SeriesDeleteOption.ThisAndLater -> children.filter { (it.installmentNumber ?: 0) >= number }.map { it.id }.toSet()
            SeriesDeleteOption.All -> children.map { it.id }.toSet()
        }
        // The hidden parent goes once no installment is left.
        val parentGoes = children.all { it.id in doomed } && rows.any { it.id == parentId }
        return SeriesDeletion(deleteIds = if (parentGoes) doomed + parentId else doomed)
    }
}
