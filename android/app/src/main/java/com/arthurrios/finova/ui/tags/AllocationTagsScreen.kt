package com.arthurrios.finova.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DragIndicator
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.tags.AllocationTag
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.dashboard.DeleteBackground
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

private val RowHeight = 64.dp
private val CardShape = RoundedCornerShape(CornerRadius.ExtraLarge)

/**
 * Port of AllocationTagsView/Controller: the tag list. Tap edits, swipe left deletes (after a
 * confirmation), and touch-and-hold then drag reorders, as on iOS.
 */
@Composable
fun AllocationTagsScreen(viewModel: TagsViewModel, onBack: () -> Unit, onEdit: (String) -> Unit) {
    val book by viewModel.book.collectAsStateWithLifecycle()
    var creating by remember { mutableStateOf(false) }
    var pendingDelete by remember { mutableStateOf<AllocationTag?>(null) }

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200)) {
        ScreenHeader(
            title = stringResource(R.string.tags_title),
            subtitle = stringResource(R.string.tags_subtitle),
            onBack = onBack,
            trailing = {
                IconButton(onClick = { creating = true }) {
                    Icon(painterResource(R.drawable.ic_plus), contentDescription = stringResource(R.string.tags_create_title), tint = FinovaColors.MainMagenta)
                }
            },
        )
        if (book.isEmpty) {
            Column(
                Modifier.fillMaxSize().padding(Spacing.S8),
                verticalArrangement = Arrangement.Center,
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Icon(painterResource(R.drawable.ic_tag), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(40.dp))
                Spacer(Modifier.height(Spacing.S4))
                Text(stringResource(R.string.tags_empty), style = FinovaType.TextSM, color = FinovaColors.Gray500,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        } else {
            ReorderableTagList(
                tags = book.orderedTags,
                categoryCount = book::categoryCount,
                onEdit = onEdit,
                onDelete = { pendingDelete = it },
                onReorder = viewModel::reorder,
            )
        }
    }

    if (creating) {
        CreateTagDialog(
            onCreate = { name ->
                creating = false
                // Straight into editing: a tag with no categories does nothing.
                viewModel.create(name)?.let { onEdit(it.id) }
            },
            onDismiss = { creating = false },
        )
    }
    pendingDelete?.let { tag ->
        DeleteTagDialog(
            onConfirm = {
                pendingDelete = null
                viewModel.delete(tag.id)
            },
            onDismiss = { pendingDelete = null },
        )
    }
}

@Composable
private fun ReorderableTagList(
    tags: List<AllocationTag>,
    categoryCount: (String) -> Int,
    onEdit: (String) -> Unit,
    onDelete: (AllocationTag) -> Unit,
    onReorder: (List<String>) -> Unit,
) {
    // A local copy moves under the finger; the new order is saved when the finger lifts.
    var order by remember(tags) { mutableStateOf(tags) }
    var draggingId by remember { mutableStateOf<String?>(null) }
    var dragOffset by remember { mutableFloatStateOf(0f) }
    val step = with(LocalDensity.current) { (RowHeight + 1.dp).toPx() }
    val reorderable = order.size > 1
    fun finishDrag() {
        draggingId = null
        dragOffset = 0f
        if (order.map { it.id } != tags.map { it.id }) onReorder(order.map { it.id })
    }

    LazyColumn(
        contentPadding = PaddingValues(Spacing.S4),
        modifier = Modifier.fillMaxSize().navigationBarsPadding(),
    ) {
        item {
            Column(Modifier.clip(CardShape).background(FinovaColors.Gray100).border(1.dp, FinovaColors.Gray300, CardShape)) {
                order.forEachIndexed { index, tag ->
                    val dragging = tag.id == draggingId
                    Box(
                        Modifier
                            .zIndex(if (dragging) 1f else 0f)
                            .graphicsLayer {
                                translationY = if (dragging) dragOffset else 0f
                                shadowElevation = if (dragging) 8f else 0f
                            }
                            .pointerInput(tag.id, reorderable) {
                                if (!reorderable) return@pointerInput
                                detectDragGesturesAfterLongPress(
                                    onDragStart = { draggingId = tag.id; dragOffset = 0f },
                                    onDrag = { change, amount ->
                                        change.consume()
                                        dragOffset += amount.y
                                        val at = order.indexOfFirst { it.id == draggingId }
                                        if (dragOffset > step / 2 && at < order.lastIndex) {
                                            order = order.toMutableList().apply { add(at + 1, removeAt(at)) }
                                            dragOffset -= step
                                        } else if (dragOffset < -step / 2 && at > 0) {
                                            order = order.toMutableList().apply { add(at - 1, removeAt(at)) }
                                            dragOffset += step
                                        }
                                    },
                                    // A cancelled drag still leaves the rows where the user put them, so both save.
                                    onDragEnd = { finishDrag() },
                                    onDragCancel = { finishDrag() },
                                )
                            },
                    ) {
                        TagRow(tag, categoryCount(tag.id), reorderable, onClick = { onEdit(tag.id) }, onDelete = { onDelete(tag) })
                    }
                    if (index < order.lastIndex) HorizontalDivider(color = FinovaColors.Gray300)
                }
            }
        }
    }
}

@Composable
private fun TagRow(tag: AllocationTag, categoryCount: Int, reorderable: Boolean, onClick: () -> Unit, onDelete: () -> Unit) {
    val currentOnDelete by rememberUpdatedState(onDelete)
    @Suppress("DEPRECATION")
    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { value ->
            if (value == SwipeToDismissBoxValue.EndToStart) currentOnDelete()
            false
        },
        positionalThreshold = { width -> width * 0.5f },
    )
    SwipeToDismissBox(state = dismissState, enableDismissFromStartToEnd = false, backgroundContent = { DeleteBackground() }) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier
                .fillMaxWidth()
                .height(RowHeight)
                .background(FinovaColors.Gray100)
                .clickable(onClick = onClick)
                .padding(horizontal = Spacing.S4),
        ) {
            if (reorderable) {
                Icon(Icons.Filled.DragIndicator, contentDescription = stringResource(R.string.tags_reorder_hint),
                    tint = FinovaColors.Gray400, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(Spacing.S2))
            }
            Box(
                Modifier.size(32.dp).clip(CircleShape).background(tag.color.inkColor.copy(alpha = 0.12f)),
                contentAlignment = Alignment.Center,
            ) { TagIcon(tag, tint = tag.color.inkColor, size = 18.dp) }
            Spacer(Modifier.width(Spacing.S3))
            Column(Modifier.weight(1f)) {
                Text(tag.name, style = FinovaType.TitleSM, color = FinovaColors.Gray700, maxLines = 1)
                Text(
                    if (categoryCount == 0) stringResource(R.string.tags_no_categories)
                    else pluralStringResource(R.plurals.tags_category_count, categoryCount, categoryCount),
                    style = FinovaType.TextXS, color = FinovaColors.Gray500,
                )
            }
            Icon(painterResource(R.drawable.ic_chevron_right), contentDescription = null, tint = FinovaColors.Gray400, modifier = Modifier.size(12.dp))
        }
    }
}

/** "Only the grouping is removed": deleting a lens must not read as deleting the money behind it. */
@Composable
fun DeleteTagDialog(onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.tags_delete_title)) },
        text = { Text(stringResource(R.string.tags_delete_message)) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(stringResource(R.string.alert_delete), color = FinovaColors.MainRed) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
