package com.arthurrios.finova.domain.model

import java.time.LocalDate

/** Port of CreditCard.swift. Money in minor units. */
data class CreditCard(
    val id: Long = 0,
    val name: String,
    val lastFourDigits: String,
    val brand: CardBrand = CardBrand.Visa,
    /** 1…28. Purchases up to this day go on this month's statement. */
    val closingDay: Int,
    /** 1…28. */
    val dueDay: Int,
    val creditLimit: Long? = null,
    val color: CardColor = CardColor.Blue,
    val isDefault: Boolean = false,
    val isDeleted: Boolean = false,
)

/** Same cases and order as iOS; unknown keys read as [Other]. */
enum class CardBrand(val key: String) {
    Visa("visa"), Mastercard("mastercard"), Amex("amex"), Elo("elo"), Hipercard("hipercard"), Other("other");

    companion object {
        fun fromKey(key: String): CardBrand = entries.firstOrNull { it.key == key } ?: Other
    }
}

/** Same cases and order as iOS; unknown keys read as [Blue]. */
enum class CardColor(val key: String) {
    Black("black"), Purple("purple"), Blue("blue"), Green("green"),
    Gold("gold"), Platinum("platinum"), Red("red"), Orange("orange");

    companion object {
        fun fromKey(key: String): CardColor = entries.firstOrNull { it.key == key } ?: Blue
    }
}

/** Port of CreditCardStatement.swift: one billing cycle of a card. */
data class CreditCardStatement(
    val id: Long = 0,
    val creditCardId: Long,
    val closingDate: LocalDate,
    val dueDate: LocalDate,
    val totalAmount: Long = 0,
    val isPaid: Boolean = false,
    val paidDate: LocalDate? = null,
    val paidAmount: Long? = null,
    val isDatesOverridden: Boolean = false,
) {
    /**
     * Derived, never stored, as on iOS. A payment dated in the future reads as scheduled until
     * its day comes.
     */
    fun status(today: LocalDate): StatementStatus = when {
        isPaid -> if (paidDate != null && paidDate > today) StatementStatus.Scheduled else StatementStatus.Paid
        today > dueDate -> StatementStatus.Overdue
        today > closingDate -> StatementStatus.Closed
        else -> StatementStatus.Open
    }
}

enum class StatementStatus { Open, Closed, Paid, Overdue, Scheduled }
