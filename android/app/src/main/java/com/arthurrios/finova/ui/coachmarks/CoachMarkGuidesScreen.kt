package com.arthurrios.finova.ui.coachmarks

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.coachmarks.CoachMarkGuideId
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Every guide, for anyone, at any time. A row starts its guide on the dashboard; a check mark says
 * the setup behind it is done, not that the row is used up.
 */
@Composable
fun CoachMarkGuidesScreen(center: CoachMarkCenter, onBack: () -> Unit) {
    var done by remember { mutableStateOf<Set<CoachMarkGuideId>>(emptySet()) }
    var reloads by remember { mutableIntStateOf(0) }
    LifecycleResumeEffect(Unit) {
        reloads++
        onPauseOrDispose { }
    }
    LaunchedEffect(reloads) { done = center.doneGuides() }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.settings_guides_title), subtitle = null, onBack = onBack)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S3),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(Spacing.S4),
        ) {
            CoachMarkGuideId.entries.forEach { guide ->
                GuideRow(guide, isDone = guide in done, onClick = { center.startReplay(guide) })
            }
            Text(
                stringResource(R.string.settings_guides_footer),
                style = FinovaType.TextXS,
                color = FinovaColors.Gray500,
                modifier = Modifier.padding(horizontal = Spacing.S2),
            )
        }
    }
}

@Composable
private fun GuideRow(guide: CoachMarkGuideId, isDone: Boolean, onClick: () -> Unit) {
    val doneLabel = stringResource(R.string.settings_guides_done)
    ListItem(
        headlineContent = { Text(keyText(guide.titleKey), style = FinovaType.TitleSM) },
        supportingContent = { Text(keyText(guide.subtitleKey), style = FinovaType.TextXS) },
        trailingContent = {
            if (isDone) {
                Icon(Icons.Filled.CheckCircle, contentDescription = null, tint = FinovaColors.MainGreen, modifier = Modifier.size(Spacing.S5))
            } else {
                Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(Spacing.S3))
            }
        },
        colors = ListItemDefaults.colors(
            containerColor = FinovaColors.Gray100,
            headlineColor = FinovaColors.Gray700,
            supportingColor = FinovaColors.Gray500,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(CornerRadius.Large))
            .clickable(onClick = onClick)
            .semantics { if (isDone) stateDescription = doneLabel },
    )
}
