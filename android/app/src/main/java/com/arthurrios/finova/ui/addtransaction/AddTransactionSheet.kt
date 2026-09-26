package com.arthurrios.finova.ui.addtransaction

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.TransactionDraft
import com.arthurrios.finova.domain.time.BusinessDayAdjuster
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.TransactionTypeSelector
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

enum class AddMode { Normal, Recurring, Installments }

/** What the sheet hands back on Save. */
data class AddTransactionRequest(val draft: TransactionDraft, val mode: AddMode, val installments: Int)

private val DateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/**
 * "New transaction". Port of AddTransactionModalView on iOS 1.5.2 (card payment comes with the
 * credit card port). The iOS system parts use their Android counterparts: the sheet is a Material
 * bottom sheet, the mode switch Material segmented buttons, the category wheel a dropdown, and
 * the date wheel the Material date picker.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AddTransactionSheet(
    currencyCode: String,
    defaultRule: BusinessDayRule,
    onSave: (AddTransactionRequest) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val focusManager = LocalFocusManager.current

    var title by rememberSaveable { mutableStateOf("") }
    var category by rememberSaveable { mutableStateOf<TransactionCategory?>(null) }
    var mode by rememberSaveable { mutableStateOf(AddMode.Normal) }
    var installments by rememberSaveable { mutableStateOf("") }
    var amount by rememberSaveable { mutableStateOf(0L) }
    var date by rememberSaveable { mutableStateOf<LocalDate?>(null) }
    var rule by rememberSaveable { mutableStateOf(defaultRule) }
    var type by rememberSaveable { mutableStateOf<TransactionType?>(null) }
    var showErrors by rememberSaveable { mutableStateOf(false) }
    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTypeAlert by rememberSaveable { mutableStateOf(false) }

    val installmentCount = installments.toIntOrNull() ?: 0
    val titleError = showErrors && title.isBlank()
    val categoryError = showErrors && category == null
    val amountError = showErrors && amount <= 0
    val dateError = showErrors && date == null
    val installmentsError = showErrors && mode == AddMode.Installments && installmentCount < 2

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = FinovaColors.Gray100,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(start = Spacing.S6, end = Spacing.S6, bottom = Spacing.S6),
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.add_transaction_title).uppercase(),
                    style = FinovaType.TitleSM,
                    color = FinovaColors.Gray700,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = onDismiss) {
                    Icon(
                        painterResource(R.drawable.ic_x),
                        contentDescription = stringResource(R.string.add_transaction_close),
                        tint = FinovaColors.Gray600,
                        modifier = Modifier.size(20.dp),
                    )
                }
            }

            FinovaTextField(
                value = title,
                onValueChange = { title = it },
                placeholder = stringResource(R.string.add_transaction_input_title),
                isError = titleError,
                imeAction = ImeAction.Next,
                keyboardActions = KeyboardActions(onNext = { focusManager.clearFocus() }),
            )

            CategoryField(selected = category, isError = categoryError, onSelect = { category = it })

            ModeSelector(mode = mode, onSelect = { mode = it })

            AnimatedVisibility(visible = mode == AddMode.Installments) {
                FinovaTextField(
                    value = installments,
                    onValueChange = { text -> installments = text.filter(Char::isDigit).take(3) },
                    placeholder = stringResource(R.string.add_transaction_installments_placeholder),
                    isError = installmentsError,
                    keyboardType = KeyboardType.Number,
                    suffix = if (installments.isEmpty()) null else " " + stringResource(R.string.add_transaction_installments_suffix),
                )
            }

            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S5)) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                    CurrencyTextField(
                        cents = amount,
                        onCentsChange = { amount = it },
                        currencyCode = currencyCode,
                        placeholder = stringResource(R.string.add_transaction_input_money),
                        isError = amountError,
                        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                    )
                    if (mode == AddMode.Installments) {
                        Text(stringResource(R.string.add_transaction_total_value), style = FinovaType.TextSM, color = FinovaColors.Gray400)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                    FinovaTextField(
                        value = date?.format(DateFormat).orEmpty(),
                        onValueChange = {},
                        placeholder = stringResource(R.string.add_transaction_input_date),
                        isError = dateError,
                        leadingIcon = R.drawable.ic_calendar,
                        onClick = {
                            focusManager.clearFocus()
                            showDatePicker = true
                        },
                    )
                    BusinessDayRuleButton(rule = rule, onSelect = { rule = it })
                    val picked = date
                    if (picked != null && rule != BusinessDayRule.Exact) {
                        val effective = BusinessDayAdjuster.adjust(picked, rule)
                        if (effective != picked) {
                            Text(
                                stringResource(R.string.add_transaction_business_day_effective, effective.format(DateFormat)),
                                style = FinovaType.TextXS,
                                color = FinovaColors.Gray500,
                            )
                        }
                    }
                }
            }

            TransactionTypeSelector(selected = type, onSelect = { type = it })

            Spacer(Modifier.height(Spacing.S3))
            HorizontalDivider(color = FinovaColors.Gray300)
            Spacer(Modifier.height(Spacing.S3))

            FinovaButton(
                text = stringResource(R.string.add_transaction_save),
                onClick = {
                    focusManager.clearFocus()
                    showErrors = true
                    val valid = title.isNotBlank() && category != null && amount > 0 && date != null &&
                        (mode != AddMode.Installments || installmentCount >= 2)
                    if (!valid) return@FinovaButton
                    val chosenType = type ?: run {
                        showTypeAlert = true
                        return@FinovaButton
                    }
                    onSave(
                        AddTransactionRequest(
                            draft = TransactionDraft(title.trim(), category!!, chosenType, amount, date!!, rule),
                            mode = mode,
                            installments = installmentCount,
                        )
                    )
                },
            )
        }
    }

    if (showDatePicker) {
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = (date ?: LocalDate.now()).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let {
                        date = Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()
                    }
                    showDatePicker = false
                    // The dialog hands focus back to the last field; keep the keyboard closed.
                    focusManager.clearFocus()
                }) { Text(stringResource(R.string.alert_ok)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    showDatePicker = false
                    focusManager.clearFocus()
                }) { Text(stringResource(R.string.alert_cancel)) }
            },
        ) { DatePicker(state = pickerState) }
    }

    if (showTypeAlert) {
        AlertDialog(
            onDismissRequest = { showTypeAlert = false },
            title = { Text(stringResource(R.string.add_transaction_alert_type_title)) },
            text = { Text(stringResource(R.string.add_transaction_alert_type_description)) },
            confirmButton = { TextButton(onClick = { showTypeAlert = false }) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
}

/** Normal / Recurring / Installments. iOS uses the system segmented control; this is Android's. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ModeSelector(mode: AddMode, onSelect: (AddMode) -> Unit) {
    val labels = listOf(R.string.transaction_mode_normal, R.string.transaction_mode_recurring, R.string.transaction_mode_installments)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().height(Spacing.InputHeight)) {
        AddMode.entries.forEachIndexed { index, option ->
            SegmentedButton(
                selected = mode == option,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, AddMode.entries.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = FinovaColors.MainMagenta,
                    activeContentColor = FinovaColors.Gray100,
                    activeBorderColor = FinovaColors.Gray300,
                    inactiveContainerColor = FinovaColors.Gray200,
                    inactiveContentColor = FinovaColors.Gray700,
                    inactiveBorderColor = FinovaColors.Gray300,
                ),
                // No check mark: iOS shows only the filled segment.
                icon = {},
                modifier = Modifier.height(Spacing.InputHeight),
            ) { Text(stringResource(labels[index]), style = FinovaType.Input) }
        }
    }
}

/** The category wheel on iOS; a dropdown on Android. Credit card is left out, as on iOS. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CategoryField(selected: TransactionCategory?, isError: Boolean, onSelect: (TransactionCategory) -> Unit) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        FinovaTextField(
            value = selected?.let { stringResource(it.label) }.orEmpty(),
            onValueChange = {},
            placeholder = stringResource(R.string.add_transaction_input_category),
            isError = isError,
            leadingIcon = R.drawable.ic_tag,
            onClick = { expanded = true },
            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = FinovaColors.Gray100,
        ) {
            TransactionCategory.entries.filter { it != TransactionCategory.CreditCard }.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.label), style = FinovaType.Input) },
                    leadingIcon = {
                        Icon(painterResource(option.icon(TransactionType.Expense)), contentDescription = null,
                            tint = FinovaColors.MainMagenta, modifier = Modifier.size(20.dp))
                    },
                    onClick = {
                        onSelect(option)
                        expanded = false
                    },
                )
            }
        }
    }
}

/** "Exact date ▾" under the date, opening a menu of the three rules (a UIMenu on iOS). */
@Composable
private fun BusinessDayRuleButton(rule: BusinessDayRule, onSelect: (BusinessDayRule) -> Unit) {
    var open by rememberSaveable { mutableStateOf(false) }
    Box {
        Text(
            text = stringResource(rule.label) + " ▾",
            style = FinovaType.TextXS,
            color = FinovaColors.Gray500,
            modifier = Modifier
                .padding(vertical = Spacing.S1)
                .clickable { open = true },
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            BusinessDayRule.entries.forEach { option ->
                DropdownMenuItem(
                    text = { Text(stringResource(option.label)) },
                    onClick = {
                        onSelect(option)
                        open = false
                    },
                )
            }
        }
    }
}

private val BusinessDayRule.label: Int
    get() = when (this) {
        BusinessDayRule.Exact -> R.string.business_day_rule_exact
        BusinessDayRule.NextBusinessDay -> R.string.business_day_rule_next
        BusinessDayRule.PreviousBusinessDay -> R.string.business_day_rule_previous
    }
