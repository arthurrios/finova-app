//
//  AddCreditCardViewModel.swift
//  Finova
//

import Foundation

final class AddCreditCardViewModel {
    private let cardRepo = CreditCardRepository()
    private let creditCardService = CreditCardService()
    var cardToEdit: CreditCard?

    var isEditMode: Bool { cardToEdit != nil }

    func saveCard(
        name: String, lastFour: String, brandIndex: Int,
        closingDay: Int, dueDay: Int, creditLimit: Int?,
        cardColor: CardColor, isDefault: Bool
    ) -> Bool {
        guard let uid = AuthenticationManager.shared.currentUser?.uid else { return false }
        guard !name.isEmpty, lastFour.count == 4, closingDay >= 1, closingDay <= 28, dueDay >= 1, dueDay <= 28 else { return false }

        let brand = CardBrand.allCases[brandIndex]

        if isDefault {
            _ = cardRepo.clearDefault(userId: uid)
        }

        if var existing = cardToEdit {
            let datesChanged = existing.closingDay != closingDay || existing.dueDay != dueDay

            existing.name = name
            existing.lastFourDigits = lastFour
            existing.cardBrand = brand
            existing.closingDay = closingDay
            existing.dueDay = dueDay
            existing.creditLimit = creditLimit
            existing.cardColor = cardColor
            existing.isDefault = isDefault

            let updated = cardRepo.updateCard(existing)

            // Recalculate unpaid statement dates when closing/due day changed
            if updated && datesChanged {
                creditCardService.recalculateStatementDatesForCard(existing)
            }

            return updated
        } else {
            let card = CreditCard(
                id: nil, name: name, lastFourDigits: lastFour,
                cardBrand: brand, closingDay: closingDay, dueDay: dueDay,
                creditLimit: creditLimit, cardColor: cardColor,
                userId: uid, isDeleted: false, isDefault: isDefault,
                createdAt: Date(), updatedAt: Date()
            )
            return cardRepo.insertCard(card) != nil
        }
    }
}
