package com.arthurrios.finova.ui.early

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.OptionTile
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.CardBody
import com.arthurrios.finova.ui.dashboard.CardHeader
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

private val DateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")
private val MonthYear: DateTimeFormatter get() = DateTimeFormatter.ofPattern("MMM/yy", Locale.getDefault())

/**
 * Port of EarlyPaymentView: pick future installments, the payment date and (on a card) where the
 * debit goes, then confirm. Afterwards the screen goes back to the transaction.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EarlyPaymentScreen(viewModel: EarlyPaymentViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirming by rememberSaveable { mutableStateOf(false) }
    var pickingDate by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(state.done) { if (state.done) onBack() }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.early_title), subtitle = null, onBack = onBack)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S5),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(start = Spacing.S4, end = Spacing.S4, top = Spacing.S4, bottom = Spacing.S6),
        ) {
            if (state.loaded && state.installments.isEmpty()) {
                Text(stringResource(R.string.early_empty), style = FinovaType.TextSM, color = FinovaColors.Gray500)
                return@Column
            }
            Text(stringResource(R.string.early_intro, state.seriesTitle), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            Column {
                CardHeader(stringResource(R.string.early_installments_header), state.installments.size)
                CardBody {
                    InstallmentLine(
                        text = stringResource(R.string.early_select_all),
                        amount = null,
                        checked = state.allSelected,
                        onToggle = viewModel::toggleAll,
                        currency = state.currencyCode,
                        hidden = state.valuesHidden,
                        bold = true,
                    )
                    state.installments.forEach { item ->
                        HorizontalDivider(color = FinovaColors.Gray300)
                        InstallmentLine(
                            text = stringResource(R.string.early_row, item.number, item.total, item.dueDate.format(MonthYear)),
                            amount = item.amount,
                            checked = item.id in state.selected,
                            onToggle = { viewModel.toggle(item.id) },
                            currency = state.currencyCode,
                            hidden = state.valuesHidden,
                        )
                    }
                }
            }
            Column {
                CardHeader(stringResource(R.string.early_payment_header))
                CardBody {
                    Text(stringResource(R.string.early_date), style = FinovaType.TextSM, color = FinovaColors.Gray600)
                    FinovaTextField(
                        value = state.date.format(DateFormat),
                        onValueChange = {},
                        placeholder = "00/00/0000",
                        leadingIcon = R.drawable.ic_calendar,
                        onClick = { pickingDate = true },
                    )
                    val card = state.card
                    AnimatedVisibility(visible = card != null) {
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                            Text(stringResource(R.string.early_destination), style = FinovaType.TextSM, color = FinovaColors.Gray600)
                            OptionTile(
                                title = stringResource(R.string.early_open_statement),
                                subtitle = card?.let { "${it.name} ****${it.lastFourDigits}" }.orEmpty(),
                                selected = state.chargeToCard,
                                onClick = { viewModel.setChargeToCard(true) },
                                modifier = Modifier.fillMaxWidth(),
                            )
                            OptionTile(
                                title = stringResource(R.string.early_standalone),
                                subtitle = stringResource(R.string.early_standalone_subtitle),
                                selected = !state.chargeToCard,
                                onClick = { viewModel.setChargeToCard(false) },
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }
            }
        }
        HorizontalDivider(color = FinovaColors.Gray300)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S1),
            modifier = Modifier.background(FinovaColors.Gray100).navigationBarsPadding().padding(Spacing.S4),
        ) {
            Text(
                stringResource(
                    if (state.selected.size == 1) R.string.early_footer_count_one else R.string.early_footer_count_other,
                    state.selected.size,
                ),
                style = FinovaType.TextXS,
                color = FinovaColors.Gray500,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.early_footer_total), style = FinovaType.TextSM, color = FinovaColors.Gray600,
                    modifier = Modifier.weight(1f))
                Text(Money.annotated(state.selectedTotal, state.currencyCode, FinovaType.TextXS, state.valuesHidden),
                    style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            }
            FinovaButton(
                text = stringResource(R.string.early_continue),
                onClick = { confirming = true },
                enabled = state.canContinue,
                loading = state.saving,
                modifier = Modifier.padding(top = Spacing.S3),
            )
        }
    }

    if (confirming) {
        val card = state.card
        val destination = if (state.chargeToCard && card != null) {
            val target = state.targetStatement?.let { "${card.name} · ${it.dueDate.format(MonthYear)}" } ?: card.name
            stringResource(R.string.early_confirm_statement, target)
        } else stringResource(R.string.early_confirm_standalone)
        val title = stringResource(R.string.early_transaction_title, state.seriesTitle)
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.early_confirm_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.early_confirm_message,
                        state.selected.size,
                        Money.format(state.selectedTotal, state.currencyCode),
                        state.date.format(DateFormat),
                        destination,
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    viewModel.confirm(title)
                }) { Text(stringResource(R.string.early_confirm_action)) }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    if (state.failed) {
        AlertDialog(
            onDismissRequest = viewModel::dismissError,
            title = { Text(stringResource(R.string.alert_error)) },
            text = { Text(stringResource(R.string.early_error)) },
            confirmButton = { TextButton(onClick = viewModel::dismissError) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    if (pickingDate) {
        val minMillis = viewModel.minimumDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = state.date.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= minMillis
                override fun isSelectableYear(year: Int) = year >= viewModel.minimumDate.year
            },
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { viewModel.setDate(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()) }
                    pickingDate = false
                }) { Text(stringResource(R.string.alert_ok)) }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text(stringResource(R.string.alert_cancel)) } },
        ) { DatePicker(state = pickerState) }
    }
}

/** One selectable line (EarlyPaymentInstallmentRow): a checkbox, the installment, its amount. */
@Composable
private fun InstallmentLine(
    text: String,
    amount: Long?,
    checked: Boolean,
    onToggle: () -> Unit,
    currency: String,
    hidden: Boolean,
    bold: Boolean = false,
) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().toggleable(value = checked, role = Role.Checkbox, onValueChange = { onToggle() }),
    ) {
        Checkbox(
            checked = checked,
            onCheckedChange = null,
            colors = CheckboxDefaults.colors(checkedColor = FinovaColors.MainMagenta, uncheckedColor = FinovaColors.Gray400),
        )
        Spacer(Modifier.width(Spacing.S3))
        Text(text, style = if (bold) FinovaType.TextSMBold else FinovaType.TextSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
        if (amount != null) Text(Money.formatMasked(amount, currency, hidden), style = FinovaType.TextSM, color = FinovaColors.Gray700)
    }
}
