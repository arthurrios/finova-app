package com.arthurrios.finova.ui.cards

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.arthurrios.finova.R
import com.arthurrios.finova.domain.model.CardBrand
import com.arthurrios.finova.domain.model.CardColor
import com.arthurrios.finova.ui.components.CurrencyTextField
import com.arthurrios.finova.ui.components.FinovaButton
import com.arthurrios.finova.ui.components.FinovaTextField
import com.arthurrios.finova.ui.components.ScreenHeader
import com.arthurrios.finova.ui.theme.CornerRadius
import com.arthurrios.finova.ui.theme.FinovaColors
import com.arthurrios.finova.ui.theme.FinovaType
import com.arthurrios.finova.ui.theme.Spacing

/** Port of AddCreditCardView: one form card, Save pinned at the bottom. Also edits a card. */
@Composable
fun AddCreditCardScreen(viewModel: AddCreditCardViewModel, onBack: () -> Unit, onSaved: () -> Unit) {
    val form by viewModel.form.collectAsState()
    val errors = form.showErrors

    Column(Modifier.fillMaxSize().background(FinovaColors.Gray200).imePadding()) {
        ScreenHeader(
            title = stringResource(if (viewModel.isEditMode) R.string.edit_card_title else R.string.add_card_title),
            subtitle = null,
            onBack = onBack,
        )
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(Spacing.S4),
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(Spacing.S5),
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(CornerRadius.ExtraLarge))
                    .background(FinovaColors.Gray100)
                    .border(1.dp, FinovaColors.Gray300, RoundedCornerShape(CornerRadius.ExtraLarge))
                    .padding(Spacing.S5),
            ) {
                Field(stringResource(R.string.add_card_name)) {
                    FinovaTextField(
                        value = form.name,
                        onValueChange = { v -> viewModel.edit { it.copy(name = v) } },
                        placeholder = stringResource(R.string.add_card_name_placeholder),
                        isError = errors && form.nameError,
                        imeAction = ImeAction.Next,
                    )
                }
                Field(stringResource(R.string.add_card_last_four), stringResource(R.string.add_card_last_four_hint)) {
                    FinovaTextField(
                        value = form.lastFour,
                        onValueChange = { v -> viewModel.edit { it.copy(lastFour = v.filter(Char::isDigit).take(4)) } },
                        placeholder = "1234",
                        isError = errors && form.lastFourError,
                        keyboardType = KeyboardType.NumberPassword,
                        imeAction = ImeAction.Done,
                    )
                }
                Field(stringResource(R.string.add_card_brand)) {
                    DropdownField(
                        text = stringResource(form.brand.label),
                        placeholder = stringResource(CardBrand.Visa.label),
                        options = CardBrand.entries,
                        optionLabel = { stringResource(it.label) },
                        onSelect = { b -> viewModel.edit { it.copy(brand = b) } },
                    )
                }
                Field(stringResource(R.string.add_card_closing_day), stringResource(R.string.add_card_closing_day_hint)) {
                    DropdownField(
                        text = form.closingDay?.toString().orEmpty(),
                        placeholder = "15",
                        options = Days,
                        optionLabel = { it.toString() },
                        isError = errors && form.closingDayError,
                        onSelect = { d -> viewModel.edit { it.copy(closingDay = d) } },
                    )
                }
                Field(stringResource(R.string.add_card_due_day), stringResource(R.string.add_card_due_day_hint)) {
                    DropdownField(
                        text = form.dueDay?.toString().orEmpty(),
                        placeholder = "22",
                        options = Days,
                        optionLabel = { it.toString() },
                        isError = errors && form.dueDayError,
                        onSelect = { d -> viewModel.edit { it.copy(dueDay = d) } },
                    )
                }
                Field(stringResource(R.string.add_card_limit)) {
                    CurrencyTextField(
                        cents = form.creditLimit,
                        onCentsChange = { c -> viewModel.edit { it.copy(creditLimit = c) } },
                        currencyCode = viewModel.currencyCode,
                    )
                }
                Field(stringResource(R.string.add_card_color)) {
                    ColorPicker(form.color) { c -> viewModel.edit { it.copy(color = c) } }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
                        Text(stringResource(R.string.add_card_default), style = FinovaType.TextSM, color = FinovaColors.Gray600)
                        Text(stringResource(R.string.add_card_default_hint), style = FinovaType.TextXS, color = FinovaColors.Gray400)
                    }
                    Spacer(Modifier.width(Spacing.S3))
                    Switch(
                        checked = form.isDefault,
                        onCheckedChange = { on -> viewModel.edit { it.copy(isDefault = on) } },
                        colors = SwitchDefaults.colors(checkedTrackColor = FinovaColors.MainMagenta),
                    )
                }
            }
        }
        HorizontalDivider(color = FinovaColors.Gray300)
        Box(Modifier.background(FinovaColors.Gray100).navigationBarsPadding().padding(Spacing.S4)) {
            FinovaButton(
                text = stringResource(if (viewModel.isEditMode) R.string.edit_card_save else R.string.add_card_save),
                onClick = { viewModel.save(onSaved) },
            )
        }
    }
}

private val Days = (1..28).toList()

@Composable
private fun Field(label: String, hint: String? = null, content: @Composable () -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.S1)) {
        Text(label, style = FinovaType.TextSM, color = FinovaColors.Gray600)
        content()
        if (hint != null) Text(hint, style = FinovaType.TextXS, color = FinovaColors.Gray400)
    }
}

/** iOS uses a wheel picker in the keyboard's place; the Material dropdown is the Android match. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun <T> DropdownField(
    text: String,
    placeholder: String,
    options: List<T>,
    optionLabel: @Composable (T) -> String,
    onSelect: (T) -> Unit,
    isError: Boolean = false,
) {
    var expanded by remember { mutableStateOf(false) }
    ExposedDropdownMenuBox(expanded = expanded, onExpandedChange = { expanded = it }) {
        FinovaTextField(
            value = text,
            onValueChange = {},
            placeholder = placeholder,
            isError = isError,
            onClick = { expanded = true },
            modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            containerColor = FinovaColors.Gray100,
            modifier = Modifier.heightIn(max = 320.dp),
        ) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(optionLabel(option), style = FinovaType.Input) },
                    onClick = {
                        expanded = false
                        onSelect(option)
                    },
                )
            }
        }
    }
}

/** A row of the eight card colours; the picked one gets a magenta ring, as on iOS. */
@Composable
private fun ColorPicker(selected: CardColor, onSelect: (CardColor) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.S3), modifier = Modifier.fillMaxWidth()) {
        CardColor.entries.forEach { color ->
            val name = stringResource(color.label)
            Box(
                modifier = Modifier
                    .weight(1f)
                    .aspectRatio(1f)
                    .clip(CircleShape)
                    .background(color.start)
                    .then(
                        if (color == selected) Modifier.border(BorderStroke(3.dp, FinovaColors.MainMagenta), CircleShape)
                        else Modifier
                    )
                    .clickable(role = Role.RadioButton) { onSelect(color) }
                    .semantics {
                        contentDescription = name
                        this.selected = color == selected
                    },
            )
        }
    }
}
