package com.arthurrios.finova.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Income / Expense choice. iOS hand-builds it (TransactionTypeSelector.swift), so this does too,
 * with its three looks: tinted with a colored border before a choice, solid when chosen, gray
 * when the other one is chosen.
 */
@Composable
fun TransactionTypeSelector(selected: TransactionType?, onSelect: (TransactionType) -> Unit, modifier: Modifier = Modifier) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Spacing.S5)) {
        TypeButton(TransactionType.Income, selected, onSelect, Modifier.weight(1f))
        TypeButton(TransactionType.Expense, selected, onSelect, Modifier.weight(1f))
    }
}

@Composable
private fun TypeButton(type: TransactionType, selected: TransactionType?, onSelect: (TransactionType) -> Unit, modifier: Modifier) {
    val income = type == TransactionType.Income
    val main = if (income) FinovaColors.MainGreen else FinovaColors.MainRed
    val tint = if (income) FinovaColors.LightGreen else FinovaColors.LightRed
    val shape = RoundedCornerShape(CornerRadius.Large)
    val (background, content, bordered) = when (selected) {
        null -> Triple(tint, main, true)
        type -> Triple(main, FinovaColors.Gray100, false)
        else -> Triple(FinovaColors.Gray200, main, false)
    }
    Row(
        modifier = modifier
            .height(Spacing.ButtonHeight)
            .clip(shape)
            .background(background)
            .then(if (bordered) Modifier.border(1.dp, main, shape) else Modifier)
            .clickable(role = Role.RadioButton) { onSelect(type) },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(if (income) R.string.add_transaction_income else R.string.add_transaction_expense),
            style = FinovaType.ButtonSM,
            color = content,
        )
        Spacer(Modifier.width(Spacing.S2))
        Icon(
            painterResource(if (income) R.drawable.ic_arrow_up else R.drawable.ic_arrow_down),
            contentDescription = null,
            tint = content,
            modifier = Modifier.size(14.dp),
        )
    }
}
