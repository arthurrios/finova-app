package com.arthurrios.finova.ui.filter

import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.ui.dashboard.TransactionModeUi
import com.arthurrios.finova.ui.dashboard.TransactionRowUi
import java.text.Normalizer

/**
 * Port of `TransactionFilters` (MonthCarouselCell.swift). An empty set means "any".
 *
 * The day range only counts in Custom mode, and only for the month it was set on: the dashboard
 * keeps a copy without it ([withoutDayFilter]) for every other month, as iOS does.
 */
data class TransactionFilters(
    val categories: Set<TransactionCategory> = emptySet(),
    /** true = income, false = expense. */
    val types: Set<Boolean> = emptySet(),
    val modes: Set<TransactionModeUi> = emptySet(),
    val startDay: Int? = null,
    val endDay: Int? = null,
    val useGlobalFilter: Boolean = true,
) {
    /** A range that covers the whole month does not count as a filter. */
    fun hasDayFilter(daysInMonth: Int): Boolean =
        !useGlobalFilter && startDay != null && endDay != null && !(startDay == 1 && endDay == daysInMonth)

    fun isEmpty(daysInMonth: Int): Boolean =
        categories.isEmpty() && types.isEmpty() && modes.isEmpty() && !hasDayFilter(daysInMonth)

    fun withoutDayFilter(): TransactionFilters = copy(startDay = null, endDay = null)

    /** Port of MonthCarouselCell.applyFilters' per-row test. */
    fun matches(row: TransactionRowUi): Boolean {
        if (categories.isNotEmpty() && row.category !in categories) return false
        if (types.isNotEmpty() && row.isIncome !in types) return false
        if (modes.isNotEmpty() && row.mode !in modes) return false
        val start = if (useGlobalFilter) null else startDay
        val end = if (useGlobalFilter) null else endDay
        if (start != null && end != null) {
            val day = row.date.dayOfMonth
            // Crossed thumbs mean a range that wraps: 20..13 keeps days 20-31 and 1-13.
            val inRange = if (start > end) day >= start || day <= end else day in start..end
            if (!inRange) return false
        }
        return true
    }

    companion object {
        /** Case- and accent-blind, like iOS `normalizedForSearch()`: "cafe" finds "Café". */
        fun normalizeForSearch(text: String): String =
            Normalizer.normalize(text, Normalizer.Form.NFD).replace(Diacritics, "").lowercase()

        private val Diacritics = "\\p{Mn}+".toRegex()
    }
}

/** The rows a month shows for a search text and a set of filters. */
fun List<TransactionRowUi>.filtered(query: String, filters: TransactionFilters): List<TransactionRowUi> {
    val needle = TransactionFilters.normalizeForSearch(query.trim())
    return filter { row ->
        (needle.isEmpty() || TransactionFilters.normalizeForSearch(row.title).contains(needle)) && filters.matches(row)
    }
}

/** What the month card shows while filtering: income adds, expenses subtract. */
fun List<TransactionRowUi>.filteredTotal(): Long = sumOf { if (it.isIncome) it.amount else -it.amount }
