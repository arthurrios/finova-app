package com.arthurrios.finova.ui.budgets

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.Budget
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.MonthYearPickerDialog
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth
import java.time.format.DateTimeFormatter

private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)
private val MonthFormat = DateTimeFormatter.ofPattern("MM/yyyy")

/** Port of BudgetsView / BudgetsViewController on iOS 1.5.2 (the Tags link comes with allocations). */
@Composable
fun BudgetsScreen(viewModel: BudgetsViewModel, onBack: () -> Unit) {
    val budgets by viewModel.budgets.collectAsStateWithLifecycle()
    val hidden by viewModel.valuesHidden.collectAsStateWithLifecycle()
    val pending by viewModel.pendingOverwrite.collectAsStateWithLifecycle()
    val focusManager = LocalFocusManager.current

    var month by rememberSaveable { mutableStateOf(viewModel.initialMonth) }
    var amount by rememberSaveable { mutableStateOf(0L) }
    var showErrors by rememberSaveable { mutableStateOf(false) }
    var showPicker by rememberSaveable { mutableStateOf(false) }
    var pendingDelete by rememberSaveable { mutableStateOf<YearMonth?>(null) }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.budgets_header_title),
            subtitle = stringResource(R.string.budgets_header_subtitle),
            onBack = onBack,
            trailing = {
                RoundIconButton(onClick = viewModel::toggleValues) {
                    Icon(
                        painterResource(if (hidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
                        contentDescription = stringResource(if (hidden) R.string.month_card_show_values else R.string.month_card_hide_values),
                        modifier = Modifier.size(24.dp),
                    )
                }
            },
        )
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = Spacing.S4, end = Spacing.S4, top = Spacing.S4)
                .navigationBarsPadding()
                .padding(bottom = Spacing.S4),
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
        ) {
            // New budget
            Column(Modifier.fillMaxWidth().clip(CardShape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, CardShape)) {
                CardHeader(stringResource(R.string.budgets_new_header_title))
                HorizontalDivider(color = FinovaColors.Gray300)
                Column(Modifier.padding(Spacing.S5), verticalArrangement = Arrangement.spacedBy(Spacing.S4)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S5)) {
                        FinovaTextField(
                            value = month?.format(MonthFormat).orEmpty(),
                            onValueChange = {},
                            placeholder = stringResource(R.string.budgets_input_month_year),
                            isError = showErrors && month == null,
                            leadingIcon = R.drawable.ic_calendar,
                            onClick = {
                                focusManager.clearFocus()
                                showPicker = true
                            },
                            modifier = Modifier.weight(1f),
                        )
                        CurrencyTextField(
                            cents = amount,
                            onCentsChange = { amount = it },
                            currencyCode = viewModel.currencyCode,
                            isError = showErrors && amount <= 0,
                            modifier = Modifier.weight(1f),
                        )
                    }
                    FinovaButton(
                        text = stringResource(R.string.budgets_save),
                        onClick = {
                            focusManager.clearFocus()
                            showErrors = true
                            val picked = month ?: return@FinovaButton
                            if (amount <= 0) return@FinovaButton
                            if (viewModel.save(picked, amount)) {
                                month = null
                                amount = 0
                                showErrors = false
                            }
                        },
                    )
                }
            }

            // Registered budgets: only the rows scroll, like the iOS table.
            Column(Modifier.fillMaxWidth().weight(1f, fill = false)) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(topStart = CornerRadius.ExtraLarge, topEnd = CornerRadius.ExtraLarge))
                        .background(FinovaColors.Gray100)
                        .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(topStart = CornerRadius.ExtraLarge, topEnd = CornerRadius.ExtraLarge)),
                ) { CardHeader(stringResource(R.string.budgets_table_header_title)) }
                val bottomShape = RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge)
                Box(Modifier.fillMaxWidth().clip(bottomShape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, bottomShape)) {
                    if (budgets.isEmpty()) {
                        Text(
                            stringResource(R.string.budgets_empty_state_description),
                            style = FinovaType.TextXS, color = FinovaColors.Gray500,
                            modifier = Modifier.padding(Spacing.S5),
                        )
                    } else {
                        LazyColumn {
                            itemsIndexed(budgets, key = { _, it -> it.month.toString() }) { index, budget ->
                                if (index > 0) HorizontalDivider(color = FinovaColors.Gray300)
                                BudgetRow(budget, viewModel.currencyCode, hidden, onDelete = { pendingDelete = budget.month })
                            }
                        }
                    }
                }
            }
        }
    }

    if (showPicker) {
        MonthYearPickerDialog(
            initial = month ?: YearMonth.now(),
            onPick = {
                month = it
                showPicker = false
            },
            onDismiss = { showPicker = false },
        )
    }
    pending?.let {
        AlertDialog(
            onDismissRequest = viewModel::cancelOverwrite,
            title = { Text(stringResource(R.string.budgets_alert_exists_title)) },
            text = { Text(stringResource(R.string.budgets_alert_exists_description)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.confirmOverwrite()
                    month = null
                    amount = 0
                    showErrors = false
                }) { Text(stringResource(R.string.alert_update)) }
            },
            dismissButton = { TextButton(onClick = viewModel::cancelOverwrite) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    pendingDelete?.let { target ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.budget_delete_title)) },
            text = { Text(stringResource(R.string.delete_confirmation)) },
            confirmButton = {
                TextButton(onClick = {
                    viewModel.delete(target)
                    pendingDelete = null
                }) { Text(stringResource(R.string.alert_delete), color = FinovaColors.MainRed) }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
}

@Composable
private fun CardHeader(title: String) {
    Box(Modifier.fillMaxWidth().height(44.dp).padding(horizontal = Spacing.S5), contentAlignment = Alignment.CenterStart) {
        Text(title.uppercase(), style = FinovaType.Title2XS, color = FinovaColors.Gray500)
    }
}

/**
 * One month. Past months are dimmed and cannot be deleted, as on iOS (their spending already
 * happened against that limit).
 */
@Composable
private fun BudgetRow(budget: Budget, currencyCode: String, hidden: Boolean, onDelete: () -> Unit) {
    val names = stringArrayResource(R.array.month_long)
    val isPast = budget.month < YearMonth.now()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .alpha(if (isPast) 0.45f else 1f)
            .padding(start = Spacing.S5, end = Spacing.S2, top = Spacing.S2, bottom = Spacing.S2)
            .height(40.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(painterResource(R.drawable.ic_calendar), contentDescription = null, tint = FinovaColors.Gray700, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.S4))
        Text(names[budget.month.monthValue - 1], style = FinovaType.TitleMD, color = FinovaColors.Gray700)
        Spacer(Modifier.width(Spacing.S2))
        Text(budget.month.year.toString(), style = FinovaType.TextSM, color = FinovaColors.Gray500)
        Spacer(Modifier.weight(1f))
        Text(Money.annotated(budget.amount, currencyCode, FinovaType.TextXS, hidden), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
        if (isPast) {
            Spacer(Modifier.width(48.dp))
        } else {
            IconButton(onClick = onDelete) {
                Icon(painterResource(R.drawable.ic_trash), contentDescription = stringResource(R.string.delete_action_label),
                    tint = FinovaColors.MainMagenta, modifier = Modifier.size(Spacing.S4))
            }
        }
    }
}
