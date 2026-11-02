package com.arthurrios.finova.ui.coachmarks

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * The small strip that reminds a new user of a setup they left. It floats over the list rather than
 * pushing it down, and it asks for nothing: `CoachMarkGating.reminderGuide` decides when it shows.
 */
@Composable
fun CoachMarkReminderBanner(guide: CoachMarkGuideId, onOpen: () -> Unit, onDismiss: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(CornerRadius.ExtraLarge)
    Surface(shape = shape, color = FinovaColors.Gray100, shadowElevation = 4.dp, modifier = modifier.fillMaxWidth()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                stringResource(R.string.coach_marks_reminder_title, keyText(guide.titleKey)),
                style = FinovaType.TextSMBold,
                color = FinovaColors.Gray700,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = 44.dp)
                    .clip(shape)
                    .clickable(onClick = onOpen)
                    .padding(start = Spacing.S4, end = Spacing.S2, top = Spacing.S3, bottom = Spacing.S3),
            )
            IconButton(onClick = onDismiss) {
                Icon(
                    painterResource(R.drawable.ic_x),
                    contentDescription = stringResource(R.string.coach_marks_reminder_dismiss),
                    tint = FinovaColors.Gray500,
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}
