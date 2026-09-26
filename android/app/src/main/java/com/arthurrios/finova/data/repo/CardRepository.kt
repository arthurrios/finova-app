package com.arthurrios.finova.data.repo

import androidx.room.withTransaction
import com.arthurrios.finova.data.db.CreditCardEntity
import com.arthurrios.finova.data.db.FinovaDatabase
import com.arthurrios.finova.data.db.StatementEntity
import com.arthurrios.finova.domain.model.CardBrand
import com.arthurrios.finova.domain.model.CardColor
import com.arthurrios.finova.domain.model.CreditCard
import com.arthurrios.finova.domain.model.CreditCardStatement
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/** Port of CreditCardRepository plus AddCreditCardViewModel's save rules. */
class CardRepository(private val db: FinovaDatabase) {
    private val cards = db.creditCards()

    /** The cards the user can pick from: not deleted, newest first. */
    val activeCards: Flow<List<CreditCard>> = cards.observeActive().map { list -> list.map { it.toModel() } }

    suspend fun card(id: Long): CreditCard? = cards.getById(id)?.toModel()

    /**
     * Adds or updates a card. At most one card is the default, so making this one the default
     * clears the others first, as iOS does.
     */
    suspend fun save(card: CreditCard): Long = db.withTransaction {
        if (card.isDefault) cards.clearDefault()
        if (card.id == 0L) {
            cards.insert(card.toEntity())
        } else {
            val stored = cards.getById(card.id) ?: return@withTransaction card.id
            cards.update(card.toEntity(createdAt = stored.createdAt))
            card.id
        }
    }

    /** Soft delete: the card leaves every list, its purchases and statements stay. */
    suspend fun delete(id: Long) = cards.softDelete(id)
}

internal fun CreditCardEntity.toModel() = CreditCard(
    id = id,
    name = name,
    lastFourDigits = lastFourDigits,
    brand = CardBrand.fromKey(cardBrand),
    closingDay = closingDay,
    dueDay = dueDay,
    creditLimit = creditLimit,
    color = CardColor.fromKey(cardColor),
    isDefault = isDefault,
    isDeleted = isDeleted,
)

internal fun CreditCard.toEntity(createdAt: Long = System.currentTimeMillis()) = CreditCardEntity(
    id = id,
    name = name,
    lastFourDigits = lastFourDigits,
    cardBrand = brand.key,
    closingDay = closingDay,
    dueDay = dueDay,
    creditLimit = creditLimit,
    cardColor = color.key,
    isDeleted = isDeleted,
    isDefault = isDefault,
    createdAt = createdAt,
    updatedAt = System.currentTimeMillis(),
)

internal fun StatementEntity.toModel() = CreditCardStatement(
    id = id,
    creditCardId = creditCardId,
    closingDate = closingDate,
    dueDate = dueDate,
    totalAmount = totalAmount,
    isPaid = isPaid,
    paidDate = paidDate,
    paidAmount = paidAmount,
    isDatesOverridden = isDatesOverridden,
)
