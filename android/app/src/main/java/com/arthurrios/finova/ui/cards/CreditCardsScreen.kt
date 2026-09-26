package com.arthurrios.finova.ui.cards

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.ui.components.RoundIconButton
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Port of CreditCardsView: the user's cards as small card previews. Tap edits, long press deletes. */
@Composable
fun CreditCardsScreen(
    viewModel: CreditCardsViewModel,
    onBack: () -> Unit,
    onAdd: () -> Unit,
    onEdit: (Long) -> Unit,
) {
    val cards by viewModel.list.collectAsState()
    val hidden by viewModel.valuesHidden.collectAsState()
    var pendingDelete by remember { mutableStateOf<CreditCard?>(null) }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.credit_cards_title),
            subtitle = null,
            onBack = onBack,
            trailing = {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    RoundIconButton(onClick = viewModel::toggleValues) {
                        Icon(
                            painterResource(if (hidden) R.drawable.ic_eye else R.drawable.ic_eye_closed),
                            contentDescription = stringResource(
                                if (hidden) R.string.month_card_show_values else R.string.month_card_hide_values
                            ),
                            modifier = Modifier.size(24.dp),
                        )
                    }
                    Spacer(Modifier.width(Spacing.S2))
                    IconButton(onClick = onAdd) {
                        Icon(
                            painterResource(R.drawable.ic_plus),
                            contentDescription = stringResource(R.string.credit_cards_add),
                            tint = FinovaColors.MainMagenta,
                        )
                    }
                }
            },
        )
        val list = cards
        when {
            list == null -> Unit
            list.isEmpty() -> EmptyState()
            else -> LazyColumn(
                contentPadding = PaddingValues(Spacing.S4),
                verticalArrangement = Arrangement.spacedBy(Spacing.S4),
                modifier = Modifier.fillMaxSize().navigationBarsPadding(),
            ) {
                items(list, key = { it.id }) { card ->
                    CreditCardCell(
                        card = card,
                        currencyCode = viewModel.currencyCode,
                        valuesHidden = hidden,
                        onClick = { onEdit(card.id) },
                        onLongClick = { pendingDelete = card },
                    )
                }
            }
        }
    }

    pendingDelete?.let { card ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(stringResource(R.string.credit_cards_delete_title)) },
            text = { Text(stringResource(R.string.credit_cards_delete_message)) },
            confirmButton = {
                TextButton(onClick = {
                    pendingDelete = null
                    viewModel.delete(card)
                }) { Text(stringResource(R.string.alert_delete), color = FinovaColors.MainRed) }
            },
            dismissButton = {
                TextButton(onClick = { pendingDelete = null }) { Text(stringResource(R.string.alert_cancel)) }
            },
        )
    }
}

@Composable
private fun EmptyState() {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.S2),
        modifier = Modifier.fillMaxWidth().padding(top = Spacing.S4 + Spacing.S12, start = Spacing.S4, end = Spacing.S4),
    ) {
        Text(stringResource(R.string.credit_cards_empty_title), style = FinovaType.TitleMD, color = FinovaColors.Gray500, textAlign = TextAlign.Center)
        Text(stringResource(R.string.credit_cards_empty_subtitle), style = FinovaType.TextSM, color = FinovaColors.Gray400, textAlign = TextAlign.Center)
    }
}

/** Port of CreditCardCell: a gradient card preview with the cycle and limit underneath. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun CreditCardCell(
    card: CreditCard,
    currencyCode: String,
    valuesHidden: Boolean,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val shape = RoundedCornerShape(CornerRadius.ExtraLarge)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(FinovaColors.Gray100)
            .combinedClickable(
                onClick = onClick,
                onLongClick = {
                    haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                    onLongClick()
                },
            )
            .padding(Spacing.S3),
    ) {
        CardPreview(card)
        Spacer(Modifier.height(Spacing.S3))
        Text(
            text = cardInfo(card, currencyCode, valuesHidden),
            style = FinovaType.TextXS,
            color = FinovaColors.Gray500,
            modifier = Modifier.padding(horizontal = Spacing.S1),
        )
    }
}

@Composable
private fun cardInfo(card: CreditCard, currencyCode: String, valuesHidden: Boolean): String {
    val parts = mutableListOf(
        stringResource(R.string.credit_cards_closes, card.closingDay.toString()),
        stringResource(R.string.credit_cards_due, card.dueDay.toString()),
    )
    card.creditLimit?.let {
        parts += stringResource(R.string.credit_cards_limit, Money.formatMasked(it, currencyCode, valuesHidden))
    }
    return parts.joinToString(" · ")
}

/** The 100dp card face: name and DEFAULT badge on top, masked number and brand below. */
@Composable
fun CardPreview(card: CreditCard, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(100.dp)
            .clip(RoundedCornerShape(CornerRadius.ExtraLarge))
            .background(card.color.gradient)
            .padding(Spacing.S4),
    ) {
        Text(
            card.name.uppercase(),
            style = FinovaType.TitleSM,
            color = Color.White,
            maxLines = 1,
            modifier = Modifier.align(Alignment.TopStart).padding(end = 72.dp),
        )
        if (card.isDefault) {
            Text(
                stringResource(R.string.credit_cards_default_badge),
                style = FinovaType.Title2XS,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .clip(RoundedCornerShape(CornerRadius.Small))
                    .background(Color.White.copy(alpha = 0.25f))
                    .padding(horizontal = Spacing.S2, vertical = Spacing.S1),
            )
        }
        Text(
            "**** **** **** ${card.lastFourDigits}",
            style = FinovaType.TextSM,
            color = Color.White.copy(alpha = 0.8f),
            modifier = Modifier.align(Alignment.BottomStart),
        )
        Text(
            stringResource(card.brand.label),
            style = FinovaType.TextXS,
            color = Color.White.copy(alpha = 0.7f),
            modifier = Modifier.align(Alignment.BottomEnd),
        )
    }
}
