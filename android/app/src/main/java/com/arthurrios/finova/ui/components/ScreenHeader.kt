package com.arthurrios.finova.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * The header of the pushed iOS screens (Budgets, Settings…): a round back button, an uppercase
 * title with a subtitle, and an optional round action on the right. Hand-built on iOS too.
 */
@Composable
fun ScreenHeader(
    title: String,
    subtitle: String?,
    onBack: () -> Unit,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(FinovaColors.Gray100)
            .statusBarsPadding()
            .padding(start = Spacing.S5, end = Spacing.S5, top = Spacing.S3, bottom = Spacing.S6),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RoundIconButton(onClick = onBack) {
            Icon(painterResource(R.drawable.ic_chevron_left), contentDescription = stringResource(R.string.back),
                tint = FinovaColors.Gray700, modifier = Modifier.size(16.dp))
        }
        Spacer(Modifier.width(Spacing.S4))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
            Text(title.uppercase(), style = FinovaType.TitleSM, color = FinovaColors.Gray700)
            if (subtitle != null) Text(subtitle, style = FinovaType.TextSM, color = FinovaColors.Gray500)
        }
        if (trailing != null) {
            Spacer(Modifier.width(Spacing.S3))
            trailing()
        }
    }
}

/** The white round button the iOS headers use (glass on iOS 26). */
@Composable
fun RoundIconButton(onClick: () -> Unit, content: @Composable () -> Unit) {
    FilledIconButton(
        onClick = onClick,
        shape = CircleShape,
        colors = IconButtonDefaults.filledIconButtonColors(containerColor = FinovaColors.Gray200, contentColor = FinovaColors.Gray700),
        modifier = Modifier.size(Spacing.S10),
        content = content,
    )
}
