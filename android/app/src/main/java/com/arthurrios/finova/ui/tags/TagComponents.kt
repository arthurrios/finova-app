package com.arthurrios.finova.ui.tags

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.tags.AllocationTag
import com.arthurrios.finova.domain.tags.AllocationTagPalette
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.theme.FinovaColors

val AllocationTagPalette.Entry.arcColor: Color get() = Color(arc)
val AllocationTagPalette.Entry.inkColor: Color get() = Color(ink)

/** The tag's icon: a category glyph, or the tag glyph by default. */
@Composable
fun TagIcon(tag: AllocationTag, tint: Color, size: Dp = 20.dp) {
    Icon(
        painterResource(tag.iconCategory?.icon(TransactionType.Expense) ?: R.drawable.ic_tag),
        contentDescription = null,
        tint = tint,
        modifier = Modifier.size(size),
    )
}

/**
 * Port of AllocationTagCreationPrompt: the one place a tag is created from (the Tags list and the
 * dashboard's + chip), so both behave the same.
 */
@Composable
fun CreateTagDialog(onCreate: (String) -> Unit, onDismiss: () -> Unit) {
    var name by rememberSaveable { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.tags_create_title)) },
        text = {
            Column {
                Text(stringResource(R.string.tags_create_message))
                androidx.compose.foundation.layout.Spacer(Modifier.size(12.dp))
                FinovaTextField(
                    value = name,
                    onValueChange = { name = it },
                    placeholder = stringResource(R.string.tags_create_placeholder),
                )
            }
        },
        confirmButton = {
            TextButton(enabled = name.isNotBlank(), onClick = { onCreate(name.trim()) }) {
                Text(stringResource(R.string.tags_create_button), color = if (name.isNotBlank()) FinovaColors.MainMagenta else FinovaColors.Gray400)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
