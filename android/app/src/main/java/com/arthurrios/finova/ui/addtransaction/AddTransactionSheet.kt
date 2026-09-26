package com.arthurrios.finova.ui.addtransaction

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.ui.draw.clip
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
import androidx.compose.foundation.focusable
import androidx.compose.runtime.remember
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.card.CardCycle
import com.arthurrios.finova.domain.model.BusinessDayRule
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.series.TransactionDraft
import com.arthurrios.finova.domain.time.BusinessDayAdjuster
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.OptionTile
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
 * "New transaction". Port of AddTransactionModalView on iOS 1.5.2. The iOS system parts use their Android counterparts: the sheet is a Material
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
    /** Opens the sheet on an existing transaction ("Edit Transaction"); its mode cannot change. */
    editing: AddTransactionRequest? = null,
    /** The cards an expense can be paid with (not deleted). */
    cards: List<CreditCard> = emptyList(),
    /** "Create Card" when there is none yet: the sheet closes and the card form opens. */
    onCreateCard: () -> Unit = {},
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    // When a dialog closes, Compose gives focus back to the last focused field, which reopened
    // the keyboard on the amount after picking a date. Parking focus on the sheet itself (not a
    // text field) first leaves nothing to restore it to.
    val parking = remember { FocusRequester() }
    val closeKeyboard = {
        parking.requestFocus()
        keyboard?.hide()
    }

    var title by rememberSaveable { mutableStateOf(editing?.draft?.title ?: "") }
    var category by rememberSaveable { mutableStateOf(editing?.draft?.category) }
    var mode by rememberSaveable { mutableStateOf(editing?.mode ?: AddMode.Normal) }
    var installments by rememberSaveable { mutableStateOf(editing?.installments?.takeIf { it > 0 }?.toString() ?: "") }
    var amount by rememberSaveable { mutableStateOf(editing?.draft?.amount ?: 0L) }
    var date by rememberSaveable { mutableStateOf(editing?.draft?.date) }
    var rule by rememberSaveable { mutableStateOf(editing?.draft?.rule ?: defaultRule) }
    var type by rememberSaveable { mutableStateOf(editing?.draft?.type) }
    var showErrors by rememberSaveable { mutableStateOf(false) }
    var showDatePicker by rememberSaveable { mutableStateOf(false) }
    var showTypeAlert by rememberSaveable { mutableStateOf(false) }
    var payWithCard by rememberSaveable { mutableStateOf(editing?.draft?.creditCardId != null) }
    var cardId by rememberSaveable { mutableStateOf(editing?.draft?.creditCardId) }
    // Only an expense can go on a card; the section hides (and stops counting) for income.
    val isExpense = type == TransactionType.Expense
    val card = cards.firstOrNull { it.id == cardId }?.takeIf { payWithCard && isExpense }

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
                .focusRequester(parking)
                .focusable()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .navigationBarsPadding()
                .padding(start = Spacing.S6, end = Spacing.S6, bottom = Spacing.S6),
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(if (editing != null) R.string.edit_transaction_title else R.string.add_transaction_title).uppercase(),
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

            ModeSelector(mode = mode, onSelect = { mode = it }, enabled = editing == null)

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
                            closeKeyboard()
                            showDatePicker = true
                        },
                    )
                    if (card != null) {
                        // A card purchase is charged on the statement's due date, which the card
                        // decides, so the weekend rule has nothing to act on.
                        Text(stringResource(R.string.add_transaction_card_rule_hint), style = FinovaType.TextXS, color = FinovaColors.Gray500)
                    } else {
                        BusinessDayRuleButton(rule = rule, onSelect = { rule = it })
                    }
                    val picked = date
                    if (card == null && picked != null && rule != BusinessDayRule.Exact) {
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

            AnimatedVisibility(visible = isExpense) {
                PaymentMethodSection(
                    payWithCard = payWithCard,
                    cards = cards,
                    selected = card,
                    purchaseDate = date ?: LocalDate.now(),
                    defaultRule = defaultRule,
                    onPayWithCard = { withCard ->
                        payWithCard = withCard
                        // Like iOS: the default card, else the first one.
                        if (withCard && cards.none { it.id == cardId }) {
                            cardId = (cards.firstOrNull { it.isDefault } ?: cards.firstOrNull())?.id
                        }
                    },
                    onSelectCard = { cardId = it.id },
                    onCreateCard = onCreateCard,
                )
            }

            Spacer(Modifier.height(Spacing.S3))
            HorizontalDivider(color = FinovaColors.Gray300)
            Spacer(Modifier.height(Spacing.S3))

            FinovaButton(
                text = stringResource(if (editing != null) R.string.edit_transaction_save else R.string.add_transaction_save),
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
                            draft = TransactionDraft(
                                title.trim(), category!!, chosenType, amount, date!!, rule,
                                // The id, not the listed card: a transaction on a card deleted
                                // since keeps its card when edited.
                                creditCardId = cardId.takeIf { payWithCard && chosenType == TransactionType.Expense },
                            ),
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
                    closeKeyboard()
                }) { Text(stringResource(R.string.alert_ok)) }
            },
            dismissButton = {
                TextButton(onClick = {
                    showDatePicker = false
                    closeKeyboard()
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
private fun ModeSelector(mode: AddMode, onSelect: (AddMode) -> Unit, enabled: Boolean = true) {
    val labels = listOf(R.string.transaction_mode_normal, R.string.transaction_mode_recurring, R.string.transaction_mode_installments)
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth().height(Spacing.InputHeight)) {
        AddMode.entries.forEachIndexed { index, option ->
            SegmentedButton(
                selected = mode == option,
                onClick = { onSelect(option) },
                enabled = enabled || mode == option,
                shape = SegmentedButtonDefaults.itemShape(index, AddMode.entries.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = FinovaColors.MainMagenta,
                    activeContentColor = FinovaColors.Gray100,
                    activeBorderColor = FinovaColors.Gray300,
                    inactiveContainerColor = FinovaColors.Gray200,
                    inactiveContentColor = FinovaColors.Gray700,
                    inactiveBorderColor = FinovaColors.Gray300,
                    disabledActiveContainerColor = FinovaColors.MainMagenta,
                    disabledActiveContentColor = FinovaColors.Gray100,
                    disabledActiveBorderColor = FinovaColors.Gray300,
                    disabledInactiveContainerColor = FinovaColors.Gray200,
                    disabledInactiveContentColor = FinovaColors.Gray400,
                    disabledInactiveBorderColor = FinovaColors.Gray300,
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

/**
 * Cash / debit or a card. Port of the payment method section of AddTransactionModalView: two
 * option tiles with a radio (hand-built on iOS as well), then the card picker and a line saying
 * which statement the purchase lands on.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PaymentMethodSection(
    payWithCard: Boolean,
    cards: List<CreditCard>,
    selected: CreditCard?,
    purchaseDate: LocalDate,
    defaultRule: BusinessDayRule,
    onPayWithCard: (Boolean) -> Unit,
    onSelectCard: (CreditCard) -> Unit,
    onCreateCard: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3), modifier = Modifier.padding(top = Spacing.S2)) {
        Text(stringResource(R.string.payment_method_title), style = FinovaType.TextSMBold, color = FinovaColors.Gray600)
        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3)) {
            OptionTile(
                title = stringResource(R.string.payment_method_cash),
                subtitle = stringResource(R.string.payment_method_cash_subtitle),
                selected = !payWithCard,
                onClick = { onPayWithCard(false) },
                modifier = Modifier.weight(1f),
            )
            OptionTile(
                title = stringResource(R.string.payment_method_card),
                subtitle = stringResource(R.string.payment_method_card_subtitle),
                selected = payWithCard,
                onClick = { onPayWithCard(true) },
                modifier = Modifier.weight(1f),
            )
        }
        AnimatedVisibility(visible = payWithCard) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                if (cards.isEmpty()) {
                    FinovaTextField(
                        value = stringResource(R.string.payment_method_no_cards),
                        onValueChange = {},
                        placeholder = "",
                        enabled = false,
                        leadingIcon = R.drawable.ic_lucide_icon_credit_card,
                    )
                    com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton(
                        text = stringResource(R.string.payment_method_create_card),
                        onClick = onCreateCard,
                    )
                } else {
                    var expanded by rememberSaveable { mutableStateOf(false) }
                    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
                        FinovaTextField(
                            value = selected?.let { "${it.name} ****${it.lastFourDigits}" }.orEmpty(),
                            onValueChange = {},
                            placeholder = stringResource(R.string.payment_method_select_card),
                            leadingIcon = R.drawable.ic_lucide_icon_credit_card,
                            onClick = { expanded = true },
                            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                        )
                        ExposedDropdownMenu(
                            expanded = expanded,
                            onDismissRequest = { expanded = false },
                            containerColor = FinovaColors.Gray100,
                        ) {
                            cards.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text("${option.name} ****${option.lastFourDigits}", style = FinovaType.Input) },
                                    onClick = {
                                        expanded = false
                                        onSelectCard(option)
                                    },
                                )
                            }
                        }
                    }
                    if (selected != null) {
                        val closing = CardCycle.closingDate(selected.closingDay, purchaseDate)
                        val due = CardCycle.dueDate(closing, selected.dueDay, defaultRule)
                        val month = androidx.compose.ui.res.stringArrayResource(R.array.month_short)[closing.monthValue - 1]
                        Text(
                            stringResource(R.string.payment_method_statement_info, month, due.format(DateFormat)),
                            style = FinovaType.TextXS,
                            color = FinovaColors.Gray500,
                        )
                    }
                }
            }
        }
    }
}
