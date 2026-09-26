package com.arthurrios.finova.ui.tags

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.TransactionCategory
import com.arthurrios.finova.domain.model.TransactionType
import com.arthurrios.finova.domain.tags.AllocationTagPalette
import com.arthurrios.finova.ui.components.FinovaAccentOutlinedButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** The icons a tag can take: the category glyphs the app already ships, each once. */
private val IconChoices: List<TransactionCategory> =
    TransactionCategory.entries.distinctBy { it.icon(TransactionType.Expense) }

/**
 * Port of AllocationTagEditView/Controller. Colour and icon save on tap; the name saves on the way
 * out (back or Categories), and a blank name stops the user leaving, as on iOS.
 */
@Composable
fun AllocationTagEditScreen(viewModel: TagsViewModel, tagId: String, onBack: () -> Unit, onCategories: () -> Unit) {
    val book by viewModel.book.collectAsStateWithLifecycle()
    val tag = book.tag(tagId)
    var name by rememberSaveable { mutableStateOf(tag?.name.orEmpty()) }
    var nameRequired by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    // Deleted here or elsewhere: nothing left to edit.
    LaunchedEffect(tag == null) { if (tag == null) onBack() }
    if (tag == null) return

    fun commitName(): Boolean {
        if (name.isBlank()) {
            nameRequired = true
            return false
        }
        if (name.trim() != tag.name) viewModel.rename(tagId, name)
        return true
    }
    val leave = { if (commitName()) onBack() }
    BackHandler(onBack = leave)

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = stringResource(R.string.tags_edit_title), subtitle = null, onBack = leave)
        Column(
            verticalArrangement = Arrangement.spacedBy(Spacing.S5),
            modifier = Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(Spacing.S5),
        ) {
            Field(stringResource(R.string.tags_edit_name)) {
                FinovaTextField(value = name, onValueChange = { name = it }, placeholder = stringResource(R.string.tags_create_placeholder))
            }
            Field(stringResource(R.string.tags_edit_color)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    AllocationTagPalette.entries.forEachIndexed { index, entry ->
                        val selected = index == tag.colorIndex
                        // The ink tone: this form is on a light surface.
                        Box(
                            Modifier
                                .size(32.dp)
                                .clip(CircleShape)
                                .background(entry.inkColor)
                                .then(if (selected) Modifier.border(3.dp, FinovaColors.MainMagenta, CircleShape) else Modifier)
                                .clickable { viewModel.setColor(tagId, index) },
                        )
                    }
                }
            }
            Field(stringResource(R.string.tags_edit_icon)) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.horizontalScroll(rememberScrollState())) {
                    IconChoice(R.drawable.ic_tag, selected = tag.iconCategory == null) { viewModel.setIcon(tagId, null) }
                    IconChoices.forEach { category ->
                        IconChoice(category.icon(TransactionType.Expense), selected = tag.iconCategory == category) { viewModel.setIcon(tagId, category) }
                    }
                }
            }
            val shape = RoundedCornerShape(CornerRadius.Large)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clip(shape)
                    .background(FinovaColors.Gray100)
                    .border(1.dp, FinovaColors.Gray300, shape)
                    .clickable { if (commitName()) onCategories() }
                    .padding(horizontal = Spacing.S4),
            ) {
                Text(stringResource(R.string.tags_edit_categories), style = FinovaType.TextSMBold, color = FinovaColors.Gray700, modifier = Modifier.weight(1f))
                Text(book.categoryCount(tagId).toString(), style = FinovaType.TextSM, color = FinovaColors.Gray500)
                Spacer(Modifier.width(Spacing.S2))
                Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(12.dp))
            }
        }
        HorizontalDivider(color = FinovaColors.Gray300)
        Column(Modifier.background(FinovaColors.Gray100).navigationBarsPadding().padding(Spacing.S4)) {
            FinovaAccentOutlinedButton(text = stringResource(R.string.tags_edit_delete), onClick = { confirmDelete = true })
        }
    }

    if (nameRequired) {
        AlertDialog(
            onDismissRequest = { nameRequired = false },
            title = { Text(stringResource(R.string.tags_name_required_title)) },
            text = { Text(stringResource(R.string.tags_name_required_message)) },
            confirmButton = { TextButton(onClick = { nameRequired = false }) { Text(stringResource(R.string.alert_ok)) } },
        )
    }
    if (confirmDelete) {
        DeleteTagDialog(
            onConfirm = {
                confirmDelete = false
                viewModel.delete(tagId)
            },
            onDismiss = { confirmDelete = false },
        )
    }
}

@Composable
private fun Field(label: String, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
        Text(label, style = FinovaType.TextSM, color = FinovaColors.Gray600)
        content()
    }
}

@Composable
private fun IconChoice(icon: Int, selected: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(32.dp)
            .clip(CircleShape)
            .background(FinovaColors.Gray200)
            .border(if (selected) 3.dp else 1.dp, if (selected) FinovaColors.MainMagenta else FinovaColors.Gray300, CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = if (selected) FinovaColors.MainMagenta else FinovaColors.Gray500, modifier = Modifier.size(16.dp))
    }
}
