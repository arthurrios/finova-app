package com.arthurrios.finova.ui.dashboard

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.format.Money
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.format.DateTimeFormatter

private val TopCorners = RoundedCornerShape(topStart = CornerRadius.ExtraLarge, topEnd = CornerRadius.ExtraLarge)
private val BottomCorners = RoundedCornerShape(bottomStart = CornerRadius.ExtraLarge, bottomEnd = CornerRadius.ExtraLarge)

/** The search field and the round filter button under the month card. */
@Composable
fun TransactionSearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    onFilter: () -> Unit,
    filterActive: Boolean = false,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) {
            FinovaTextField(
                value = query,
                onValueChange = onQueryChange,
                placeholder = stringResource(R.string.transactions_search_placeholder),
                imeAction = ImeAction.Search,
                leadingIcon = R.drawable.ic_search,
                containerColor = FinovaColors.Gray100,
                clearable = true,
            )
        }
        Spacer(Modifier.width(Spacing.S2))
        OutlinedIconButton(
            onClick = onFilter,
            // Magenta and filled while a filter is on, like updateFilterButtonAppearance on iOS.
            border = if (filterActive) null else BorderStroke(1.dp, FinovaColors.Gray300),
            colors = androidx.compose.material3.IconButtonDefaults.outlinedIconButtonColors(
                containerColor = if (filterActive) FinovaColors.MainMagenta else FinovaColors.Gray100,
                contentColor = if (filterActive) FinovaColors.Gray100 else FinovaColors.Gray600,
            ),
            modifier = Modifier.size(Spacing.InputHeight),
        ) {
            Icon(painterResource(R.drawable.ic_filter), contentDescription = stringResource(R.string.transactions_filter))
        }
    }
}

/** "TRANSACTIONS" with the count pill: the rounded top of the list card. */
@Composable
fun TransactionListHeader(count: Int) = CardHeader(stringResource(R.string.transactions_header_title), count)

/**
 * Port of CardHeader.swift: the rounded top of a card, an uppercase title and an optional count
 * pill. The card body below it has the rounded bottom.
 */
@Composable
fun CardHeader(title: String, count: Int? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clip(TopCorners)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, TopCorners)
            .padding(start = Spacing.S5, end = Spacing.S4),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        // With trailing actions the count sits beside the title, as in the iOS allocations header.
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S2)) {
            Text(
                text = title.uppercase(),
                style = FinovaType.Title2XS,
                color = FinovaColors.Gray500,
            )
            if (count != null && trailing != null) CountPill(count)
        }
        if (trailing != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Spacing.S3)) { trailing() }
        } else if (count != null) {
            CountPill(count)
        }
    }
}

@Composable
private fun CountPill(count: Int) {
    Box(
        modifier = Modifier
            .height(18.dp)
            .clip(CircleShape)
            .background(FinovaColors.Gray300)
            .padding(horizontal = Spacing.S2),
        contentAlignment = Alignment.Center,
    ) {
        Text(count.toString(), style = FinovaType.TitleXS, color = FinovaColors.Gray600)
    }
}

/** The rounded bottom half of a card, under a [CardHeader]. */
@Composable
fun CardBody(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(BottomCorners)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, BottomCorners)
            .padding(Spacing.S4),
        verticalArrangement = Arrangement.spacedBy(Spacing.S3),
    ) { content() }
}

/** The rounded box the rows scroll inside: the bottom half of the list card. */
@Composable
fun TransactionListBox(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(BottomCorners)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, BottomCorners),
    ) { content() }
}

/** Shown in place of the rows when the month has none. */
@Composable
fun TransactionEmptyState(message: String = stringResource(R.string.transactions_empty_state_description)) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(68.dp)
            .clip(BottomCorners)
            .background(FinovaColors.Gray100)
            .border(1.dp, FinovaColors.Gray300, BottomCorners)
            .padding(horizontal = Spacing.S5),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            painterResource(R.drawable.ic_icon_bank_slip),
            contentDescription = null,
            tint = FinovaColors.Gray400,
            modifier = Modifier.size(Spacing.S8),
        )
        Spacer(Modifier.width(Spacing.S5))
        Text(
            message,
            style = FinovaType.TextXS,
            color = FinovaColors.Gray500,
        )
    }
}

/**
 * One transaction. Port of TransactionCell.swift. Swiping left deletes, as on iOS; the trash icon
 * does the same.
 */
@Composable
fun TransactionRow(
    row: TransactionRowUi,
    currencyCode: String,
    valuesHidden: Boolean,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    // Half the row, not Material's 56dp default, and the row never stays dismissed: a swipe only
    // asks the dashboard to confirm, then springs back, as the iOS delete action does.
    val currentOnDelete by rememberUpdatedState(onDelete)
    @Suppress("DEPRECATION")
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) currentOnDelete()
            false
        },
        positionalThreshold = { width -> width * 0.5f },
    )
    val canDelete = row.statementTransactionCount == null
    Column {
        SwipeToDismissBox(
            state = dismissState,
            enableDismissFromStartToEnd = false,
            enableDismissFromEndToStart = canDelete,
            backgroundContent = { DeleteBackground() },
        ) {
            RowContent(row, currencyCode, valuesHidden, canDelete, onClick, onDelete)
        }
    }
}

@Composable
private fun RowContent(
    row: TransactionRowUi,
    currencyCode: String,
    valuesHidden: Boolean,
    canDelete: Boolean,
    onClick: () -> Unit,
    onDelete: () -> Unit,
) {
    val isStatement = row.statementTransactionCount != null
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(FinovaColors.Gray100)
            .clickable(onClick = onClick)
            .alpha(if (row.isSettledEarly) 0.45f else 1f)
            .padding(start = Spacing.S5, end = Spacing.S3, top = Spacing.S4, bottom = Spacing.S4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier
                .size(Spacing.S8)
                .clip(RoundedCornerShape(CornerRadius.Medium))
                .background(FinovaColors.Gray200)
                .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(CornerRadius.Medium)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(row.icon), contentDescription = null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(Spacing.S5))
        }
        Spacer(Modifier.width(Spacing.S4))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
            Text(
                if (isStatement) stringResource(R.string.credit_card_statement_title, row.title) else row.title,
                style = if (isStatement) FinovaType.TextSM else FinovaType.TextSMBold,
                color = FinovaColors.Gray700,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                val subtitle = row.statementTransactionCount?.let { count ->
                    stringResource(
                        if (count == 1) R.string.credit_card_statement_subtitle_singular else R.string.credit_card_statement_subtitle,
                        count,
                    )
                } ?: row.date.format(DateFormatter)
                Text(subtitle, style = FinovaType.TextXS, color = FinovaColors.Gray500)
                if (row.isCreditCard && !isStatement) {
                    Spacer(Modifier.width(Spacing.S1))
                    Icon(
                        painterResource(R.drawable.ic_lucide_icon_credit_card),
                        contentDescription = null,
                        tint = FinovaColors.MainMagenta,
                        modifier = Modifier.size(16.dp),
                    )
                }
            }
        }
        Spacer(Modifier.width(Spacing.S2))
        if (row.mode == TransactionModeUi.Recurring) {
            Icon(painterResource(R.drawable.ic_reload), contentDescription = null, tint = FinovaColors.Gray500, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(Spacing.S1))
        }
        Column(horizontalAlignment = Alignment.End) {
            Text(
                Money.annotated(row.amount, currencyCode, FinovaType.TextXS, valuesHidden),
                style = FinovaType.TitleMD,
                color = FinovaColors.Gray700,
            )
            if (row.mode == TransactionModeUi.Installments && row.installmentNumber != null) {
                Text("(${row.installmentNumber}/${row.totalInstallments})", style = FinovaType.TextXS, color = FinovaColors.Gray500)
            }
        }
        Spacer(Modifier.width(Spacing.S1))
        Icon(
            painterResource(if (row.isIncome) R.drawable.ic_arrow_up else R.drawable.ic_arrow_down),
            contentDescription = null,
            tint = if (row.isIncome) FinovaColors.MainGreen else FinovaColors.MainRed,
            modifier = Modifier.size(14.dp),
        )
        if (canDelete) {
            IconButton(onClick = onDelete, modifier = Modifier.size(40.dp)) {
                Icon(
                    painterResource(R.drawable.ic_trash),
                    contentDescription = stringResource(R.string.delete_action_label),
                    tint = FinovaColors.MainMagenta,
                    modifier = Modifier.size(Spacing.S4),
                )
            }
        } else {
            Spacer(Modifier.width(40.dp))
        }
    }
}

@Composable
private fun DeleteBackground() {
    Row(
        modifier = Modifier.fillMaxSize().background(FinovaColors.MainMagenta).padding(end = Spacing.S5),
        horizontalArrangement = Arrangement.End,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(painterResource(R.drawable.ic_trash), contentDescription = null, tint = FinovaColors.Gray100, modifier = Modifier.size(Spacing.S4))
        Spacer(Modifier.width(Spacing.S2))
        Text(stringResource(R.string.delete_action_label), style = FinovaType.ButtonSM, color = FinovaColors.Gray100)
    }
}

/** iOS `DateFormatter.fullDateFormatter`: always dd/MM/yyyy, whatever the language. */
private val DateFormatter: DateTimeFormatter = DateTimeFormatter.ofPattern("dd/MM/yyyy")
