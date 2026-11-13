package com.arthurrios.finova.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Port of PaymentMethodOptionView: a 48dp tile with a radio, a title and a subtitle. iOS draws it
 * by hand; the radio inside is the Material one.
 */
@Composable
fun OptionTile(title: String, subtitle: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = androidx.compose.foundation.shape.RoundedCornerShape(com.arthurrios.finova.ui.theme.CornerRadius.Large)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .height(Spacing.InputHeight)
            .clip(shape)
            .background(FinovaColors.Gray200)
            .border(1.dp, if (selected) FinovaColors.MainMagenta else FinovaColors.Gray300, shape)
            .selectable(selected = selected, role = androidx.compose.ui.semantics.Role.RadioButton, onClick = onClick)
            .padding(horizontal = Spacing.S3),
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            colors = RadioButtonDefaults.colors(selectedColor = FinovaColors.MainMagenta, unselectedColor = FinovaColors.Gray400),
        )
        Spacer(Modifier.width(Spacing.S2))
        // The tile is half the sheet wide, so long labels ("Cartão de Crédito") shrink to fit
        // instead of wrapping or being cut, as on iOS.
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            BasicText(
                title,
                style = FinovaType.TextSMBold.copy(color = FinovaColors.Gray700),
                maxLines = 1,
                autoSize = TextAutoSize.StepBased(minFontSize = 8.sp, maxFontSize = FinovaType.TextSMBold.fontSize),
            )
            BasicText(
                subtitle,
                style = FinovaType.TextXS.copy(color = FinovaColors.Gray500),
                maxLines = 1,
                autoSize = TextAutoSize.StepBased(minFontSize = 7.sp, maxFontSize = FinovaType.TextXS.fontSize),
            )
        }
    }
}
