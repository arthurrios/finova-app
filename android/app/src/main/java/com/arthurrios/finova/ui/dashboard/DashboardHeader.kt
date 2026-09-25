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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** The top bar: avatar, greeting, account label and the notification bell. Port of DashboardView. */
@Composable
fun DashboardHeader(
    userName: String,
    unreadNotifications: Int,
    onProfile: () -> Unit,
    onNotifications: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(FinovaColors.Gray100)
            .statusBarsPadding()
            .padding(start = Spacing.S5, end = Spacing.S3, top = Spacing.S3, bottom = Spacing.S6),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .clip(CircleShape)
                .clickable(onClick = onProfile),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Avatar()
            Spacer(Modifier.width(Spacing.S3))
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                Text(
                    text = stringResource(R.string.dashboard_welcome_title, userName).uppercase(),
                    style = FinovaType.TitleSM,
                    color = FinovaColors.Gray700,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = stringResource(R.string.dashboard_context_label),
                        style = FinovaType.TextSM,
                        color = FinovaColors.MainMagenta,
                    )
                    Spacer(Modifier.width(Spacing.S1))
                    Icon(
                        painter = painterResource(R.drawable.ic_chevron_right),
                        contentDescription = null,
                        tint = FinovaColors.MainMagenta,
                        modifier = Modifier.size(10.dp),
                    )
                }
            }
        }
        IconButton(onClick = onNotifications) {
            BadgedBox(
                badge = {
                    if (unreadNotifications > 0) {
                        Badge(
                            containerColor = FinovaColors.MainMagenta,
                            contentColor = FinovaColors.Gray100,
                            modifier = Modifier.border(2.dp, FinovaColors.Gray100, CircleShape),
                        ) {
                            Text(if (unreadNotifications > 99) "99+" else unreadNotifications.toString(), fontSize = 10.sp)
                        }
                    }
                },
            ) {
                Icon(
                    painter = painterResource(R.drawable.ic_bell),
                    contentDescription = stringResource(R.string.dashboard_notifications),
                    tint = FinovaColors.Gray500,
                    modifier = Modifier.size(24.dp),
                )
            }
        }
    }
}

/** Port of Avatar.swift: a gray circle with a thin dark ring and the user glyph. */
@Composable
fun Avatar(modifier: Modifier = Modifier, size: androidx.compose.ui.unit.Dp = 40.dp) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(FinovaColors.Gray300)
            .border(BorderStroke(1.dp, FinovaColors.Gray700), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            painter = painterResource(R.drawable.ic_user),
            contentDescription = null,
            tint = FinovaColors.Gray500,
            modifier = Modifier.size(size / 2),
        )
    }
}
