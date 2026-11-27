package com.arthurrios.finova.ui.budgets

import androidx.compose.runtime.remember
import androidx.compose.foundation.layout.heightIn
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId
import com.arthurrios.finova.domain.coachmarks.CoachMarkEvent
import com.arthurrios.finova.domain.coachmarks.CoachMarkTarget
import com.arthurrios.finova.ui.coachmarks.LocalCoachMarks
import com.arthurrios.finova.ui.coachmarks.coachMarkTarget
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
import androidx.compose.foundation.clickable
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
import com.arthurrios.finova.domain.budget.BudgetFollowsIncome
import androidx.compose.material.icons.filled.Check
import com.arthurrios.finova.ui.budget.ChoiceDialog
import com.arthurrios.finova.ui.budget.DurationPicker
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
fun BudgetsScreen(viewModel: BudgetsViewModel, onBack: () -> Unit, onManageTags: () -> Unit = {}) {
    val budgets by viewModel.budgets.collectAsStateWithLifecycle()
    val hidden by viewModel.valuesHidden.collectAsStateWithLifecycle()
    val pending by viewModel.pendingOverwrite.collectAsStateWithLifecycle()
    val pendingRange by viewModel.pendingRange.collectAsStateWithLifecycle()
    val focusManager = LocalFocusManager.current

    var month by rememberSaveable { mutableStateOf(viewModel.initialMonth) }
    var amount by rememberSaveable { mutableStateOf(0L) }
    /** Last month a save covers; null is this month only (the single-month save, unchanged). */
    var endMonth by rememberSaveable { mutableStateOf<YearMonth?>(null) }
    var showErrors by rememberSaveable { mutableStateOf(false) }
    var showPicker by rememberSaveable { mutableStateOf(false) }
    var pendingDelete by rememberSaveable { mutableStateOf<YearMonth?>(null) }
    val coachMarks = LocalCoachMarks.current
    val coachSession = coachMarks?.session?.collectAsStateWithLifecycle()
    val guideRuns = coachSession?.value?.guide == CoachMarkGuideId.FirstBudget
    val income by remember(month) { viewModel.incomeOf(month) }.collectAsStateWithLifecycle(0L)
    val follow by viewModel.followSettings.collectAsStateWithLifecycle()
    val incomeByMonth by viewModel.incomeByMonth.collectAsStateWithLifecycle()
    var askEnable by rememberSaveable { mutableStateOf(false) }
    var askPercent by rememberSaveable { mutableStateOf(false) }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.budgets_header_title),
            subtitle = stringResource(R.string.budgets_header_subtitle),
            onBack = onBack,
            backModifier = Modifier.coachMarkTarget(CoachMarkTarget.BudgetsBack),
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
            Column(
                Modifier
                    .coachMarkTarget(CoachMarkTarget.BudgetsForm)
                    .fillMaxWidth()
                    .clip(CardShape)
                    .background(FinovaColors.Gray100)
                    .border(1.dp, FinovaColors.Gray300, CardShape),
            ) {
                CardHeader(stringResource(R.string.budgets_new_header_title))
                HorizontalDivider(color = FinovaColors.Gray300)
                Column(Modifier.padding(Spacing.S5), verticalArrangement = Arrangement.spacedBy(Spacing.S4)) {
                    FollowIncomeSection(
                        enabled = follow.isEnabled,
                        percent = follow.percent,
                        onToggle = { on -> if (on) askEnable = true else viewModel.disableFollow() },
                        onPickPercent = viewModel::setFollowPercent,
                        onOtherPercent = { askPercent = true },
                    )
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
                    if (guideRuns && income > 0) {
                        // A suggestion only: it fills the field, and saving stays the user's act.
                        TextButton(onClick = { amount = income }, modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp)) {
                            Text(
                                stringResource(R.string.budgets_suggestion_income, Money.formatMasked(income, viewModel.currencyCode, hidden)),
                                style = FinovaType.TextSMBold,
                                color = FinovaColors.MainMagenta,
                            )
                        }
                    }
                    // Same "Repeat for" row as the allocation sheet. An end month chosen for an
                    // earlier start month that is no longer after the start falls back to one month.
                    val repeatStart = month ?: YearMonth.now()
                    if (endMonth?.let { it <= repeatStart } == true) endMonth = null
                    DurationPicker(
                        start = repeatStart,
                        endMonth = endMonth,
                        onChange = { endMonth = it },
                        noEndLabel = stringResource(R.string.budgets_repeat_this_month_only),
                    )
                    FinovaButton(
                        text = stringResource(R.string.budgets_save),
                        onClick = {
                            focusManager.clearFocus()
                            showErrors = true
                            val picked = month ?: return@FinovaButton
                            if (amount <= 0) return@FinovaButton
                            val end = endMonth
                            val saved = if (end != null && end > picked) viewModel.saveRange(picked, end, amount)
                                else viewModel.save(picked, amount)
                            if (saved) {
                                month = null
                                amount = 0
                                endMonth = null
                                showErrors = false
                                coachMarks?.post(CoachMarkEvent.BudgetSaved)
                            }
                        },
                    )
                }
            }

            // Registered budgets: only the rows scroll, like the iOS table.
            Column(Modifier.fillMaxWidth().weight(1f, fill = false).coachMarkTarget(CoachMarkTarget.BudgetsList)) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(topStart = CornerRadius.ExtraLarge, topEnd = CornerRadius.ExtraLarge))
                        .background(FinovaColors.Gray100)
                        .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(topStart = CornerRadius.ExtraLarge, topEnd = CornerRadius.ExtraLarge)),
                ) {
                    CardHeader(stringResource(R.string.budgets_table_header_title)) {
                        // The only way to Tags when no month has any, since the dashboard strip then hides.
                        Text(
                            stringResource(R.string.budget_tags_manage),
                            style = FinovaType.TitleXS,
                            color = FinovaColors.MainMagenta,
                            modifier = Modifier.clip(RoundedCornerShape(CornerRadius.Small)).clickable(onClick = onManageTags).padding(Spacing.S1),
                        )
                    }
                }
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
                                // "80% of income", or the hint for a following month with no income yet.
                                val note = if (BudgetFollowsIncome.follows(budget.month, follow, incomeByMonth, YearMonth.now())) {
                                    if (budget.amount == 0L) stringResource(R.string.budgets_follow_income_no_income)
                                    else stringResource(R.string.budgets_follow_income_row_note, follow.percent)
                                } else null
                                BudgetRow(budget, viewModel.currencyCode, hidden, note = note, onDelete = { pendingDelete = budget.month })
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
                    coachMarks?.post(CoachMarkEvent.BudgetSaved)
                }) { Text(stringResource(R.string.alert_update)) }
            },
            dismissButton = { TextButton(onClick = viewModel::cancelOverwrite) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    pendingRange?.let { range ->
        val names = stringArrayResource(R.array.month_long)
        val shown = range.existing.map { "${names[it.monthValue - 1]} ${it.year}" }
        val list = shown.take(3).joinToString(", ") + if (shown.size > 3) " (+${shown.size - 3})" else ""
        fun resolved(replace: Boolean) {
            viewModel.resolveRange(range, replace)
            month = null
            amount = 0
            endMonth = null
            showErrors = false
            coachMarks?.post(CoachMarkEvent.BudgetSaved)
        }
        ChoiceDialog(
            title = stringResource(R.string.budgets_multi_conflict_title),
            message = stringResource(R.string.budgets_multi_conflict_message, list),
            choices = listOf(
                stringResource(R.string.budgets_multi_conflict_replace) to { resolved(true) },
                stringResource(R.string.budgets_multi_conflict_keep) to { resolved(false) },
            ),
            onDismiss = viewModel::cancelRange,
        )
    }
    if (askEnable) {
        ChoiceDialog(
            title = stringResource(R.string.budgets_follow_income_enable_title),
            message = stringResource(R.string.budgets_follow_income_enable_message, follow.percent),
            choices = listOf(
                stringResource(R.string.budgets_follow_income_enable_from_now) to { viewModel.enableFollow(includePastMonths = false) },
                stringResource(R.string.budgets_follow_income_enable_include_past) to { viewModel.enableFollow(includePastMonths = true) },
            ),
            onDismiss = { askEnable = false },
        )
    }
    if (askPercent) {
        CustomPercentDialog(
            initial = follow.percent,
            onPick = {
                viewModel.setFollowPercent(it)
                askPercent = false
            },
            onDismiss = { askPercent = false },
        )
    }
    val fixedTarget = pendingDelete?.takeIf(viewModel::isFixedInRange)
    if (fixedTarget != null) {
        // A fixed month inside the "follows income" range can rejoin instead of being deleted.
        ChoiceDialog(
            title = stringResource(R.string.budget_delete_title),
            message = stringResource(R.string.budgets_follow_income_fixed_month_message),
            choices = listOf(
                stringResource(R.string.budgets_follow_income_fixed_month_rejoin) to { viewModel.rejoin(fixedTarget) },
                stringResource(R.string.alert_delete) to { viewModel.delete(fixedTarget) },
            ),
            onDismiss = { pendingDelete = null },
        )
    } else pendingDelete?.let { target ->
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
private fun CardHeader(title: String, trailing: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().height(44.dp).padding(start = Spacing.S5, end = Spacing.S4), verticalAlignment = Alignment.CenterVertically) {
        Text(title.uppercase(), style = FinovaType.Title2XS, color = FinovaColors.Gray500, modifier = Modifier.weight(1f))
        trailing?.invoke()
    }
}

/**
 * One month. Past months are dimmed and cannot be deleted, as on iOS (their spending already
 * happened against that limit).
 */
@Composable
private fun BudgetRow(budget: Budget, currencyCode: String, hidden: Boolean, note: String? = null, onDelete: () -> Unit) {
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
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(names[budget.month.monthValue - 1], style = FinovaType.TitleMD, color = FinovaColors.Gray700)
                Spacer(Modifier.width(Spacing.S2))
                Text(budget.month.year.toString(), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            }
            if (note != null) {
                Text(note, style = FinovaType.TextXS, color = FinovaColors.Gray500, maxLines = 1,
                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
            }
        }
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

/**
 * "Budget follows income": one switch for every month and one percent. Months typed below stay
 * fixed. iOS uses a UISwitch and a menu; this is the Material switch and dropdown.
 */
@Composable
private fun FollowIncomeSection(
    enabled: Boolean,
    percent: Int,
    onToggle: (Boolean) -> Unit,
    onPickPercent: (Int) -> Unit,
    onOtherPercent: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.budgets_follow_income_title), style = FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
            androidx.compose.material3.Switch(
                checked = enabled,
                onCheckedChange = onToggle,
                colors = androidx.compose.material3.SwitchDefaults.colors(
                    checkedTrackColor = FinovaColors.MainMagenta,
                    checkedThumbColor = FinovaColors.Gray100,
                ),
            )
        }
        if (enabled) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.budgets_follow_income_percent), style = FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
                var open by remember { mutableStateOf(false) }
                Box {
                    TextButton(onClick = { open = true }) {
                        Text("$percent%  ⌄", style = FinovaType.TextSM, color = FinovaColors.MainMagenta)
                    }
                    androidx.compose.material3.DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = FinovaColors.Gray100) {
                        BudgetFollowsIncome.PERCENT_PRESETS.forEach { preset ->
                            androidx.compose.material3.DropdownMenuItem(
                                text = { Text("$preset%") },
                                trailingIcon = if (preset == percent) {
                                    { Icon(androidx.compose.material.icons.Icons.Filled.Check, contentDescription = null, tint = FinovaColors.MainMagenta) }
                                } else null,
                                onClick = { open = false; onPickPercent(preset) },
                            )
                        }
                        androidx.compose.material3.DropdownMenuItem(
                            text = { Text(stringResource(R.string.budgets_follow_income_percent_other)) },
                            onClick = { open = false; onOtherPercent() },
                        )
                    }
                }
            }
            Text(stringResource(R.string.budgets_follow_income_hint, percent), style = FinovaType.TextXS, color = FinovaColors.Gray500)
        }
    }
}

/** "Other…": a whole percent from 1 to 200. */
@Composable
private fun CustomPercentDialog(initial: Int, onPick: (Int) -> Unit, onDismiss: () -> Unit) {
    var text by remember { mutableStateOf(initial.toString()) }
    val range = BudgetFollowsIncome.PERCENT_RANGE
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.budgets_follow_income_percent)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                Text(stringResource(R.string.budgets_follow_income_percent_range, range.first, range.last))
                androidx.compose.material3.OutlinedTextField(
                    value = text,
                    onValueChange = { text = it.filter(Char::isDigit).take(3) },
                    singleLine = true,
                    suffix = { Text("%") },
                    keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { text.toIntOrNull()?.takeIf { it in range }?.let(onPick) ?: onDismiss() }) {
                Text(stringResource(R.string.alert_ok))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
