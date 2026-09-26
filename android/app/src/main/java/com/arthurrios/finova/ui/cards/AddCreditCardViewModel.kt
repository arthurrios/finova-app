package com.arthurrios.finova.ui.cards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.domain.model.CardBrand
import com.arthurrios.finova.domain.model.CardColor
import com.arthurrios.finova.domain.model.CreditCard
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the form holds. Days are null until picked, as the iOS pickers start empty. */
data class CardForm(
    val name: String = "",
    val lastFour: String = "",
    val brand: CardBrand = CardBrand.Visa,
    val closingDay: Int? = null,
    val dueDay: Int? = null,
    val creditLimit: Long = 0,
    val color: CardColor = CardColor.Blue,
    val isDefault: Boolean = false,
    /** Set after a failed save, so errors show only once the user tried. */
    val showErrors: Boolean = false,
) {
    val nameError: Boolean get() = name.isBlank()
    val lastFourError: Boolean get() = lastFour.length != 4
    val closingDayError: Boolean get() = closingDay == null
    val dueDayError: Boolean get() = dueDay == null
    val isValid: Boolean get() = !nameError && !lastFourError && !closingDayError && !dueDayError
}

/** Port of AddCreditCardViewModel plus the validation in AddCreditCardView. */
class AddCreditCardViewModel(
    private val cards: CardRepository,
    private val settings: UserSettingsStore,
    private val editingId: Long?,
) : ViewModel() {
    private var editing: CreditCard? = null
    val isEditMode: Boolean get() = editingId != null
    val currencyCode: String get() = settings.currencyCode

    private val _form = MutableStateFlow(CardForm())
    val form: StateFlow<CardForm> = _form.asStateFlow()

    init {
        if (editingId != null) viewModelScope.launch {
            cards.card(editingId)?.let { card ->
                editing = card
                _form.value = CardForm(
                    name = card.name,
                    lastFour = card.lastFourDigits,
                    brand = card.brand,
                    closingDay = card.closingDay,
                    dueDay = card.dueDay,
                    creditLimit = card.creditLimit ?: 0,
                    color = card.color,
                    isDefault = card.isDefault,
                )
            }
        }
    }

    fun edit(change: (CardForm) -> CardForm) = _form.update(change)

    /** Returns false and turns the errors on when the form is not complete. */
    fun save(onSaved: () -> Unit) {
        val f = _form.value
        if (!f.isValid) {
            _form.update { it.copy(showErrors = true) }
            return
        }
        val card = (editing ?: CreditCard(name = "", lastFourDigits = "", closingDay = 1, dueDay = 1)).copy(
            name = f.name.trim(),
            lastFourDigits = f.lastFour,
            brand = f.brand,
            closingDay = f.closingDay!!,
            dueDay = f.dueDay!!,
            // An empty limit field means no limit, as on iOS.
            creditLimit = f.creditLimit.takeIf { it > 0 },
            color = f.color,
            isDefault = f.isDefault,
        )
        viewModelScope.launch {
            cards.save(card)
            onSaved()
        }
    }
}
