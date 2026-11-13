package com.arthurrios.finova.ui.statement

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.foundation.focusable
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.OptionTile
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.CardBody
import com.arthurrios.finova.ui.dashboard.CardHeader
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

private val DateFormat: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")

/**
 * Port of StatementPaymentView: pay a statement in full or in part, today or on a later date.
 * Continue asks to confirm, then the payment is booked and the screen goes back to the statement.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatementPaymentScreen(viewModel: StatementPaymentViewModel, onBack: () -> Unit) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirming by rememberSaveable { mutableStateOf(false) }
    var pickingDate by rememberSaveable { mutableStateOf(false) }
    val keyboard = LocalSoftwareKeyboardController.current
    val parking = remember { FocusRequester() }

    LaunchedEffect(state.done) { if (state.done) onBack() }

    val cardLabel = state.card?.let { "${it.name} ****${it.lastFourDigits}" }.orEmpty()
    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200).imePadding()) {
        ScreenHeader(
            title = stringResource(R.string.pay_title),
            subtitle = null,
            onBack = onBack,
            trailing = {
                RoundIconButton(onClick = viewModel::toggleValues) {
                    Icon(
                        painterResource(if (state.valuesHidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
                        contentDescription = stringResource(
                            if (state.valuesHidden) R.string.month_card_show_values else R.string.month_card_hide_values
                        ),
                        modifier = Modifier.size(24.dp),
                    )
                }
            },
        )
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S5),
            modifier = Modifier
                .weight(1f)
                .focusRequester(parking)
                .focusable()
                .verticalScroll(rememberScrollState())
                .padding(start = Spacing.S4, end = Spacing.S4, top = Spacing.S4, bottom = Spacing.S6),
        ) {
            Text(stringResource(R.string.pay_intro, state.statementLabel), style = FinovaType.TextSM, color = FinovaColors.Gray500)
            Column {
                CardHeader(stringResource(R.string.pay_invoice_header))
                CardBody {
                    InfoLine(stringResource(R.string.pay_invoice_card)) { Value(cardLabel) }
                    InfoLine(stringResource(R.string.pay_invoice_due)) { Value(state.statement?.dueDate?.format(DateFormat).orEmpty()) }
                    InfoLine(stringResource(R.string.pay_invoice_balance)) {
                        Text(Money.annotated(state.remaining, state.currencyCode, FinovaType.TextXS, state.valuesHidden),
                            style = FinovaType.TextSM, color = FinovaColors.Gray700)
                    }
                }
            }
            Column {
                CardHeader(stringResource(R.string.pay_payment_header))
                CardBody {
                    Label(stringResource(R.string.pay_amount))
                    CurrencyTextField(
                        cents = state.amount,
                        onCentsChange = viewModel::setAmount,
                        currencyCode = state.currencyCode,
                        isError = state.exceedsBalance,
                    )
                    if (state.exceedsBalance) {
                        Text(
                            stringResource(R.string.pay_error_exceeds, Money.format(state.remaining, state.currencyCode)),
                            style = FinovaType.TextXS,
                            color = FinovaColors.MainRed,
                        )
                    }
                    Label(stringResource(R.string.pay_when))
                    OptionTile(
                        title = stringResource(R.string.pay_today),
                        subtitle = stringResource(R.string.pay_today_subtitle),
                        selected = state.payToday,
                        onClick = { viewModel.setPayToday(true) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    OptionTile(
                        title = stringResource(R.string.pay_schedule),
                        subtitle = stringResource(R.string.pay_schedule_subtitle),
                        selected = !state.payToday,
                        onClick = { viewModel.setPayToday(false) },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    AnimatedVisibility(visible = !state.payToday) {
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                            Label(stringResource(R.string.pay_date))
                            FinovaTextField(
                                value = state.scheduledDate.format(DateFormat),
                                onValueChange = {},
                                placeholder = "00/00/0000",
                                leadingIcon = R.drawable.ic_calendar,
                                onClick = {
                                    parking.requestFocus()
                                    keyboard?.hide()
                                    pickingDate = true
                                },
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
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.pay_remaining), style = FinovaType.TextSM, color = FinovaColors.Gray600,
                    modifier = Modifier.weight(1f))
                Spacer(Modifier.width(Spacing.S3))
                Text(Money.annotated(state.balanceAfter, state.currencyCode, FinovaType.TextXS, state.valuesHidden),
                    style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            }
            Text(
                stringResource(if (state.paysInFull) R.string.pay_note_full else R.string.pay_note_partial),
                style = FinovaType.TextXS,
                color = FinovaColors.Gray500,
            )
            Spacer(Modifier.width(Spacing.S3))
            FinovaButton(
                text = stringResource(R.string.pay_continue),
                onClick = {
                    parking.requestFocus()
                    keyboard?.hide()
                    confirming = true
                },
                enabled = state.canContinue,
                loading = state.saving,
                modifier = Modifier.padding(top = Spacing.S3),
            )
        }
    }

    if (confirming) {
        val today = viewModel.minimumDate
        val outcome = if (state.paysInFull) stringResource(R.string.pay_confirm_full)
        else stringResource(R.string.pay_confirm_partial, Money.format(state.balanceAfter, state.currencyCode))
        val debitTitle = stringResource(R.string.pay_debit_title, state.card?.name.orEmpty(), state.statementLabel)
        val creditTitle = stringResource(R.string.pay_credit_title, state.statementLabel)
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.pay_confirm_title)) },
            text = {
                Text(
                    stringResource(
                        R.string.pay_confirm_message,
                        Money.format(state.amount, state.currencyCode),
                        cardLabel,
                        state.paymentDate(today).format(DateFormat),
                        outcome,
                    )
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirming = false
                    viewModel.confirm(debitTitle, creditTitle)
                }) { Text(stringResource(R.string.pay_confirm_action)) }
            },
            dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
    if (state.failed) {
        AlertDialog(
            onDismissRequest = viewModel::dismissError,
            title = { Text(stringResource(R.string.alert_error)) },
            text = { Text(stringResource(R.string.pay_error_generic)) },
            confirmButton = { TextButton(onClick = viewModel::dismissError) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    if (pickingDate) {
        val minMillis = viewModel.minimumDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
        val pickerState = rememberDatePickerState(
            initialSelectedDateMillis = state.scheduledDate.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli(),
            // A payment cannot be backdated, as on iOS.
            selectableDates = object : SelectableDates {
                override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis >= minMillis
                override fun isSelectableYear(year: Int) = year >= viewModel.minimumDate.year
            },
        )
        DatePickerDialog(
            onDismissRequest = { pickingDate = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let {
                        viewModel.setScheduledDate(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate())
                    }
                    pickingDate = false
                }) { Text(stringResource(R.string.alert_ok)) }
            },
            dismissButton = { TextButton(onClick = { pickingDate = false }) { Text(stringResource(R.string.alert_cancel)) } },
        ) { DatePicker(state = pickerState) }
    }
}

@Composable
private fun Label(text: String) = Text(text, style = FinovaType.TextSM, color = FinovaColors.Gray600)

@Composable
private fun Value(text: String) = Text(text, style = FinovaType.TextSM, color = FinovaColors.Gray700)

@Composable
private fun InfoLine(title: String, value: @Composable () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(title, style = FinovaType.TextSM, color = FinovaColors.Gray500, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(Spacing.S3))
        value()
    }
}
