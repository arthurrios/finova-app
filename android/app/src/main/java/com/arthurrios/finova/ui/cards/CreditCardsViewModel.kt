package com.arthurrios.finova.ui.cards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.arthurrios.finova.data.UserSettingsStore
import com.arthurrios.finova.data.repo.CardRepository
import com.arthurrios.finova.domain.model.CreditCard
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

/** Port of CreditCardsViewModel.swift. Null cards means still loading (no empty-state flash). */
class CreditCardsViewModel(
    private val cards: CardRepository,
    private val settings: UserSettingsStore,
) : ViewModel() {
    val list: StateFlow<List<CreditCard>?> = cards.activeCards
        .map<List<CreditCard>, List<CreditCard>?> { it }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val currencyCode: String get() = settings.currencyCode

    private val _valuesHidden = MutableStateFlow(settings.hideValues)
    val valuesHidden: StateFlow<Boolean> = _valuesHidden.asStateFlow()

    fun delete(card: CreditCard) {
        viewModelScope.launch { cards.delete(card.id) }
    }

    fun toggleValues() {
        val hidden = !_valuesHidden.value
        settings.hideValues = hidden
        _valuesHidden.value = hidden
    }
}
