package com.arthurrios.finova.ui.dashboard

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * "Doesn't match your bank?" Port of AdjustBalanceModalView: shows the balance the app computes
 * for today and takes the real one. The difference goes into the balance offset.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdjustBalanceSheet(
    currentBalance: Long,
    currencyCode: String,
    onConfirm: (realBalance: Long) -> Unit,
    onDismiss: () -> Unit,
) {
    val focusManager = LocalFocusManager.current
    var real by rememberSaveable { mutableStateOf(0L) }
    var showError by rememberSaveable { mutableStateOf(false) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = FinovaColors.Gray100,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .imePadding()
                .navigationBarsPadding()
                .padding(start = Spacing.S8, end = Spacing.S8, bottom = Spacing.S4),
            verticalArrangement = Arrangement.spacedBy(Spacing.S7),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.adjust_balance_title).uppercase(), style = FinovaType.TitleXS,
                    color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
                IconButton(onClick = onDismiss) {
                    Icon(painterResource(R.drawable.ic_x), stringResource(R.string.add_transaction_close),
                        tint = FinovaColors.Gray500, modifier = Modifier.size(20.dp))
                }
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                Text(stringResource(R.string.adjust_balance_current), style = FinovaType.TextSM, color = FinovaColors.Gray400)
                Text(Money.format(currentBalance, currencyCode), style = FinovaType.TitleSM, color = FinovaColors.Gray700)
            }
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                Text(stringResource(R.string.adjust_balance_real), style = FinovaType.TextSM, color = FinovaColors.Gray400)
                CurrencyTextField(
                    cents = real,
                    onCentsChange = { real = it },
                    currencyCode = currencyCode,
                    isError = showError && real == 0L,
                    keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus() }),
                )
            }
            HorizontalDivider(color = FinovaColors.Gray300)
            FinovaButton(
                text = stringResource(R.string.adjust_balance_confirm),
                onClick = {
                    showError = true
                    if (real == 0L) return@FinovaButton
                    onConfirm(real)
                },
            )
        }
    }
}
