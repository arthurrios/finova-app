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
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaTheme
import com.arthurrios.finova.ui.theme.Spacing
import kotlinx.coroutines.launch

/** Everything the dashboard can ask its owner to do. */
interface DashboardActions {
    fun onSelectMonth(index: Int) {}
    fun balanceForDay(page: MonthPageUi, day: Int): Long = page.finalBalance ?: 0
    fun onToggleValues() {}
    fun onAddTransaction() {}
    fun onProfile() {}
    fun onNotifications() {}
    fun onAdjustBalance(page: MonthPageUi) {}
    fun onBudgetView(page: MonthPageUi) {}
    fun onMonthSettings(page: MonthPageUi) {}
    fun onDefineBudget(page: MonthPageUi) {}
    fun onFilter(page: MonthPageUi) {}
    fun onTransaction(row: TransactionRowUi) {}
    fun onDeleteTransaction(row: TransactionRowUi) {}
}

/** Port of DashboardView / DashboardViewController layout on iOS. */
@Composable
fun DashboardScreen(state: DashboardUiState, actions: DashboardActions) {
    val pagerState = rememberPagerState(initialPage = state.selectedMonth) { state.months.size }
    val scope = rememberCoroutineScope()
    // iOS always asks before deleting; a swipe or the trash icon only opens the question.
    var pendingDelete by remember { mutableStateOf<TransactionRowUi?>(null) }

    // The pager reports the settled page; the tabs follow it.
    LaunchedEffect(pagerState) {
        snapshotFlow { pagerState.settledPage }.collect { actions.onSelectMonth(it) }
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
                        onRequestDelete = { pendingDelete = it },
                    )
                }
            }
        }
        FloatingActionButton(
            onClick = actions::onAddTransaction,
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

    pendingDelete?.let { row ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.transaction_delete_title)) },
            text = { Text(stringResource(R.string.delete_confirmation)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = null
                    actions.onDeleteTransaction(row)
                }) { Text(stringResource(R.string.alert_delete), color = FinovaColors.MainRed) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.alert_cancel)) }
            },
        )
    }
}

@Composable
private fun MonthPage(
    page: MonthPageUi,
    state: DashboardUiState,
    actions: DashboardActions,
    onRequestDelete: (TransactionRowUi) -> Unit,
) {
    var query by rememberSaveable(page.month) { mutableStateOf("") }
    val rows = remember(page.transactions, query) {
        if (query.isBlank()) page.transactions
        else page.transactions.filter { it.title.contains(query.trim(), ignoreCase = true) }
    }
    LazyColumn(
        contentPadding = PaddingValues(
            start = Spacing.S4, end = Spacing.S4, top = Spacing.S4,
            // Room for the add button so the last row can scroll clear of it.
            bottom = 96.dp,
        ),
        modifier = Modifier.fillMaxSize(),
    ) {
        item {
            MonthCard(
                page = page,
                currencyCode = state.currencyCode,
                valuesHidden = state.valuesHidden,
                balanceForDay = { actions.balanceForDay(page, it) },
                onToggleValues = actions::onToggleValues,
                onAdjustBalance = { actions.onAdjustBalance(page) },
                onBudgetView = { actions.onBudgetView(page) },
                onSettings = { actions.onMonthSettings(page) },
                onDefineBudget = { actions.onDefineBudget(page) },
            )
            Spacer(Modifier.height(Spacing.S4))
            TransactionSearchBar(query = query, onQueryChange = { query = it }, onFilter = { actions.onFilter(page) })
            Spacer(Modifier.height(Spacing.S3))
            TransactionListHeader(count = rows.size)
        }
        if (rows.isEmpty()) {
            item { TransactionEmptyState() }
        } else {
            itemsIndexed(rows, key = { _, row -> row.id }) { index, row ->
                TransactionRow(
                    row = row,
                    currencyCode = state.currencyCode,
                    valuesHidden = state.valuesHidden,
                    isLast = index == rows.lastIndex,
                    onClick = { actions.onTransaction(row) },
                    onDelete = { onRequestDelete(row) },
                )
            }
        }
    }
}

@Preview(showBackground = true, heightDp = 915)
@Composable
private fun DashboardPreview() {
    FinovaTheme { DashboardScreen(DashboardSamples.state(), object : DashboardActions {}) }
}
