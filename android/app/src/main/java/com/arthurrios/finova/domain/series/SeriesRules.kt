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

/** What the user picks when editing one row of a recurring series. Port of RecurringEditOption. */
enum class SeriesEditOption { ThisOnly, ThisAndLater, All }

/**
 * The rows an edit rewrites. When the series splits: the old parent stops repeating, and the
 * months the user deleted from the split point on move to the new parent.
 */
data class SeriesEdit(
    val updates: List<Transaction>,
    val stopRepeating: Set<Long> = emptySet(),
    val moveExclusions: ExclusionMove? = null,
)

/** Exclusions of series [fromParent] at or after [fromSlot] now belong to series [toParent]. */
data class ExclusionMove(val fromParent: Long, val toParent: Long, val fromSlot: YearMonth)

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
    /** Paid with this card; null means cash or debit. */
    val creditCardId: Long? = null,
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
            creditCardId = draft.creditCardId,
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
                // The repository moves card installments onto their statements' due dates.
                creditCardId = draft.creditCardId,
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

    // ---- Editing -------------------------------------------------------------------------

    /** A one-off edited in place: the picked date moves by the rule, and it counts where it lands. */
    fun editOneOff(row: Transaction, draft: TransactionDraft): Transaction {
        val date = BusinessDayAdjuster.adjust(draft.date, draft.rule)
        return row.copy(
            title = draft.title,
            category = draft.category,
            type = draft.type,
            amount = draft.amount,
            date = date,
            budgetMonth = YearMonth.from(date),
            businessDayRule = draft.rule,
            unadjustedDate = draft.date,
            seriesPeriod = YearMonth.from(date),
            creditCardId = draft.creditCardId,
            statementId = keptStatement(row, draft.creditCardId, draft.date),
            isStatementOverridden = row.isStatementOverridden && draft.creditCardId == row.creditCardId,
        )
    }

    /**
     * A card row keeps its statement only while its card and picked date stay the same; otherwise
     * the repository routes it again, as iOS reassigns it on edit.
     */
    private fun keptStatement(row: Transaction, cardId: Long?, picked: LocalDate): Long? =
        row.statementId.takeIf { cardId != null && cardId == row.creditCardId && picked == row.unadjusted }

    /**
     * Port of `editRecurringTransactionsFromDate`: each chosen occurrence takes the new title,
     * category, type, amount and rule. A new day moves every chosen occurrence to that day inside its
     * own month (clamped, never spilling into the next month).
     *
     * One change over iOS: "this and later" from a month after the first splits the series there.
     * The chosen month becomes the parent of a new series and the old one stops repeating, so the
     * months generated later copy the new values; on iOS they kept copying the old parent.
     */
    fun editRecurring(target: Transaction, draft: TransactionDraft, option: SeriesEditOption, rows: List<Transaction>): SeriesEdit {
        val parentId = seriesId(target)
        val members = rows.filter { it.id == parentId || it.parentTransactionId == parentId }
        val parent = members.firstOrNull { it.id == parentId } ?: target
        val chosen = when (option) {
            SeriesEditOption.ThisOnly -> members.filter { it.id == target.id }
            SeriesEditOption.ThisAndLater -> members.filter { it.slot >= target.slot }
            SeriesEditOption.All -> members
        }.sortedBy { it.slot }
        val anchorDay = parent.unadjusted.dayOfMonth
        val newDay = draft.date.dayOfMonth

        val rewritten = chosen.map { row ->
            val keepDates = newDay == anchorDay && draft.rule == row.businessDayRule && row.budgetMonth == row.slot
            val base = row.copy(
                title = draft.title,
                category = draft.category,
                type = draft.type,
                amount = draft.amount,
                businessDayRule = draft.rule,
                creditCardId = draft.creditCardId,
                statementId = row.statementId.takeIf { draft.creditCardId != null && draft.creditCardId == row.creditCardId },
            )
            if (keepDates) base
            else {
                val unadjusted = OccurrenceDates.occurrence(newDay, row.slot)
                base.copy(
                    date = BusinessDayAdjuster.adjust(unadjusted, draft.rule),
                    unadjustedDate = unadjusted,
                    budgetMonth = row.slot,
                    seriesPeriod = row.slot,
                    // A new day can fall in another billing cycle.
                    statementId = base.statementId.takeIf { unadjusted == row.unadjusted },
                )
            }
        }

        val splits = option == SeriesEditOption.ThisAndLater && chosen.none { it.id == parentId }
        if (!splits) return SeriesEdit(rewritten)
        val head = rewritten.first()
        // The new part repeats only if the series still did: a series the user already stopped
        // must not start filling months again.
        val newSeries = rewritten.map { row ->
            if (row.id == head.id) row.copy(isRecurring = parent.isRecurring, parentTransactionId = row.id)
            else row.copy(parentTransactionId = head.id)
        }
        return SeriesEdit(
            updates = newSeries,
            stopRepeating = setOf(parentId),
            moveExclusions = ExclusionMove(fromParent = parentId, toParent = head.id, fromSlot = head.slot),
        )
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
