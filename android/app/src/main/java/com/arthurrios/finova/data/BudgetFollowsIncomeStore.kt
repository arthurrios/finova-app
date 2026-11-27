package com.arthurrios.finova.data

import android.content.Context
import androidx.core.content.edit
import com.arthurrios.finova.data.repo.FinanceRepository
import com.arthurrios.finova.domain.budget.BudgetFollowsIncome
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.LocalDate
import java.time.YearMonth

/**
 * "Budget follows income" for the signed-in account: its settings (UserDefaults keyed by uid on
 * iOS, preferences keyed by uid here) and the recompute that keeps the budget rows in step with
 * income. Port of the IO side of BudgetFollowsIncomeService.swift.
 */
class BudgetFollowsIncomeService(context: Context, private val uid: () -> String) {
    private val prefs = context.getSharedPreferences("finova_follow_income", Context.MODE_PRIVATE)
    private val mutex = Mutex()

    private val _settings = MutableStateFlow(read())

    /** The current account's settings; screens redraw when they change. */
    val settings: StateFlow<BudgetFollowsIncome.Settings> = _settings

    /** Reads the settings again when another account signed in since. */
    fun reload() = refreshIfAccountChanged()

    private var readFor: String? = null

    private fun refreshIfAccountChanged() {
        if (readFor != uid()) _settings.value = read()
    }

    private fun key(name: String) = "budgetFollowsIncome.$name.${uid()}"

    private fun read(): BudgetFollowsIncome.Settings {
        readFor = uid()
        val percent = prefs.getInt(key("percent"), 100)
        return BudgetFollowsIncome.Settings(
            isEnabled = prefs.getBoolean(key("enabled"), false),
            percent = if (percent in BudgetFollowsIncome.PERCENT_RANGE) percent else 100,
            startMonth = prefs.getInt(key("startMonth"), 0).takeIf { it > 0 }?.let { YearMonth.of(it / 100, it % 100) },
            optedOutMonths = prefs.getStringSet(key("optedOut"), emptySet()).orEmpty()
                .mapNotNull { it.toIntOrNull()?.let { v -> YearMonth.of(v / 100, v % 100) } }.toSet(),
        )
    }

    private fun write(s: BudgetFollowsIncome.Settings) {
        prefs.edit {
            putBoolean(key("enabled"), s.isEnabled)
            putInt(key("percent"), s.percent.coerceIn(BudgetFollowsIncome.PERCENT_RANGE))
            putInt(key("startMonth"), s.startMonth?.let { it.year * 100 + it.monthValue } ?: 0)
            putStringSet(key("optedOut"), s.optedOutMonths.map { (it.year * 100 + it.monthValue).toString() }.toSet())
        }
        readFor = uid()
        _settings.value = s
    }

    private fun current(): BudgetFollowsIncome.Settings {
        refreshIfAccountChanged()
        return _settings.value
    }

    /** Turns it on; `includePastMonths` also applies it to every earlier month with income. */
    suspend fun enable(repository: FinanceRepository, percent: Int, includePastMonths: Boolean, today: LocalDate = LocalDate.now()) {
        val rows = repository.storedRows()
        write(BudgetFollowsIncome.enabled(current(), percent, includePastMonths, rows, YearMonth.from(today)))
        recompute(repository, today)
    }

    /** Turns it off. The budgets already written stay, as fixed budgets. */
    fun disable() = write(current().copy(isEnabled = false))

    suspend fun setPercent(repository: FinanceRepository, percent: Int) {
        write(current().copy(percent = percent))
        recompute(repository)
    }

    /** The months keep a fixed budget (the user typed one, or deleted its budget). */
    fun optOut(months: Collection<YearMonth>) {
        val s = current()
        if (!s.isEnabled || months.isEmpty()) return
        write(s.copy(optedOutMonths = s.optedOutMonths + months))
    }

    /** The month follows income again. */
    suspend fun optIn(repository: FinanceRepository, month: YearMonth) {
        write(current().copy(optedOutMonths = current().optedOutMonths - month))
        recompute(repository)
    }

    /** Brings every following month's budget in line with its income. Returns the months changed. */
    suspend fun recompute(repository: FinanceRepository, today: LocalDate = LocalDate.now()): Set<YearMonth> = mutex.withLock {
        val s = current()
        if (!s.isEnabled) return@withLock emptySet()
        val rows = repository.storedRows()
        val existing = repository.budgets.first().associate { it.month to it.amount }
        val targets = BudgetFollowsIncome.targets(rows, s, existing, YearMonth.from(today))
        if (targets.isNotEmpty()) repository.setBudgetAmounts(targets)
        targets.keys
    }
}
