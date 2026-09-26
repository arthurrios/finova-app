package com.arthurrios.finova.ui.dashboard

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.HorizontalDivider
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.FloatingActionButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.addtransaction.AddTransactionRequest
import com.arthurrios.finova.ui.addtransaction.AddTransactionSheet
import com.arthurrios.finova.domain.series.SeriesDeleteOption
import com.arthurrios.finova.ui.filter.TransactionFilterSheet
import com.arthurrios.finova.ui.filter.TransactionFilters
import com.arthurrios.finova.ui.filter.filtered
import com.arthurrios.finova.ui.filter.filteredTotal
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaTheme
import com.arthurrios.finova.ui.theme.Spacing
import kotlinx.coroutines.launch
import java.time.YearMonth

/** Everything the dashboard can ask its owner to do. */
interface DashboardActions {
    fun onSelectMonth(index: Int) {}
    fun balanceForDay(page: MonthPageUi, day: Int): Long = page.finalBalance ?: 0
    fun onToggleValues() {}
    fun onSaveTransaction(request: AddTransactionRequest) {}
    fun onProfile() {}
    fun onNotifications() {}
    /** The balance today, which "Adjust balance" calibrates against. */
    fun currentBalanceToday(): Long = 0
    fun onConfirmAdjustBalance(realBalance: Long, appBalance: Long) {}
    fun onBudgetView(page: MonthPageUi) {}
    fun onTransaction(row: TransactionRowUi) {}
    fun onDeleteTransaction(row: TransactionRowUi, option: SeriesDeleteOption = SeriesDeleteOption.ThisOnly) {}
}

/** Port of DashboardView / DashboardViewController layout on iOS. */
@Composable
fun DashboardScreen(
    state: DashboardUiState,
    actions: DashboardActions,
    onOpenBudgets: (YearMonth?) -> Unit = {},
    onOpenTransaction: (Long) -> Unit = {},
    onOpenStatement: (Long) -> Unit = {},
    onCreateCard: () -> Unit = {},
) {
    val pagerState = rememberPagerState(initialPage = state.selectedMonth) { state.months.size }
    val scope = rememberCoroutineScope()
    // iOS always asks before deleting; a swipe or the trash icon only opens the question.
    var pendingDelete by remember { mutableStateOf<TransactionRowUi?>(null) }
    var showAddSheet by rememberSaveable { mutableStateOf(false) }
    var adjustFrom by remember { mutableStateOf<Long?>(null) }
    // Port of DashboardViewController.globalFilters: type, mode and category follow every month.
    var globalFilters by remember { mutableStateOf(TransactionFilters()) }
    // A Custom day range belongs to the month it was set on only, and iOS drops it once that
    // month scrolls away, so it is kept apart with its month.
    var dayFiltered by remember { mutableStateOf<Pair<YearMonth, TransactionFilters>?>(null) }
    var filterFor by remember { mutableStateOf<MonthPageUi?>(null) }
    fun filtersFor(page: MonthPageUi) = dayFiltered?.takeIf { it.first == page.month }?.second ?: globalFilters

    // The pager reports the settled page; the tabs follow it.
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }.collect { index ->
            actions.onSelectMonth(index)
            if (dayFiltered?.first != state.months.getOrNull(index)?.month) dayFiltered = null
        }
    }
    // And when the app picks a month itself (after adding a transaction), the pager goes there.
    LaunchedEffect(state.selectedMonth) {
        if (state.months.isNotEmpty() && pagerState.settledPage != state.selectedMonth) {
            pagerState.animateScrollToPage(state.selectedMonth)
        }
    }

    Box(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        Column(Modifier.fillMaxSize()) {
            DashboardHeader(
                userName = state.userName,
                unreadNotifications = state.unreadNotifications,
                onProfile = actions::onProfile,
                onNotifications = actions::onNotifications,
            )
            if (state.months.isNotEmpty()) {
                Spacer(Modifier.height(Spacing.S3))
                MonthTabs(
                    months = state.months.map { it.month },
                    selected = pagerState.currentPage,
                    onSelect = { scope.launch { pagerState.animateScrollToPage(it) } },
                )
                HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { index ->
                    MonthPage(
                        page = state.months[index],
                        state = state,
                        actions = actions,
                        filters = filtersFor(state.months[index]),
                        onOpenFilter = { filterFor = it },
                        onRequestDelete = { pendingDelete = it },
                        onAdjustBalance = { adjustFrom = actions.currentBalanceToday() },
                        onOpenBudgets = onOpenBudgets,
                        onOpenTransaction = onOpenTransaction,
                        onOpenStatement = onOpenStatement,
                    )
                }
            }
        }
        FloatingActionButton(
            onClick = { showAddSheet = true },
            shape = CircleShape,
            containerColor = FinovaColors.Gray100,
            contentColor = FinovaColors.MainMagenta,
            elevation = FloatingActionButtonDefaults.elevation(defaultElevation = 4.dp),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .navigationBarsPadding()
                .padding(bottom = Spacing.S2),
        ) {
            Icon(painterResource(R.drawable.ic_plus), contentDescription = stringResource(R.string.dashboard_add_transaction))
        }
    }

    adjustFrom?.let { appBalance ->
        AdjustBalanceSheet(
            currentBalance = appBalance,
            currencyCode = state.currencyCode,
            onConfirm = { real ->
                adjustFrom = null
                actions.onConfirmAdjustBalance(real, appBalance)
            },
            onDismiss = { adjustFrom = null },
        )
    }

    if (showAddSheet) {
        AddTransactionSheet(
            currencyCode = state.currencyCode,
            defaultRule = state.defaultBusinessDayRule,
            onSave = {
                showAddSheet = false
                actions.onSaveTransaction(it)
            },
            onDismiss = { showAddSheet = false },
            cards = state.cards,
            onCreateCard = {
                showAddSheet = false
                onCreateCard()
            },
        )
    }

    filterFor?.let { page ->
        val days = page.month.lengthOfMonth()
        TransactionFilterSheet(
            current = filtersFor(page),
            daysInMonth = days,
            onApply = { filters ->
                filterFor = null
                globalFilters = filters.withoutDayFilter()
                dayFiltered = if (filters.hasDayFilter(days)) page.month to filters else null
            },
            onClear = {
                filterFor = null
                globalFilters = TransactionFilters()
                dayFiltered = null
            },
            onDismiss = { filterFor = null },
        )
    }

    pendingDelete?.let { row ->
        DeleteTransactionDialog(
            kind = row.seriesKind,
            onDelete = { option ->
                pendingDelete = null
                actions.onDeleteTransaction(row, option)
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun MonthPage(
    page: MonthPageUi,
    state: DashboardUiState,
    actions: DashboardActions,
    filters: TransactionFilters,
    onOpenFilter: (MonthPageUi) -> Unit,
    onRequestDelete: (TransactionRowUi) -> Unit,
    onAdjustBalance: () -> Unit,
    onOpenBudgets: (YearMonth?) -> Unit,
    onOpenTransaction: (Long) -> Unit,
    onOpenStatement: (Long) -> Unit,
) {
    var query by rememberSaveable(page.month) { mutableStateOf("") }
    val rows = remember(page.transactions, query, filters) { page.transactions.filtered(query, filters) }
    val filterActive = !filters.isEmpty(page.month.lengthOfMonth())
    // iOS swaps the card's balance for the shown rows' total whenever a search or filter is on.
    val filteredTotal = if (filterActive || query.isNotBlank()) rows.filteredTotal() else null
    // Like iOS, the card, the search bar and the list header stay put; only the rows scroll,
    // inside the rounded list box that fills the rest of the page.
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(start = Spacing.S4, end = Spacing.S4, top = Spacing.S4)
            .navigationBarsPadding()
            .padding(bottom = Spacing.S2),
    ) {
        MonthCard(
            page = page,
            currencyCode = state.currencyCode,
            valuesHidden = state.valuesHidden,
            balanceForDay = { actions.balanceForDay(page, it) },
            onToggleValues = actions::onToggleValues,
            onAdjustBalance = onAdjustBalance,
            onBudgetView = { actions.onBudgetView(page) },
            // The gear opens every budget, "Set budget" opens this month's (as on iOS).
            onSettings = { onOpenBudgets(null) },
            onDefineBudget = { onOpenBudgets(page.month) },
            filteredTotal = filteredTotal,
        )
        Spacer(Modifier.height(Spacing.S4))
        TransactionSearchBar(
            query = query,
            onQueryChange = { query = it },
            onFilter = { onOpenFilter(page) },
            filterActive = filterActive,
        )
        Spacer(Modifier.height(Spacing.S3))
        TransactionListHeader(count = rows.size)
        if (rows.isEmpty()) {
            TransactionEmptyState()
        } else {
            TransactionListBox(modifier = Modifier.weight(1f)) {
                LazyColumn(
                    // Room under the last row so it can scroll clear of the add button.
                    contentPadding = PaddingValues(bottom = 72.dp),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(rows, key = { _, row -> row.id }) { index, row ->
                        if (index > 0) HorizontalDivider(color = FinovaColors.Gray300)
                        TransactionRow(
                            row = row,
                            currencyCode = state.currencyCode,
                            valuesHidden = state.valuesHidden,
                            onClick = {
                                val statementId = row.statementId
                                if (row.statementTransactionCount != null && statementId != null) onOpenStatement(statementId)
                                else onOpenTransaction(row.id)
                            },
                            onDelete = { onRequestDelete(row) },
                        )
                    }
                }
            }
        }
    }
}

@Preview(showBackground = true, heightDp = 915)
@Composable
private fun DashboardPreview() {
    FinovaTheme { DashboardScreen(DashboardSamples.state(), object : DashboardActions {}) }
}
