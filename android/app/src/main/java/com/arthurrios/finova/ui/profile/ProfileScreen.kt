package com.arthurrios.finova.ui.profile

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CreditCard
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.Avatar
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Port of ProfileView ("My Account"): the user, then Financial, General and Account sections. */
@Composable
fun ProfileScreen(
    viewModel: ProfileViewModel,
    onBack: () -> Unit,
    onCreditCards: () -> Unit,
    onSettings: () -> Unit,
    onLoggedOut: () -> Unit,
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var confirmLogout by rememberSaveable { mutableStateOf(false) }
    // The system photo picker: no storage permission needed.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) viewModel.setPhoto(uri)
    }
    val pickPhoto = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    LifecycleResumeEffect(Unit) {
        viewModel.reload()
        onPauseOrDispose { }
    }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.profile_title), subtitle = null, onBack = onBack)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S4),
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .navigationBarsPadding()
                .padding(Spacing.S4),
        ) {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.S1),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(CornerRadius.ExtraLarge))
                    .background(FinovaColors.Gray100)
                    .padding(Spacing.S6),
            ) {
                Box(Modifier.clickable(onClick = pickPhoto)) {
                    Avatar(size = 80.dp, image = remember(state.photo) { state.photo?.asImageBitmap() })
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .offset(x = 2.dp, y = 2.dp)
                            .size(24.dp)
                            .clip(CircleShape)
                            .background(FinovaColors.MainMagenta),
                    ) {
                        Icon(Icons.Outlined.Edit, contentDescription = stringResource(R.string.profile_change_photo),
                            tint = FinovaColors.Gray100, modifier = Modifier.size(12.dp))
                    }
                }
                Spacer(Modifier.height(Spacing.S2))
                Text(state.name, style = FinovaType.TextSMBold, color = FinovaColors.Gray700, textAlign = TextAlign.Center)
                Text(state.email, style = FinovaType.TextXS, color = FinovaColors.Gray500, textAlign = TextAlign.Center)
            }
            SectionHeader(stringResource(R.string.profile_section_financial))
            SettingRow(Icons.Outlined.CreditCard, stringResource(R.string.credit_cards_title), onClick = onCreditCards)
            SectionHeader(stringResource(R.string.profile_section_general))
            SettingRow(Icons.Outlined.Settings, stringResource(R.string.profile_settings), onClick = onSettings)
            SectionHeader(stringResource(R.string.profile_section_account))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clip(RoundedCornerShape(CornerRadius.Large))
                    .background(FinovaColors.Gray100)
                    .clickable { confirmLogout = true }
                    .padding(horizontal = Spacing.S4),
            ) {
                Icon(painterResource(R.drawable.ic_logout), contentDescription = null, tint = FinovaColors.MainRed, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(Spacing.S3))
                Text(stringResource(R.string.profile_logout), style = FinovaType.TitleSM, color = FinovaColors.MainRed)
            }
            Text(
                viewModel.appVersion,
                style = FinovaType.TextXS,
                color = FinovaColors.Gray400,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = Spacing.S2),
            )
        }
    }

    if (confirmLogout) {
        AlertDialog(
            onDismissRequest = { confirmLogout = false },
            title = { Text(stringResource(R.string.profile_logout)) },
            text = { Text(stringResource(R.string.profile_logout_message)) },
            confirmButton = {
                TextButton(onClick = {
                    confirmLogout = false
                    viewModel.logout()
                    onLoggedOut()
                }) { Text(stringResource(R.string.profile_logout), color = FinovaColors.MainRed) }
            },
            dismissButton = { TextButton(onClick = { confirmLogout = false }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title.uppercase(),
        style = FinovaType.TextXS,
        color = FinovaColors.Gray500,
        modifier = Modifier.padding(start = Spacing.S2, top = Spacing.S2),
    )
}

/** A 56dp settings row: icon, label, chevron. */
@Composable
fun SettingRow(icon: ImageVector, label: String, value: String? = null, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .clip(RoundedCornerShape(CornerRadius.Large))
            .background(FinovaColors.Gray100)
            .clickable(onClick = onClick)
            .padding(horizontal = Spacing.S4),
    ) {
        Icon(icon, contentDescription = null, tint = FinovaColors.Gray600, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(Spacing.S3))
        Text(label, style = FinovaType.TitleSM, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
        if (value != null) {
            Text(value, style = FinovaType.TextSM, color = FinovaColors.Gray500)
            Spacer(Modifier.width(Spacing.S2))
        }
        Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(12.dp))
    }
}
