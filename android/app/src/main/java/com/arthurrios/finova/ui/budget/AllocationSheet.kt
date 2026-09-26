package com.arthurrios.finova.ui.budget

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.allocation.AllocationEditScope
import com.arthurrios.finova.domain.allocation.AllocationRow
import com.arthurrios.finova.domain.allocation.Allocations
import com.arthurrios.finova.domain.allocation.BudgetAllocation
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.time.SeriesMonths
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth
import java.time.format.DateTimeFormatter
import java.util.Locale

/** What the allocation sheet asks its owner to do once every question is answered. */
interface AllocationSheetActions {
    /** [overwrite] are allocations to remove first ("Overwrite Future Allocations"). */
    fun createAllocation(category: TransactionCategory, amount: Long, month: YearMonth, repeating: Boolean, endMonth: YearMonth?, overwrite: List<Long>)
    fun editAllocation(id: Long, amount: Long, scope: AllocationEditScope, through: YearMonth?)
}

private val MonthYear: DateTimeFormatter get() = DateTimeFormatter.ofPattern("MMM yyyy", Locale.getDefault())
private fun YearMonth.label() = format(MonthYear).replaceFirstChar { it.titlecase() }

/** How long a new repeating allocation runs, as AddAllocationModalView offers it. */
private val DurationPresets = listOf(3, 6, 12, 24)

/**
 * Port of AddAllocationModalView/Controller: category, amount and, for a new one, whether it
 * repeats and for how long. Saving asks the same questions iOS asks: which months an edit to a
 * series reaches, and what to do about later allocations a new repeating one would meet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AllocationSheet(
    month: YearMonth,
    allocations: List<AllocationRow>,
    currencyCode: String,
    actions: AllocationSheetActions,
    onDismiss: () -> Unit,
    editing: BudgetAllocation? = null,
    preselected: TransactionCategory? = null,
) {
    val available = remember(allocations, month) { Allocations.availableCategories(allocations, month) }
    var category by rememberSaveable { mutableStateOf(editing?.category ?: preselected) }
    var amount by rememberSaveable { mutableStateOf(editing?.allocated ?: 0L) }
    var repeating by rememberSaveable { mutableStateOf(false) }
    var endMonth by rememberSaveable { mutableStateOf<YearMonth?>(null) }
    var error by remember { mutableStateOf<Pair<Int, Int>?>(null) }
    var conflicts by remember { mutableStateOf<List<AllocationRow>>(emptyList()) }
    var askScope by remember { mutableStateOf(false) }
    var askThrough by remember { mutableStateOf(false) }

    fun create(repeat: Boolean, overwrite: List<Long> = emptyList()) {
        actions.createAllocation(category!!, amount, month, repeat, if (repeat) endMonth else null, overwrite)
        onDismiss()
    }

    fun save() {
        val c = category ?: return run { error = R.string.alloc_error_category_title to R.string.alloc_error_category_message }
        if (amount <= 0) return run { error = R.string.alloc_error_amount_title to R.string.alloc_error_amount_message }
        if (editing != null) {
            if (Allocations.isPartOfSeries(allocations, editing.id)) askScope = true
            else {
                actions.editAllocation(editing.id, amount, AllocationEditScope.ThisOnly, null)
                onDismiss()
            }
            return
        }
        if (repeating) {
            val found = Allocations.conflicts(allocations, c, month, endMonth)
            if (found.isNotEmpty()) return run { conflicts = found }
        }
        create(repeating)
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = FinovaColors.Gray100,
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(start = Spacing.S6, end = Spacing.S6, bottom = Spacing.S6),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(if (editing != null) R.string.alloc_edit_title else R.string.alloc_new_title).uppercase(),
                    style = FinovaType.TitleSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss) {
                    Icon(painterResource(R.drawable.ic_x), contentDescription = stringResource(R.string.add_transaction_close),
                        tint = FinovaColors.Gray600, modifier = Modifier.size(20.dp))
                }
            }
            CategoryPicker(
                selected = category,
                options = if (editing != null) listOfNotNull(editing.category) else available,
                enabled = editing == null,
                onSelect = { category = it },
            )
            CurrencyTextField(cents = amount, onCentsChange = { amount = it }, currencyCode = currencyCode)
            if (editing == null) {
                Text(stringResource(R.string.alloc_options), style = FinovaType.TextSMBold, color = FinovaColors.Gray600,
                    modifier = Modifier.padding(top = Spacing.S2))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.alloc_repeat), style = FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
                    Switch(checked = repeating, onCheckedChange = { repeating = it },
                        colors = SwitchDefaults.colors(checkedTrackColor = FinovaColors.MainMagenta))
                }
                AnimatedVisibility(visible = repeating) {
                    DurationPicker(month, endMonth) { endMonth = it }
                }
            }
            Spacer(Modifier.size(Spacing.S2))
            HorizontalDivider(color = FinovaColors.Gray300)
            FinovaButton(
                text = stringResource(if (editing != null) R.string.alloc_save else R.string.alloc_create),
                onClick = ::save,
                modifier = Modifier.padding(top = Spacing.S3),
            )
        }
    }

    error?.let { (title, message) ->
        AlertDialog(
            onDismissRequest = { error = null },
            title = { Text(stringResource(title)) },
            text = { Text(stringResource(message)) },
            confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    if (conflicts.isNotEmpty()) {
        val shown = conflicts.map { it.month }.distinct()
        val list = shown.take(3).joinToString(", ") { it.label() } + if (shown.size > 3) " (+${shown.size - 3})" else ""
        ChoiceDialog(
            title = stringResource(R.string.alloc_conflict_title),
            message = stringResource(R.string.alloc_conflict_message, stringResource(category!!.label), list),
            choices = listOf(
                stringResource(R.string.alloc_conflict_overwrite) to { create(true, conflicts.map { it.id }) },
                stringResource(R.string.alloc_conflict_keep) to { create(true) },
                stringResource(R.string.alloc_conflict_this_month) to { create(false) },
            ),
            onDismiss = { conflicts = emptyList() },
        )
    }
    if (askScope && editing != null) {
        ChoiceDialog(
            title = stringResource(R.string.alloc_edit_scope_title),
            message = stringResource(R.string.alloc_edit_scope_message),
            choices = listOf(
                stringResource(R.string.alloc_edit_this) to { actions.editAllocation(editing.id, amount, AllocationEditScope.ThisOnly, null); onDismiss() },
                stringResource(R.string.alloc_edit_future) to { actions.editAllocation(editing.id, amount, AllocationEditScope.ThisAndLater, null); onDismiss() },
                stringResource(R.string.alloc_edit_through) to { askScope = false; askThrough = true },
                stringResource(R.string.alloc_edit_all) to { actions.editAllocation(editing.id, amount, AllocationEditScope.All, null); onDismiss() },
            ),
            onDismiss = { askScope = false },
        )
    }
    if (askThrough && editing != null) {
        val months = remember(allocations) { Allocations.laterSeriesMonths(allocations, editing.id) }
        ChoiceDialog(
            title = stringResource(R.string.alloc_edit_through_title),
            message = null,
            choices = months.map { m -> m.label() to { actions.editAllocation(editing.id, amount, AllocationEditScope.Through, m); onDismiss() } },
            onDismiss = { askThrough = false },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryPicker(selected: TransactionCategory?, options: List<TransactionCategory>, enabled: Boolean, onSelect: (TransactionCategory) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { if (enabled) expanded = it }) {
        FinovaTextField(
            value = selected?.let { stringResource(it.label) }.orEmpty(),
            onValueChange = {},
            placeholder = stringResource(R.string.alloc_category_placeholder),
            leadingIcon = selected?.icon(TransactionType.Expense) ?: R.drawable.ic_tag,
            enabled = enabled,
            onClick = { if (enabled) expanded = true },
            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = FinovaColors.Gray100,
            modifier = Modifier.heightIn(max = 360.dp)) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.label), style = FinovaType.Input) },
                    leadingIcon = { Icon(painterResource(option.icon(TransactionType.Expense)), null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(20.dp)) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

/** "Repeat for": always, a preset number of months, or an exact end month. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DurationPicker(start: YearMonth, endMonth: YearMonth?, onChange: (YearMonth?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    var choosingMonth by remember { mutableStateOf(false) }
    val presetFor = { end: YearMonth? -> DurationPresets.firstOrNull { end == start.plusMonths(it - 1L) } }
    val title = when (endMonth) {
        null -> stringResource(R.string.alloc_always)
        else -> presetFor(endMonth)?.let { stringResource(R.string.alloc_months, it) } ?: endMonth.label()
    }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.alloc_repeat_for), style = FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
            ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                TextButton(onClick = { expanded = true }, modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable)) {
                    Text("$title  ⌄", color = FinovaColors.MainMagenta, style = FinovaType.TextSMBold)
                }
                ExposedDropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }, containerColor = FinovaColors.Gray100,
                    modifier = Modifier.width(220.dp)) {
                    DropdownMenuItem(text = { Text(stringResource(R.string.alloc_always)) }, onClick = { expanded = false; onChange(null) })
                    DurationPresets.forEach { preset ->
                        // A preset of N is the starting month plus N-1 more.
                        DropdownMenuItem(text = { Text(stringResource(R.string.alloc_months, preset)) },
                            onClick = { expanded = false; onChange(start.plusMonths(preset - 1L)) })
                    }
                    DropdownMenuItem(text = { Text(stringResource(R.string.alloc_choose_end)) }, onClick = { expanded = false; choosingMonth = true })
                }
            }
        }
        if (endMonth != null) {
            Text(stringResource(R.string.alloc_until, endMonth.label()), style = FinovaType.TextXS, color = FinovaColors.Gray500)
        }
    }
    if (choosingMonth) {
        ChoiceDialog(
            title = stringResource(R.string.alloc_choose_end),
            message = null,
            choices = (1..SeriesMonths.HORIZON_MONTHS.toInt()).map { offset ->
                val month = start.plusMonths(offset.toLong())
                month.label() to { onChange(month) }
            },
            onDismiss = { choosingMonth = false },
        )
    }
}

/** A question with a list of answers (the iOS alerts and action sheets with several buttons). */
@Composable
fun ChoiceDialog(title: String, message: String?, choices: List<Pair<String, () -> Unit>>, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(Modifier.heightIn(max = 420.dp).verticalScroll(rememberScrollState())) {
                if (message != null) Text(message, modifier = Modifier.padding(bottom = Spacing.S2))
                choices.forEach { (label, action) ->
                    TextButton(onClick = { onDismiss(); action() }, modifier = Modifier.fillMaxWidth()) {
                        Text(label, color = FinovaColors.MainMagenta, modifier = Modifier.fillMaxWidth())
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
