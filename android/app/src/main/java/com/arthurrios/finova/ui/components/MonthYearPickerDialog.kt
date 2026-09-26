package com.arthurrios.finova.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringArrayResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing
import java.time.YearMonth

/**
 * Picks a month. iOS uses the system month/year wheel; Android has no month picker, so this is a
 * Material dialog with a year stepper and a grid of the twelve months.
 */
@Composable
fun MonthYearPickerDialog(initial: YearMonth, onPick: (YearMonth) -> Unit, onDismiss: () -> Unit) {
    var year by rememberSaveable { mutableStateOf(initial.year) }
    var month by rememberSaveable { mutableStateOf(initial.monthValue) }
    val names = stringArrayResource(R.array.month_short)
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = FinovaColors.Gray100,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { year-- }) {
                    Icon(painterResource(R.drawable.ic_chevron_left), stringResource(R.string.month_picker_previous_year), Modifier.size(16.dp))
                }
                Text(year.toString(), style = FinovaType.TitleMD, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
                IconButton(onClick = { year++ }) {
                    Icon(painterResource(R.drawable.ic_chevron_right), stringResource(R.string.month_picker_next_year), Modifier.size(16.dp))
                }
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.S2)) {
                (0 until 4).forEach { row ->
                    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S2), modifier = Modifier.fillMaxWidth()) {
                        (1..3).forEach { col ->
                            val value = row * 3 + col
                            FilterChip(
                                selected = month == value,
                                onClick = { month = value },
                                label = { Text(names[value - 1], modifier = Modifier.fillMaxWidth(), textAlign = TextAlign.Center) },
                                colors = FilterChipDefaults.filterChipColors(
                                    selectedContainerColor = FinovaColors.MainMagenta,
                                    selectedLabelColor = FinovaColors.Gray100,
                                ),
                                modifier = Modifier.weight(1f).height(40.dp),
                            )
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = { onPick(YearMonth.of(year, month)) }) { Text(stringResource(R.string.alert_ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.alert_cancel)) } },
    )
}
