package com.arthurrios.finova.ui.addtransaction

import androidx.compose.foundation.border
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.fx.FxCurrency
import com.arthurrios.finova.domain.fx.FxMath
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.fx.FxFormat
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

/**
 * The currency menu on the amount field (a UIMenu on the iOS input): "Received in", the app
 * currency and the common ones first, the rest under "More currencies".
 */
@Composable
internal fun CurrencyPickerButton(selected: String, appCurrency: String, onSelect: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    var showMore by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(
                Icons.Filled.ArrowDropDown,
                contentDescription = stringResource(R.string.fx_picker_accessibility),
                tint = FinovaColors.Gray600,
            )
        }
        DropdownMenu(
            expanded = open,
            onDismissRequest = { open = false; showMore = false },
            containerColor = FinovaColors.Gray100,
        ) {
            Text(
                stringResource(R.string.fx_picker_title),
                style = FinovaType.TextXS,
                color = FinovaColors.Gray500,
                modifier = Modifier.padding(horizontal = Spacing.S4, vertical = Spacing.S2),
            )
            val common = listOf(appCurrency) + FxCurrency.common.filter { it != appCurrency }
            val rest = FxCurrency.all.filter { it != appCurrency && it !in FxCurrency.common }
            @Composable
            fun item(code: String) = DropdownMenuItem(
                text = { Text("$code · ${FxFormat.symbol(code)}", style = FinovaType.Input) },
                trailingIcon = if (code == selected) {
                    { Icon(Icons.Filled.Check, contentDescription = null, tint = FinovaColors.MainMagenta) }
                } else null,
                onClick = {
                    open = false
                    showMore = false
                    onSelect(code)
                },
            )
            common.forEach { item(it) }
            HorizontalDivider(color = FinovaColors.Gray300)
            DropdownMenuItem(
                text = { Text(stringResource(R.string.fx_picker_more), style = FinovaType.Input) },
                trailingIcon = { Icon(if (showMore) Icons.Filled.ExpandMore else Icons.Filled.ChevronRight, contentDescription = null) },
                onClick = { showMore = !showMore },
            )
            if (showMore) rest.forEach { item(it) }
        }
    }
}

/** What the "Save as default" line says. */
internal enum class FxDefaultState { Hint, IsDefault, CanSave, Disabled }

/**
 * The FX card under the amount and the date (iOS `fxCard`):
 *
 *     YOU RECEIVE
 *     ≈ R$ 28.000,00
 *     Market 5,6513 → You get 5,6013
 *     Fee 0,9% · −R$ 252,07
 *     Market rate · 18:59                      (tap: type the rate)
 *     ─────────────────────────────
 *     Provider difference          [ R$ 0,05 ]
 *     per US$ 1, below the market
 *     Provider fee                 [ 0,9 % ]
 *     % taken from the total
 *     Save as default for USD
 */
@Composable
internal fun FxIncomeCard(
    currency: String,
    appCurrency: String,
    fxAmount: Long,
    /** The rate to show: locked, cached, or typed. Null: none yet (offline). */
    rateMicros: Long?,
    /** "Market rate · 18:59", "typed by you", "Rate locked on 20/11". */
    rateLabel: String?,
    rateTappable: Boolean,
    onRateTap: () -> Unit,
    diffCents: Long,
    onDiffChange: (Long) -> Unit,
    feeText: String,
    onFeeChange: (String) -> Unit,
    defaultState: FxDefaultState,
    onSaveDefault: () -> Unit,
    onDone: () -> Unit,
    valuesHidden: Boolean = false,
) {
    val shape = RoundedCornerShape(CornerRadius.ExtraLarge)
    val feeBps = FxMath.feeBps(feeText)
    val spread = spreadMicros(diffCents, appCurrency)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(FinovaColors.Gray200.copy(alpha = 0.5f))
            .border(1.dp, FinovaColors.Gray300, shape)
            .padding(start = Spacing.S4, end = Spacing.S4, top = Spacing.S4, bottom = Spacing.S3),
        verticalArrangement = Arrangement.spacedBy(Spacing.S1),
    ) {
        Text(stringResource(R.string.fx_card_title), style = FinovaType.Title2XS, color = FinovaColors.Gray500)
        if (rateMicros == null) {
            Text(stringResource(R.string.fx_hint_no_rate), style = FinovaType.TitleMD, color = FinovaColors.Gray700)
            Text(
                stringResource(R.string.fx_hint_type_rate),
                style = FinovaType.TextXS,
                color = FinovaColors.MainMagenta,
                modifier = Modifier.clickable(onClick = onRateTap).padding(vertical = Spacing.S1),
            )
        } else {
            // Difference first (the rate), then the fee off the total: the same order FxMath uses.
            val fee = feeBps ?: 0
            val beforeFee = com.arthurrios.finova.domain.fx.FxConversion.convert(fxAmount, currency, rateMicros, appCurrency, null, spread)
            val converted = com.arthurrios.finova.domain.fx.FxConversion.convert(fxAmount, currency, rateMicros, appCurrency, fee, spread)
            Text(
                "≈ " + Money.formatMasked(converted, appCurrency, valuesHidden),
                style = FinovaType.TitleMD,
                color = FinovaColors.Gray700,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            val market = FxFormat.plainRate(rateMicros)
            val marketText = stringResource(R.string.fx_card_market, market)
            val youGet = stringResource(R.string.fx_card_you_get, FxFormat.plainRate(FxMath.effectiveRateMicros(rateMicros, spread)))
            Text(
                buildAnnotatedString {
                    append(marketText)
                    if (spread > 0) {
                        append("  →  ")
                        withStyle(SpanStyle(fontWeight = FinovaType.TextSMBold.fontWeight, color = FinovaColors.Gray700)) { append(youGet) }
                    }
                },
                style = FinovaType.TextSM,
                color = FinovaColors.Gray600,
            )
            if (fee > 0) {
                Text(
                    stringResource(
                        R.string.fx_card_fee_line,
                        FxFormat.fee(fee) + "%",
                        "−" + Money.formatMasked(beforeFee - converted, appCurrency, valuesHidden),
                    ),
                    style = FinovaType.TextSM,
                    color = FinovaColors.Gray600,
                )
            }
            if (rateLabel != null) {
                Text(
                    rateLabel,
                    style = FinovaType.TextXS,
                    color = FinovaColors.Gray500,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .then(if (rateTappable) Modifier.clickable(onClick = onRateTap) else Modifier)
                        .padding(vertical = Spacing.S1),
                )
            }
        }
        Spacer(Modifier.height(Spacing.S2))
        HorizontalDivider(color = FinovaColors.Gray300)
        Spacer(Modifier.height(Spacing.S2))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                Text(stringResource(R.string.fx_diff_title), style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
                Text(stringResource(R.string.fx_diff_unit, "${FxFormat.symbol(currency)} 1"), style = FinovaType.TextXS, color = FinovaColors.Gray500)
            }
            Spacer(Modifier.width(Spacing.S3))
            CurrencyTextField(
                cents = diffCents,
                onCentsChange = onDiffChange,
                currencyCode = appCurrency,
                keyboardActions = KeyboardActions(onDone = { onDone() }),
                modifier = Modifier.width(136.dp),
            )
        }
        Spacer(Modifier.height(Spacing.S2))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                Text(stringResource(R.string.fx_fee_row_title), style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
                Text(stringResource(R.string.fx_fee_row_unit), style = FinovaType.TextXS, color = FinovaColors.Gray500)
            }
            Spacer(Modifier.width(Spacing.S3))
            FinovaTextField(
                value = feeText,
                onValueChange = { text -> onFeeChange(text.filter { it.isDigit() || it == ',' || it == '.' }.take(6)) },
                placeholder = zeroFee(),
                isError = feeBps == null,
                keyboardType = KeyboardType.Decimal,
                imeAction = ImeAction.Done,
                keyboardActions = KeyboardActions(onDone = { onDone() }),
                suffix = "%",
                modifier = Modifier.width(136.dp),
            )
        }
        Spacer(Modifier.height(Spacing.S1))
        val defaultText = when (defaultState) {
            FxDefaultState.Hint -> stringResource(R.string.fx_diff_hint)
            FxDefaultState.IsDefault -> stringResource(R.string.fx_diff_is_default, currency)
            FxDefaultState.CanSave, FxDefaultState.Disabled -> stringResource(R.string.fx_diff_save_default, currency)
        }
        Text(
            defaultText,
            style = FinovaType.TextXS,
            color = when (defaultState) {
                FxDefaultState.CanSave -> FinovaColors.MainMagenta
                FxDefaultState.Disabled -> FinovaColors.Gray400
                else -> FinovaColors.Gray500
            },
            modifier = Modifier
                .then(if (defaultState == FxDefaultState.CanSave) Modifier.clickable(onClick = onSaveDefault) else Modifier)
                .padding(vertical = Spacing.S1),
        )
    }
}

/** "0,00" in the phone's format, the fee hint. */
private fun zeroFee(): String = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
    minimumFractionDigits = 2
    maximumFractionDigits = 2
}.format(0)

/** The provider difference typed, in rate micros (R$ 0,05 → 50000). */
internal fun spreadMicros(diffCents: Long, appCurrency: String): Long =
    diffCents * BigDecimal.TEN.pow(maxOf(0, 6 - FxCurrency.digits(appCurrency))).toLong()

/** Back from micros to the field's minor units. */
internal fun diffCents(spreadMicros: Long, appCurrency: String): Long =
    spreadMicros / BigDecimal.TEN.pow(maxOf(0, 6 - FxCurrency.digits(appCurrency))).toLong()

/** The rate typed by hand when none is saved (offline, first use). */
@Composable
internal fun ManualRateDialog(currency: String, appCurrency: String, onDismiss: () -> Unit, onRate: (Long) -> Unit) {
    var text by remember { mutableStateOf("") }
    val separator = java.text.DecimalFormatSymbols.getInstance().decimalSeparator
    fun parsed(): Long? {
        val value = text.trim().replace(',', '.').toBigDecimalOrNull() ?: return null
        return if (value.signum() > 0) FxMath.micros(value) else null
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.fx_manual_rate_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S3)) {
                Text(stringResource(R.string.fx_manual_rate_message, FxFormat.symbol(currency), FxFormat.symbol(appCurrency)))
                OutlinedTextField(
                    value = text,
                    onValueChange = { new -> text = new.filter { it.isDigit() || it == ',' || it == '.' }.take(12) },
                    placeholder = { Text("5${separator}7651") },
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { parsed()?.let(onRate) ?: onDismiss() }) { Text(stringResource(R.string.fx_manual_rate_save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.fx_cancel)) } },
    )
}
