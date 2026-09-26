package com.arthurrios.finova.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
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
import com.arthurrios.finova.domain.tags.AllocationTag
import com.arthurrios.finova.domain.tags.AllocationTagBook
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.icon
import com.arthurrios.finova.ui.dashboard.label
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/**
 * Port of AllocationTagCategoriesView/Controller: tick the categories a tag covers. A category in
 * another tag asks first, because that tag silently loses it.
 */
@Composable
fun AllocationTagCategoriesScreen(viewModel: TagsViewModel, tagId: String, onBack: () -> Unit) {
    val book by viewModel.book.collectAsStateWithLifecycle()
    val tag = book.tag(tagId) ?: return
    var moving by remember { mutableStateOf<Pair<TransactionCategory, AllocationTag>?>(null) }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(title = tag.name, subtitle = stringResource(R.string.tags_categories_subtitle), onBack = onBack)
        val shape = RoundedCornerShape(CornerRadius.ExtraLarge)
        LazyColumn(contentPadding = PaddingValues(Spacing.S4), modifier = Modifier.fillMaxSize().navigationBarsPadding()) {
            item {
                Column(Modifier.clip(shape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, shape)) {
                    val categories = AllocationTagBook.taggableCategories
                    categories.forEachIndexed { index, category ->
                        val owner = book.tagFor(category)
                        CategoryRow(category, selected = owner?.id == tagId, otherTag = owner?.takeIf { it.id != tagId }?.name) {
                            if (owner != null && owner.id != tagId) moving = category to owner else viewModel.toggle(tagId, category)
                        }
                        if (index < categories.lastIndex) HorizontalDivider(color = FinovaColors.Gray300)
                    }
                }
            }
        }
    }

    moving?.let { (category, owner) ->
        val categoryName = stringResource(category.label)
        AlertDialog(
            onDismissRequest = { moving = null },
            title = { Text(stringResource(R.string.tags_move_title)) },
            text = { Text(stringResource(R.string.tags_move_message, categoryName, owner.name)) },
            confirmButton = {
                TextButton(onClick = {
                    moving = null
                    viewModel.toggle(tagId, category)
                }) { Text(stringResource(R.string.tags_move_button), color = FinovaColors.MainMagenta) }
            },
            dismissButton = { TextButton(onClick = { moving = null }) { Text(stringResource(R.string.alert_cancel)) } },
        )
    }
}

@Composable
private fun CategoryRow(category: TransactionCategory, selected: Boolean, otherTag: String?, onClick: () -> Unit) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().height(56.dp).clickable(onClick = onClick).padding(horizontal = Spacing.S4),
    ) {
        val iconShape = RoundedCornerShape(CornerRadius.Medium)
        Box(
            Modifier.size(32.dp).clip(iconShape).background(FinovaColors.Gray200).border(1.dp, FinovaColors.Gray300, iconShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(painterResource(category.icon(TransactionType.Expense)), contentDescription = null,
                tint = if (selected) FinovaColors.MainMagenta else FinovaColors.Gray500, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(Spacing.S3))
        Column(Modifier.weight(1f)) {
            Text(stringResource(category.label), style = FinovaType.TextSMBold, color = FinovaColors.Gray700)
            otherTag?.let { Text(stringResource(R.string.tags_in_other, it), style = FinovaType.TextXS, color = FinovaColors.Gray500) }
        }
        if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = FinovaColors.MainMagenta, modifier = Modifier.size(20.dp))
    }
}
