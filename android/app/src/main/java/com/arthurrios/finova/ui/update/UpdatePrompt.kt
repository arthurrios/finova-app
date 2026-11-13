package com.arthurrios.finova.ui.update

import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.content.edit
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.UpdateAvailability
import com.google.android.play.core.ktx.requestAppUpdateInfo

/** At most one prompt every six hours, as UpdateToastManager does on iOS. */
private const val COOLDOWN_MS = 6 * 60 * 60 * 1000L

/**
 * Port of the iOS update toast. iOS asks the App Store for the latest version; Android asks Google
 * Play, whose own screen then downloads and installs the update. Outside a Play install (the
 * emulator, a debug build) Play reports nothing, so no banner shows.
 */
@Composable
fun UpdatePrompt(enabled: Boolean) {
    val context = LocalContext.current
    var info by remember { mutableStateOf<AppUpdateInfo?>(null) }
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { }

    LaunchedEffect(enabled) {
        if (!enabled || !dueForPrompt(context)) return@LaunchedEffect
        info = runCatching { AppUpdateManagerFactory.create(context).requestAppUpdateInfo() }.getOrNull()
            ?.takeIf { it.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE && it.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE) }
            ?.also { markShown(context) }
    }

    AnimatedVisibility(visible = info != null, enter = slideInVertically { -it }, exit = slideOutVertically { -it }) {
        val shape = RoundedCornerShape(CornerRadius.ExtraLarge)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S1),
            modifier = Modifier
                .statusBarsPadding()
                .padding(Spacing.S4)
                .fillMaxWidth()
                .shadow(8.dp, shape)
                .clip(shape)
                .background(FinovaColors.Gray100)
                .border(1.dp, FinovaColors.Gray300, shape)
                .padding(start = Spacing.S5, end = Spacing.S3, top = Spacing.S4, bottom = Spacing.S2),
        ) {
            Text(stringResource(R.string.update_title), style = FinovaType.TitleSM, color = FinovaColors.Gray700)
            Text(stringResource(R.string.update_message), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                modifier = Modifier.padding(end = Spacing.S2))
            Row(horizontalArrangement = Arrangement.End, modifier = Modifier.fillMaxWidth()) {
                TextButton(onClick = { info = null }) { Text(stringResource(R.string.update_later), color = FinovaColors.Gray500) }
                TextButton(onClick = {
                    info?.let {
                        AppUpdateManagerFactory.create(context).startUpdateFlowForResult(
                            it, launcher, AppUpdateOptions.newBuilder(AppUpdateType.IMMEDIATE).build(),
                        )
                    }
                    info = null
                }) { Text(stringResource(R.string.update_now), color = FinovaColors.MainMagenta) }
            }
        }
    }
}

private fun prefs(context: Context) = context.getSharedPreferences("finova_update_prompt", Context.MODE_PRIVATE)
private fun dueForPrompt(context: Context) = System.currentTimeMillis() - prefs(context).getLong("last_shown", 0) >= COOLDOWN_MS
private fun markShown(context: Context) = prefs(context).edit { putLong("last_shown", System.currentTimeMillis()) }
