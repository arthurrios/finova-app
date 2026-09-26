package com.arthurrios.finova.ui.components

import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale

/**
 * A money input. Port of the iOS `Input(type: .currency)`: the currency symbol sits inside the
 * field and digits fill from the right (1, 2, 3, 4 reads 0,01 → 0,12 → 1,23 → 12,34). The value is
 * the amount in minor units.
 */
@Composable
fun CurrencyTextField(
    cents: Long,
    onCentsChange: (Long) -> Unit,
    currencyCode: String,
    modifier: Modifier = Modifier,
    placeholder: String = "0,00",
    isError: Boolean = false,
    imeAction: ImeAction = ImeAction.Done,
    keyboardActions: KeyboardActions = KeyboardActions.Default,
) {
    FinovaTextField(
        value = if (cents == 0L) "" else cents.toString(),
        onValueChange = { text -> onCentsChange(text.filter(Char::isDigit).take(12).toLongOrNull() ?: 0L) },
        placeholder = placeholder,
        modifier = modifier,
        isError = isError,
        keyboardType = KeyboardType.Number,
        prefix = currencySymbol(currencyCode) + " ",
        visualTransformationOverride = CentsTransformation(currencyCode),
        imeAction = imeAction,
        keyboardActions = keyboardActions,
    )
}

fun currencySymbol(code: String): String =
    runCatching { Currency.getInstance(code).getSymbol(Locale.getDefault()) }.getOrDefault(code)

private class CentsTransformation(private val currencyCode: String) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        if (text.text.isEmpty()) return TransformedText(text, OffsetMapping.Identity)
        val digits = runCatching { Currency.getInstance(currencyCode).defaultFractionDigits }.getOrDefault(2).coerceAtLeast(0)
        val formatter = NumberFormat.getNumberInstance(Locale.getDefault()).apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
        }
        val shown = formatter.format(BigDecimal.valueOf(text.text.toLong(), digits))
        return TransformedText(
            AnnotatedString(shown),
            object : OffsetMapping {
                override fun originalToTransformed(offset: Int) = shown.length
                override fun transformedToOriginal(offset: Int) = text.text.length
            },
        )
    }
}
